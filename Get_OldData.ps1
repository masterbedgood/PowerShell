param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$FolderPath,
    [datetime]$Threshold = ([datetime]::Now.AddYears(-1)),
    [int64]$MinSizeBytes = 500000000,
    [string[]]$exclusionList = '$Recycle.Bin'
)

foreach($path in $FolderPath)
{
    Get-ChildItem -Path $FolderPath -Directory | Where-Object {$exclusionList -notcontains $_.Name} |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Recurse -Force |
            Where-Object {$_.Length -gt $MinSizeBytes -and (($_.LastWriteTime -lt $Threshold) -and `
            ($_.CreationTime -lt $Threshold) -and ($_.LastAccessTime -lt $Threshold))} |  
                Select-Object Name, Extension, CreationTime, LastWriteTime, LastAccessTime,
                @{n='SizeGB';e={[math]::Round(($_.Length / 1GB),2)}}, Length, FullName
        }
}
