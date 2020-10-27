# https://www.top-password.com/blog/find-bitlocker-recovery-key-from-active-directory/

#Requires -Modules ActiveDirectory

function Get-BitLockerRecoveryKeys
{
    param(
        [string]$compSearchBase = (Get-ADDomain).DistinguishedName,
        [alias('Computer','ADComputer')]
        [string[]]$ComputerName,
        [alias('AdminCred','Cred')]
        [pscredential]$Credential
    )

    # Collects all AD computers under the search base
    Write-Host "Collecting AD computer information, please wait." -ForegroundColor Magenta
    $ADComputers =  if($ComputerName){
                        foreach($computerValue in $ComputerName)
                        {Get-ADComputer $computerValue}
                    }
                    else{Get-ADComputer -Filter * -SearchBase $compSearchBase}

    # Initializes a hash table for splatting in Get-ADObject cmd inside foreach loop
    $getObjectHash = @{
        Filter = {objectclass -eq 'msFVE-RecoveryInformation'}
        SearchBase = $null
        Properties = 'msFVE-RecoveryPassword'
    }
    if($Credential){$getObjectHash.Credential = $Credential}

    [int]$numOfComputers = ($ADComputers | Measure-Object).Count
    [int]$currentProgress = 0

    # Loops through each returned computer object
    foreach($computer in $ADComputers)
    {
        $currentProgress++
        $percentComplete = (100*($currentProgress/$numOfComputers))
        Write-Progress -Activity 'Collecting BitLocker information' `
            -Status "Processing system $($computer.Name)" -PercentComplete $percentComplete

        # Initializes recPW string array and outputRecPW string to null @ each loop
        [string[]]$recPW = $null
        $outputRecPW = $null

        # Sets the SearchBase for getObjectHash to the current loop computer's distinguished name
        $getObjectHash.SearchBase = $computer.DistinguishedName

        # Searches AD computer object for BitLocker recovery key(s) & stores in recPW array
        $recPW = (Get-ADObject @getObjectHash).'msFVE-RecoveryPassword'

        # If a value exists in the recPW array, joins as single string so it can be exported to csv
        if($recPW){$outputRecPW = [string]::Join('; ',$recPW)}

        # Creates a return object w/computer name & recovery key
        New-Object psobject -Property @{
            ComputerName = $computer.Name
            RecoveryKey = $outputRecPW
        }
    }
}
