#Requires -Modules GroupPolicy,ActiveDirectory

param(
    [switch]$CheckIntune,
    [switch]$StartTask
)

#Gets all policies with 'Azure' or 'Intune' in the DisplayName
$EnrollmentGPOs = Get-GPO -All | Where-Object {$_.DisplayName -match 'azure' -or $_.DisplayName -match 'intune'}

#Empty object to append OUs w/EnrollmentGPOs linked
$LinkedOUs = @()

foreach($Policy in $EnrollmentGPOs)
{
    #Sets the GPOPath to the distinguished name of the policy
    $GPOPath = "cn={$($Policy.ID)},cn=policies,cn=system,$((Get-ADDomain).DistinguishedName)"

    #Searches for all OUs w/policy linked & appends values to LinkedOUs
    (Get-ADOrganizationalUnit -filter {LinkedGroupPolicyObjects -like $GPOPath}).DistinguishedName | ForEach-Object {
        $LinkedOUs += New-Object PSObject -Property @{
            OrgUnit = $_
            AppliedPolicy = $Policy.DisplayName
            PolicyID = $Policy.ID
        }
    }
}

#Groups OUs & assigns to new variable - prevents next foreach from running multiple times against each OU
$GroupedOUs = $LinkedOUs | Group-Object OrgUnit

#Empty object to append devices inside LinkedOUs
$LinkedDevices = @()

foreach($OrgUnit in $GroupedOUs)
{
    #Grabs all computers in OU & assigns to variable
    $ChildComputers = Get-ADComputer -filter * -SearchBase $OrgUnit.Name -Properties LastLogonDate,UserCertificate

    #Appends values to LinkedDevices object
    $ChildComputers | ForEach-Object {
        $LinkedDevices += New-Object PSObject -Property @{
            ComputerName = $_.Name
            LastLogonDate = $_.LastLogonDate
            AppliedPolicies = [string]::Join('; ', $OrgUnit.Group.AppliedPolicy)
            HasUserCert = [bool]($_.UserCertificate)
        }
    }
}

#If running interactively, attempts to check Intune to verify device enrollment status
if($CheckIntune)
{
    [int]$IntuneConnectLoops = 0
    #Loops until able to connect to Intune - attempts to install required module
    do{
        try{$IntuneDevices = Get-IntuneManagedDevice}
        catch{
            try{Connect-MSGraph | Out-Null}
            catch{
                Write-Warning "Failed to connect to Intune services - attempting to install Module:  Microsoft.Graph.Intune..."
                #https://www.powershellgallery.com/packages/Microsoft.Graph.Intune/6.1907.1.0
                Install-PackageProvider -Name NuGet -Force
                Install-Module -Name Microsoft.Graph.Intune -Scope AllUsers -Force
                $IntuneConnectLoops++
            }
        }
    }until($IntuneDevices -or $IntuneConnectLoops -eq 3)

    if($IntuneDevices)
    {
        $LinkedDevices | ForEach-Object {
            if($IntuneDevices.deviceName -Contains $_.ComputerName)
            {$_ | Add-Member -MemberType NoteProperty -Name 'IntuneEnrolled' -Value $true -Force}
            else{$_ | Add-Member -MemberType NoteProperty -Name 'IntuneEnrolled' -Value $false -Force}
        }
    }
}

if($StartTask)
{
    #Specifies the name & path for scheduled task
    $TaskPath = '\Microsoft\Windows\Workplace Join\'
    $TaskName = 'Automatic-Device-Join'
    
    $LinkedDevices | Add-Member -MemberType NoteProperty -Name TaskExecution -Value $null

    #Loops through each device the group policies apply to
    #foreach($Device in $LinkedDevices)
    $LinkedDevices | ForEach-Object{
        $Device = $_
        #Only kicks of scheduled task if device is not Intune enrolled
        if(!$Device.IntuneEnrolled)
        {
            #Only attempts to run remote command if the ping test is successful
            if(Test-NetConnection $Device.Computername -InformationLevel Quiet -WarningAction SilentlyContinue)
            {
                Write-Host "Attempting to execute scheduled task $TaskName on system $($Device.ComputerName)" `
                    -ForegroundColor Cyan

                try{
                    #Invoke command will fail if PSRemoting is not enabled on the remote machine
                    Invoke-Command -ComputerName $Device.ComputerName `
                        -Command {
                            Enable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
                            Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
                        } -ErrorAction Stop
                    Write-Host "Task executed successfully on $($Device.Computername)" -ForegroundColor Green
                    
                    #Updates device w/method of execution for scheduled task
                    $Device.TaskExecution = 'PSRemoting'
                }
                catch{
                    Write-Warning "Failed to execute scheduled task on $($Device.ComputerName) with Invoke-Command."
                    Write-Host "Attempting to execute scheduled task on $($Device.ComputerName) with schtasks.exe" -ForegroundColor Cyan

                    #Attempts remote enable & execution of scheduled task w/ schtasks.exe
                    $SchRun =   cmd /c `
                                    schtasks /S $Device.ComputerName /Change /TN $TaskPath$TaskName /Enable `
                                    '&&' `
                                        schtasks /run /S $Device.ComputerName /tn $TaskPath$TaskName

                    #Attempts remote execution w/schtasks.exe - if fails, attempts to run w/PSExec
                    #if("$(schtasks /run /S $Device.ComputerName /tn $TaskPath$TaskName)" -notmatch 'Success:')
                    if($SchRun -match "Attempted to run the scheduled task")
                    {
                        #Updates device w/method of execution for scheduled task
                        $Device.TaskExecution = 'schtasks.exe'
                    }
                    else{
                        Write-Warning "Failed to execute scheduled task on $($Device.ComputerName) with schtasks.exe"
                        Write-Host "Attempting to execute scheduled task on $($Device.ComputerName) with psexec.exe" -ForegroundColor Cyan
                        psexec \\$($Device.ComputerName) schtasks /Change /TN $TaskPath$TaskName /Enable
                        psexec \\$($Device.ComputerName) schtasks /run /tn $TaskPath$TaskName

                        #Updates device w/method of execution for scheduled task
                        $Device.TaskExecution = 'PSExec.exe'
                    }
                }
            }
            else{
                Write-Host "Skipping device $($Device.ComputerName) - ping test failed." -ForegroundColor Red
                
                #Updates device w/method of execution for scheduled task
                $Device.TaskExecution = 'PING_FAIL'
            }

            #Updates current loop obj w/updated $Device values
            $_ = $Device
        }
    }
}

$LinkedDevices
