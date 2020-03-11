#Requires -Module VMware.VimAutomation.Core
<#
.SYNOPSIS
    Gets information of specified VMs hosted on connected vcenter servers.

.DESCRIPTION
    Utilizes vmware.PowerCLI to return information of specified VM guests on connected host servers.
    PowerCLI may encounter issues when run in PowerShell x64.
    If issues are encountered, it is recommended loading this module in PowerShell x86.

.EXAMPLE
    Get-VMInfo VM1, TestVM

    Returns information of VM guests VM1 and TestVM

.LINK
    https://code.vmware.com/docs/9638/cmdlet-reference
#>
function Get-VMInfo
{
    param(
        #Specifies the VMs to get information for - defaults to wildcard to return all
        [string[]]$VMs = '*',
        [validateset('DiskTypes','HardDisks','HardwareVersion','ResourcePool',
            'DataStores','ConfiguredOS','IPv6',
            'VeeamBackupFolder','DatastoreIDs','*')]
        [string[]]$Properties
    )
    $DefaultProps = ('Name','VMID','RunningOS','PowerState','IPv4',
            'VMHost','VeeamJobName','LastSuccessfulBackup')
    
    #If values exist in properties, prepends DefaultProps to additional properties & assigns to ReturnProps
    if($Properties)
    {
        $ReturnProps = $DefaultProps + ($Properties | Sort-Object -Unique)
        #If ReturnProps includes a '*', assigns ReturnProps only * value
        switch($ReturnProps)
        {
            * {$ReturnProps = '*'}
        }
    }
    #If no values in Properties, assigns only DefaultProps to ReturnProps
    else{$ReturnProps = $DefaultProps}

    #Gets VMs & returns all non-excluded objects
    Get-VM $VMs | Select-Object Name, PowerState, HardwareVersion, ID, VMHost, ResourcePool, Notes, DatastoreIdList,ExtensionData,Guest |
    ForEach-Object { 
        #Expands Notes property & assigns to ExpandedNotes var for parsing
        $ExpandedNotes = ((($_ | Select-Object -ExpandProperty Notes) -split '\n' | Select-String 'Veeam Backup') `
            -split ', ' -replace "Veeam Backup:\s+" -replace '\[' -replace '\]')

        #Gets all DataStore IDs for VM object
        $DatastoreIDs = ($_ | Select-Object -ExpandProperty DatastoreIdList)
        #Gets all DataStores for VMObject
        $DataStores = $DatastoreIDs | ForEach-Object {
                $DatID = $_
                Get-Datastore | Where-Object {$_.ID -match $DatID}
            }

        #Gets all HardDisks connected to VM
        $HardDiskObjects = (Get-HardDisk $_.Name)
        #Gets storage format for all attached HardDisks
        $DiskTypes = $HardDiskObjects.StorageFormat
        #Gets file names of all attached hard disks
        $HardDiskNames = $HardDiskObjects.FileName

        #Parses Notes property for Veeam backup information
        $VeeamTime = (($ExpandedNotes | Select-String 'Time:') -replace 'Time: ')
        [string]$VeeamJobName = (($ExpandedNotes | Select-String 'Job name:') -replace 'Job name: ')
        [string]$VeeamBackupFolder = (($ExpandedNotes | Select-String 'Backup folder:') -replace 'Backup folder: ')

        #Parses Notes data & creates a new PSObject that can be piped to additional cmds
        $ReturnObj = New-Object psobject -Property @{
            Name = $_.Name
            PowerState = $_.PowerState
            HardwareVersion = $_.HardwareVersion
            VMID = $_.ID
            VMHost = $_.VMHost
            ResourcePool = $_.ResourcePool
            VeeamJobName = $VeeamJobName
            LastSuccessfulBackup = %{if($VeeamTime){[datetime]$VeeamTime} else{$null}}
            VeeamBackupFolder = $VeeamBackupFolder
            DatastoreIDs = $DatastoreIDs
            Datastores = $DataStores
            HardDisks = $HardDiskNames
            DiskTypes = $DiskTypes
            RunningOS = $_.Guest.OSFullName
            ConfiguredOS = $_.ExtensionData.Config.GuestFullName
            IPv6 = $_.Guest.IPAddress | Where-Object {$_ -match ':'}
            IPv4 = $_.Guest.IPAddress | Where-Object {$_ -notmatch ':'}
        }
    
        #Returns the object with only selected properties
        $ReturnObj | Select-Object $ReturnProps
    }
}
