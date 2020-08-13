# http://vstrong.info/2013/08/20/who-created-these-vm-snapshots/
# Gets all non-Citrix / VDI VMs and snapshot events
Get-VM | Where-Object {$_.Name -notmatch 'vdi' -and $_.Name -notmatch 'citri'} | 
    Get-Snapshot | ForEach-Object{
        $Snapshot= $_
        
        $CreatedBy = (Get-VIEvent -Entity $Snapshot.VM -Types Info -Finish $Snapshot.Created -MaxSamples 1).UserName
        
        if(!$CreatedBy){
            $Start = $SnapShot.Created.AddDays(-1)
            $Finish = $SnapShot.Created.AddDays(1)
            $CreatedBy = Get-VIEvent -Entity $Snapshot.VM -Start $Start -Finish $Finish | 
                            Where-Object {$_.Info.Name -eq 'CreateSnapshot_Task'} | 
                                Select-Object -ExpandProperty UserName
            if(!$CreatedBy){$CreatedBy = 'EVENT_OUTSIDE_SCOPE'}
        }
        
        New-Object psobject -Property @{
        VM = $Snapshot.VM
        Description = $Snapshot.Description
        Name = $SnapShot.Name
        CreatedBy = $CreatedBy
        CreatedOn = $Snapshot.Created
        SizeGB = [math]::Round($Snapshot.SizeGB,2)
        }
    } | Select-Object VM, Description, Name, CreatedBy, CreatedOn, SizeGB
