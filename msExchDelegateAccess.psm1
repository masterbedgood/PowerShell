#Requires -Modules ActiveDirectory

function Find-DelegatedMailboxes
{
    param(
        [parameter(Mandatory=$true, position=0)]
        [string]$ADUsername,
        $SearchBase = "DC=$($Env:USERDNSDOMAIN -replace '\.',',DC=')"
    )

    Get-ADUser -Filter {msExchDelegateListLink -like '*'} `
        -SearchBase $SearchBase -Properties msExchDelegateListLink | 
            Where-Object {$_.msExchDelegateListLink -contains (Get-ADUser $ADUsername).DistinguishedName} |
            ForEach-Object {
                $DelegatedADAccount = $_

                New-Object psobject -Property @{
                    SamAccountName = $DelegatedADAccount.SamAccountName
                    DelegatedUsers = $DelegatedADAccount.msExchDelegateListLink |
                                        ForEach-Object{(Get-ADUser $_).SamAccountName}
                }
            }
}
