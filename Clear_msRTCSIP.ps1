#Lync on-prem to Teams environment; clear msRTCSIP properties to resolve issues w/messaging external recipients
Get-ADUser -filter * -Properties * | ForEach-Object {
    $UserObject = $_
    $Props = ($UserObject | Get-Member -MemberType Properties | Where-Object {$_.Name -match 'msRTCSIP'}).Name
    Set-ADUser $UserObject.SamAccountName -Clear $Props
}
