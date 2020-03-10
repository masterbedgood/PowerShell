function Get-DuplicateReverseDNS
{   
    Get-DnsServerZone | Where-Object {$_.IsReverseLookupZone} | 
	ForEach-Object {
        $ZoneName = $_.ZoneName
        Get-DnsServerResourceRecord -ZoneName $ZoneName |
			Where-Object {$_.HostName -ne '@'} | 
			Group-Object HostName |
            Where-Object {$_.Count -gt 1} | Select-Object -ExpandProperty Group |
            Add-Member -MemberType NoteProperty -Name 'ZoneName' -Value $ZoneName -PassThru |
            Select-Object HostName,RecordType,@{Name='RecordData';Expression={$_.RecordData.PtrDomainName}},ZoneName
    } | %{
        $RZObject = $_
        $PTRDomainName = $RZObject.RecordData

        $PingTest = Test-NetConnection $PTRDomainName -WarningAction SilentlyContinue

            New-Object PSObject -Property @{
                DNSZoneName = $RZObject.ZoneName
                RecordValue = $PTRDomainName
                DNSHostName = $RZObject.HostName
                RecordType = $RZObject.RecordType
                IPv4Address = $PingTest.RemoteAddress
                PingSucceeded = $PingTest.PingSucceeded
            }
        }
}
