#https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/event.aspx?eventID=4625
#https://support.microsoft.com/en-us/help/243330/well-known-security-identifiers-in-windows-operating-systems

function Get-UserLockoutEvents
{
    [cmdletbinding()]
    param
    (
        [parameter(mandatory=$false,position=0)]
        [string[]]$Server = (Get-ADDomainController -Filter *).Name,
        [parameter(mandatory=$false,position=1)]
        [alias('Credential')]
        [pscredential]$AdminCred,
        [parameter(mandatory=$false,position=2)]
        [string]$ADUsername,

        [parameter(mandatory=$false,position=3)]
        [int]$MaxResultSize = 5,
        [parameter(mandatory=$false,position=4)]
        $StartDate = (Get-Date).AddDays(-3),
        [parameter(mandatory=$false,position=5)]
        $EndDate = (Get-Date)
    )

    $ScriptBlock = {
        param(
            $MaxResultSize,
            $StartDate,
            $EndDate,
            $ADUsername
        )

        Get-Eventlog security -InstanceId 4740 -Newest $MaxResultSize -After $StartDate -Before $EndDate |
            ForEach-Object { 
                if($_.Message -Match $ADUsername)
                {
                    New-Object PSObject -Property @{
                        TimeGenerated = $_.TimeGenerated
                        EventID = $_.InstanceID
                        Category = $_.CategoryNumber
                        ADUsername = $_.ReplacementStrings[0]
                        Domain = $_.ReplacementStrings[5]
                        UserSID= $_.ReplacementStrings[2]
                        CallerComputerName = $_.ReplacementStrings[1]
                    }
                }    
            }
    }

    $InvokeHash = @{
        ComputerName = $Server
        ArgumentList = $MaxResultSize,$StartDate,$EndDate,$ADUsername
        ScriptBlock = $ScriptBlock
    }
    if($AdminCred){$InvokeHash.Add('Credential',$AdminCred)}

    Invoke-Command @InvokeHash | 
        Select-Object ADUsername,CallerComputerName,TimeGenerated, 
            @{Name='LockoutServer';Expression={$_.PSComputerName}},
            UserSID,Domain,EventID,Category

    #To check within a certain date range, pipe Get-FailedLogins to Where-Object TimeGenerated -ge (Get-Date).AddDays(-1)
}




#https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/event.aspx?eventID=4625
#https://support.microsoft.com/en-us/help/243330/well-known-security-identifiers-in-windows-operating-systems

function Get-FailedLoginEvents
{
    
    [cmdletbinding()]
    param
    (
        [parameter(mandatory=$false,position=0)]
        [string[]]$Server = (Get-ADDomainController -Filter *).Name,
        [parameter(mandatory=$false,position=1)]
        [alias('Credential')]
        [pscredential]$AdminCred,
        [parameter(mandatory=$false,position=2)]
        [string]$ADUsername,
        [parameter(mandatory=$false,position=3)]
        [int]$MaxResultSize = 5,
        [parameter(mandatory=$false,position=4)]
        $StartDate = (Get-Date).AddDays(-3),
        [parameter(mandatory=$false,position=5)]
        $EndDate = (Get-Date)
    )
    
    $ScriptBlock = {
        param(
            $MaxResultSize,
            $StartDate,
            $EndDate,
            $ADUsername
        )

        Get-Eventlog security -InstanceId 4625,681,529 -Newest $MaxResultSize -After $StartDate -Before $EndDate | 
            ForEach-Object {
                if($_.Message -Match $ADUsername)
                {
                    New-Object PSObject -Property @{
                        TimeGenerated = $_.TimeGenerated
                        EventID = $_.InstanceId
                        Category = $_.CategoryNumber
                        ADUsername = $_.ReplacementStrings[5]
                        Domain = $_.ReplacementStrings[6]
                        UserSID= (($_.Message -Split '\r\n' | Select-String 'Security ID')[1] -Split '\s+')[3]
                        Workstation = $_.ReplacementStrings[13]
                        SourceIP = $_.ReplacementStrings[19]
                        Port = $_.ReplacementStrings[20]
                        FailureReason = $_.ReplacementStrings[8]
                        FailureStatus = $_.ReplacementStrings[7]
                        FailureSubStatus = $_.ReplacementStrings[9]
                    }
                } 
            }
    }

    $InvokeHash = @{
        ComputerName = $Server
        ArgumentList = $MaxResultSize,$StartDate,$EndDate,$ADUsername
        ScriptBlock = $ScriptBlock
    }
    if($AdminCred){$InvokeHash.Add('Credential',$AdminCred)}

    Invoke-Command @InvokeHash | Select-Object ADUsername,Workstation,SourceIP,Port,TimeGenerated,
        EventID,FailureReason,Category,FailureStatus,FailureSubStatus,Domain,
        @{Name='DomainController';Expression={$_.PSComputerName}}

    #Invoke-Command  -ComputerName $Server -Credential $Username -ArgumentList $MaxResultSize,$StartDate,$EndDate -ScriptBlock $ScriptBlock
}