#https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed

function Get-DotNetVersion
{
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$false, Position=0)]
        [string[]]$ComputerName,
        [alias('Credential')]
        [pscredential]$AdminCred
    )

    $ErrorActionPreference = 'Stop'

    $ScriptBlock = {
            $ReleaseKey = (Get-Childitem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').GetValue("Release")

            switch($releaseKey)
            {
                {$releaseKey -ge 528040} {$DNVersion = "4.8 or later"; break}
                {$releaseKey -ge 461808} {$DNVersion = "4.7.2"; break}
                {$releaseKey -ge 461308} {$DNVersion = "4.7.1"; break}
                {$releaseKey -ge 460798} {$DNVersion = "4.7"; break}
                {$releaseKey -ge 394802} {$DNVersion = "4.6.2"; break}
                {$releaseKey -ge 394254} {$DNVersion = "4.6.1"; break}
                {$releaseKey -ge 393295} {$DNVersion = "4.6"; break}
                {$releaseKey -ge 379893} {$DNVersion = "4.5.2"; break}
                {$releaseKey -ge 378675} {$DNVersion = "4.5.1"; break}
                {$releaseKey -ge 378389} {$DNVersion = "4.5"; break}
    
                default {$DNVersion = "No 4.5 or later version detected"}
            }

            [pscustomobject]@{
                    DotNetVersion = $DNVersion
                }
        }

    $InvokeHash = @{
        ScriptBlock = $ScriptBlock
        ComputerName = $ComputerName
    }
    if($AdminCred){$InvokeHash.Add('Credential',$AdminCred)}

    
    if(!$ComputerName)
    {&$ScriptBlock}
    else{Invoke-Command @InvokeHash | Select-Object DotNetVersion, PSComputerName}
}
