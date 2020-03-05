function Get-RecursiveDistroGroupMembers
{
    param(
        [string]$GroupName,
        [string]$Domain,
        [string]$AdminUsername,
        [String]$ExchangeHostname,
        [string]$ExchangeFQDN = "$ExchangeHostname.$Domain",
        [switch]$O365
    )

    #Defines warning preference as silentlycontinue to prevent warning messages except where specified otherwise
    $WarningPreference = "SilentlyContinue"

    #Checks to see if an active connection to Exchange already exists - if no, throws error & moves to catch block
    try{
        if($O365)
        {
            $Mailbox = Get-Mailbox -ResultSize 1 | Select-Object -First 1
            if(!$Mailbox)
            {throw}
        }
        else{
            $MBXServers = Get-MailboxServer -ErrorAction Stop
            if(!$MBXServers)
            {throw}
        }
    }
    catch{
        #Defines Exchange connection address
        if($O365)
        {$ExchangeAddress = 'https://outlook.office365.com/powershell-liveid/'}
        else{$ExchangeAddress = "http://$ExchangeFQDN/powershell/"}
        
        #Prompts for creds for Exchange connection
        $AdminCreds = Get-Credential "$Domain\$AdminUsername"
        
        #Defines Exchange connection params in hash table
        $SessionParams = @{
            ConfigurationName = 'Microsoft.Exchange'
            ConnectionUri = "$ExchangeAddress"
            ErrorAction = 'SilentlyContinue'
            Credential = $AdminCreds
        }


        $Session = New-PSSession @SessionParams
        if($Session){Import-PSSession $Session -AllowClobber | Out-Null}
        else{throw "Failed to connect to Exchange.";break}
    }

    <#
        Does an initial get of the distribution group & assigns to the DistroGroups variable
        Creates an empty property named 'RecursiveGroupMember' - this is where the child group names will be noted
    #>
    $DistroGroups = Get-DistributionGroupMember $GroupName | 
        Select-Object DisplayName,PrimarySmtpAddress,RecipientType, `
            @{n='RecursiveGroupMember'; e={$null}}
    
    #Do While continues to loop until all group objects have been replaced with their members
    do{
        $DistroGroups = $DistroGroups |
            #Foreach item in the DistroGroups object, checks to see if the type contains 'group'
            ForEach-Object{
                    #If the type is a 'group' that entry is replaced with all of that group's members
                    if($_.RecipientType -match 'group')
                    {
                        $RecrusiveGroupMember = $_.PrimarySmtpAddress
                        Get-DistributionGroupMember $RecrusiveGroupMember |
                            Select-Object DisplayName,PrimarySmtpAddress,RecipientType, `
                                @{n='RecursiveGroupMember'; e={$RecrusiveGroupMember}}
                    }
                    #If not a group, that object remains in the DistroGroups parent
                    else{$_}
                }
    }while($DistroGroups.RecipientType -match 'group')

    #Filters out duplicate objects (compares DisplayName AND RecursiveGroupMember values)
    $DistroGroups | Sort-Object DisplayName,RecursiveGroupMember -Unique

    #If a PSSession was created by the script, it is removed
    if($Session){Remove-PSSession $Session}
}
