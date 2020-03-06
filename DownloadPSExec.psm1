<#
.SYNOPSIS
Checks if psexec is present in System32 - if not, downloads PSTools & extracts, moves psexec & psexec64 to System32
#>
function Get-PSExec
{
    [Alias('Download-PSExec')]
    param(
        [string]$DownloadPath = "$env:userprofile\Downloads\PSTools_$(Get-Date -format MM_dd_yyyy)",
        [string]$ArchivePath = "$DownloadPath\PSTools.zip",
        [string]$ExtractPath = "$DownloadPath\PSTools",
        [string]$PSExecURL = "https://download.sysinternals.com/files/PSTools.zip",
        [string]$PSExecDest = (cmd /c echo %systemroot%\System32)
    )

    #Attempts to run the following command as running user - if fails, moves on to CatchBlock and tries to runas admin
    $MoveCommand = {Move-Item -Path $ExtractPath\psexec.exe, $ExtractPath\psexec64.exe -Destination $PSExecDest -Force -ErrorAction Stop}
    #CatchBlock defines passed arguments as parameters to enable the same structure as $MoveCommand
    $CatchBlock = {param($ExtractPath,$PSExecDest) Move-Item -Path $ExtractPath\psexec.exe, $ExtractPath\psexec64.exe -Destination $PSExecDest -Force}

    #If the psexec.exe is not found in the Windows\System32 dir, downloads, unzips, & moves file
    if(!$(Test-Path $PSExecDest\psexec.exe))
    {
        #If the download path doesn't exist, creates it
        if(!$(Test-Path $ExtractPath)){New-Item -Path $ExtractPath -ItemType Directory}
        
        #Downloads PSTools.zip & extracts files
        Invoke-WebRequest $PSExecURL -OutFile $ArchivePath
        Expand-Archive -Path $ArchivePath -DestinationPath $DownloadPath\PSTools
        
        #Attempts to move psexec & psexec64 to System32 - if fails, runs as admin in catch block
        try{Invoke-Command -Command $MoveCommand}
        catch{
            #https://it-trials.github.io/scripting/passing-a-scriptblock-with-arguments-to-a-new-powershell-instance.html
            Write-Warning "Move-Item failed; attempting as admin."
            timeout -t 1 > $null
            Start-Process PowerShell.exe -Verb RunAs -ArgumentList "-Command Invoke-Command -ScriptBlock {$CatchBlock} -ArgumentList $ExtractPath,$PSExecDest" -Wait -WindowStyle Hidden
        }

        #Cleans up downloaded files
        Remove-Item $DownloadPath -Force -Recurse
    }
}
