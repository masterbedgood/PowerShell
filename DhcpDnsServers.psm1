#Requires -Module DhcpServer
function Get-DhcpScopeDnsServers
{
    param (
        [string[]]$ServerName = ((Get-DhcpServerInDC).DNSName | 
            ForEach-Object{Get-ADComputer -Filter {DNSHostName -eq $_} | Where-Object {$_.Enabled}}).Name,
        #[string[]]$ServerName = (Get-DhcpServerInDC).DNSName,
        [pscredential]$AdminCreds
    )

    #Creates a hashtable for invoke command & appends admin creds to Credential param if a value exists
    $InvokeHash = @{
        ComputerName = $ServerName
    }
    if($AdminCreds){$InvokeHash.Add('Credential',$AdminCreds)}

    #Runs against all servers provided & provides admin creds if value exists
    Invoke-Command @InvokeHash -ScriptBlock {
        #Assigns the remote system's computername to the DHCPServer var for the return object
        $DHCPServer = $Env:COMPUTERNAME
        
        #Gets all DHCP IPv4 scopes & pipes to a Foreach loop
        Get-DhcpServerv4Scope | ForEach-Object{
            #Assigns the current Scope's OptionValue table to DHCPOptions var
            $DHCPOptions = Get-DHCPServerv4OptionValue -ScopeID $_.ScopeID
            #Selects ONLY the DHCP server Key valus in the DHCPOptions table
            $DNSServers = ($DHCPOptions | Where-Object {$_.Name -eq 'DNS Servers'}).Value

            #Creates a return object with the values specified
            New-Object PSObject -Property @{
                DHCPServer = $DHCPServer
                ScopeID = $_.ScopeID
                ScopeName = $_.Name
                ScopeStart = $_.StartRange
                ScopeEnd = $_.EndRange
                DNSServers = &{if(($DNSServers | Measure-Object).Count -gt 1){[string]::join('; ',$DNSServers)}
                    else{$DNSServers}
                }
            }
        }
    } | Select-Object DhcpServer,ScopeID,ScopeName,ScopeStart,ScopeEnd,DNSServers
}
