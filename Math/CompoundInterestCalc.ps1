#Compound Interest Calculator
#https://mcpmag.com/articles/2018/01/10/math-with-powershell.aspx
#https://devblogs.microsoft.com/scripting/rounding-numberspowershell-style/
param(
    [double]$StartingPrincipal,
    [double]$PercentInterest,
    [double]$Years,
    [validateset('Annually','Semi-Annually','Quarterly','Bi-Monthly',
        'Monthly','Semi-Monthly','Bi-Weekly','Weekly','Daily','Custom')]
    [string]$Compounding = 'Annually'
    #[int]$CompoundRatePerYear = 1
)

switch($Compounding)
{
    'Annually' {$CompoundRatePerYear = 1}
    'Semi-Annually' {$CompoundRatePerYear = 2}
    'Quarterly' {$CompoundRatePerYear = 4}
    'Bi-Monthly' {$CompoundRatePerYear = 6}
    'Monthly' {$CompoundRatePerYear = 12}
    'Semi-Monthly' {$CompoundRatePerYear = 24}
    'Bi-Weekly' {$CompoundRatePerYear = 26}
    'Weekly' {$CompoundRatePerYear = 52}
    'Daily' {$CompoundRatePerYear = 365}

    default {
        do{
            #Validates CompoundRate input
            try{
                [int]$CompoundRatePerYear = Read-Host -Prompt "Please enter compounding rate per year (numeric value)"
                $CompRateIsValid = $true
            }
            catch{
                Write-Warning "You have provided an invalid value - a whole number is required."
                $CompRateIsValid = $false
            }
        }until($CompRateIsValid)
    }
}

[double]$InterestRate = $PercentInterest / 100
[double]$AdjustedTotal = $StartingPrincipal

#https://www.calculatorsoup.com/calculators/financial/compound-interest-calculator.php
$AdjustedTotal = $StartingPrincipal * `
    [math]::Pow((1 + ($InterestRate / $CompoundRatePerYear)),($CompoundRatePerYear * $Years))

New-Object PSObject -Property @{
    AdjustedTotal = [math]::round($AdjustedTotal,2)
    StartingPrincipal = [math]::round($StartingPrincipal,2)
    InterestEarned = [math]::round(($AdjustedTotal - $StartingPrincipal),2)
} | Select-Object AdjustedTotal, StartingPrincipal, InterestEarned
