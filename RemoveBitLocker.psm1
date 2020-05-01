function Remove-BitLockerEncryption
{
    [alias('Decrypt-Volume')]
    param(
        [char]$DriveLetter = 'C'
    )

    #Turns off BitLocker encryption on specified volume
    manage-bde -off "$($DriveLetter):"

    #Loops through progress & displays percentage complete until 100%
    do{
        #Percent is equal to the actual percentage encrypted
        [int]$Percent = ((manage-bde -status "$($DriveLetter):" |select-string 'Percentage Encrypted') -split '\s+' |Select-String '%')-replace '%'
        #Inverts percent to display percentage decrypted
        $Percent = 100 - $Percent
        #Displays progress status
        Write-Progress -Activity 'Decrypting Drive' -Status "$Percent% complete" -PercentComplete $Percent
        #Pauses 15 seconds before next retry
        Start-Sleep -Seconds 15
    }until($Percent -match '100')
}
