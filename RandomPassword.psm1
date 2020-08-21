#https://poshhelp.wordpress.com/2017/01/30/why-you-should-stop-using-generatepassword/
<#
.SYNOPSIS
    Generates a random password of the specified length
#>
Function New-RandomPassword
{
    param(
        [validateScript({$_ -ge 8})] 
        [int]$Length = 10
    )

    # Special character set for complexity requirements
    $SpecialCharString = '-*@)$^%(_!/|.'
    $SpecialChars = $SpecialCharString.ToCharArray()
    # Number character set for complexity requirements
    $NumberString = '0123456789'
    $Numbers = $NumberString.ToCharArray()

    Add-Type -AssemblyName System.Web
    $CharSet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ$($NumberString)$($SpecialCharString)".ToCharArray()
    #Removed some special characters to resolve conflict in setting AD password without specifying an escape character
    #$CharSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{]+-[*=@:)}$^%;(_!&#?>/|.'.ToCharArray()
    #Index1s 012345678901234567890123456789012345678901234567890123456789012345678901234567890123456
    #Index10s 0 1 2 3 4 5 6 7 8
 
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($Length)
 
    $rng.GetBytes($bytes)
 
    $Return = New-Object char[]($Length)
 
    For ($i = 0 ; $i -lt $Length ; $i++)
    {
        $Return[$i] = $CharSet[$bytes[$i]%$CharSet.Length]
    }

    # If the return object ($Return array joined as string) does not contain special characters
    if(($Return -join '') -notmatch "[$SpecialChars]")
    {
        # New RNG for special characters
        $SpecRNG = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $SpecBytes = New-Object byte[]($Length)
        $SpecRNG.GetBytes($SpecBytes)
        
        # Loops until the SpecialPosition in the Return array doesn't match a Number value
        do{
            $Script:SpecialPosition = Get-Random -Minimum 0 -Maximum $Length
        }until($Return[$SpecialPosition] -notmatch "[$Numbers]")
        
        # Updates the Return array @ SpecialPosition index with a random special character
        $Return[$SpecialPosition] = $SpecialChars[$SpecBytes[$SpecialPosition]%$SpecialChars.Length]
    }
    # If the return object ($Return array joined as string) does not contain Numbers
    if(($Return -join '') -notmatch "[$Numbers]")
    {
        # New RNG for Numbers
        $NumRNG = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $NumBytes = New-Object byte[]($Length)
        $NumRNG.GetBytes($NumBytes)
        
        # Loops until the SpecialPosition in the Return array doesn't match a SpecialCharacter value
        do{
            $Script:NumPosition = Get-Random -Minimum 0 -Maximum $Length
        }until($NumPosition -ne $SpecialPosition -and ($Return[$NumPosition] -notmatch "[$SpecialChars]"))
        
        # Updates the Return array @ NumPosition index with a random number character
        $Return[$NumPosition] = $Numbers[$NumBytes[$NumPosition]%$Numbers.Length]
    }

    # Returns the joined Return array as a single string object
    (-join $Return)
}
