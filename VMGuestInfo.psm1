#Requires -Module VMware.VimAutomation.Core

#Requires -Module VMware.VimAutomation.Core
#https://communities.vmware.com/thread/556784

function Find-VMByOS
{
    param(
        [parameter(mandatory=$false,position=0)]
        [alias('Architecture')]
        [string]$OSName
    )

    switch($OSName)
    {
        x86 {$OSName = '32-bit'}
        x64 {$OSName = '64-bit'}
    }

    Get-VM | Where-Object {$_.ExtensionData.Config.GuestFullname -match $OSName} |
        Select-Object `
            @{N='VMName';E={$_.Name}},
            @{N="ConfiguredOS";E={$_.ExtensionData.Config.GuestFullname}},
            @{N="RunningOS";E={$_.Guest.OsFullName}},
            @{N="PoweredOn";E={ $_.PowerState -eq "PoweredOn"}},
            @{N="disktype";E={(Get-Harddisk $_).Storageformat}}
}

<#
.SYNOPSIS
    Gets guest VMs hosted on connected vcenter servers.

.DESCRIPTION
    Utilizes vmware.PowerCLI to return all non-excluded VM guests on connected host servers.  PowerCLI may not function in PowerShell x64; it is recommended loading this module in PowerShell x86.

.EXAMPLE
    Get-AllVMs NoVDI, PoweredOff

    Returns all VM guests that do not have names beginning with VDI and are not powered off

.PARAMETER Exclusions
    Filters results to specified parameter value:
     - NoVDI = No VMs with VDI at the start of their name will be returned
     - NoNotes = No VMs with a null "Notes" value will be returned
     - PoweredOff = No VMs with a power status equal to 'PoweredOff' will be returned
     - NoLab = No VMs with a ResourcePool value like *lab* will be returned
     - All = Supersedes all input parameter values & excludes all powered off devices, devices with names beginning with VDI, devices with null Notes values, and devices with a ResourcePool value like *lab*

.LINK
    https://code.vmware.com/docs/9638/cmdlet-reference


#>
function Get-AllVMs
{
    param(
        #Specifies the Exclusion array variable & sets a validate set to restrict parameter values input by the user
        [ValidateSet('NoVDI','NoNotes','PoweredOff','NoLab','All')]
        [string[]]$Exclusions
    )

    #If the Exclusions parameter includes the value "All," the $Filter script block is set to note all exclusions - this supersedes any other entries.
    if($Exclusions -eq 'All')
    {
        $Filter = {$_.Name -notlike 'vdi*' -and $_.PowerState -notlike 'PoweredOff' -and $_.ResourcePool -notlike '*lab*' -and $_.Notes}
    }

    #If the Exclusions parameter does not include the value "All," the switch checks all input values & updates the $Filter variable with all relevant exclusions
    else
    {
        Switch ($Exclusions)
        {
            NoVDI {$Filter += "`n"+'$_.Name -notlike ' + "'vdi*'"}
            NoNotes {$Filter += "`n" + '$_.Notes'}
            PoweredOff {$Filter += "`n" + '$_.PowerState -notlike '+ "'PoweredOff'"}
            NoLab {$Filter += "`n" + '$_.ResourcePool -notlike ' + "'*lab*'"}

            #If no exclusions are defined, the default value of the $Filter script block is to return VMs that have a non-null Name value
            default {$Filter = {$_.Name}}
        }

        #Declares int $i to equall the number of Exclusions entered
        [int]$i = ($Exclusions.Count)

        #Splits $Filter at line break character & creates a new $CombinedFilter - joins split $Filter values with -and while $i is greater than 0
        $Filter -Split "\n" | foreach{
            if($_ -and $i -gt 0){$CombinedFilter += "$_ -and"}
            elseif($_){$CombinedFilter += $_}
            $i --
        }

        #Creates a script block from the $CombinedFilter string & assigns to the $Filter variable
        $Filter = [scriptblock]::Create($CombinedFilter)
    }

    #Gets VMs & returns all non-excluded objects
    Get-VM | Select Name, PowerState, HardwareVersion, ID, VMHost, ResourcePool, Notes, DatastoreIdList | 
    Where-Object $Filter | % { 
        $ExpandedNotes = ((($_ | Select-Object -ExpandProperty Notes) -split '\n' | Select-String 'Veeam Backup') `
            -split ', ' -replace "Veeam Backup:\s+" -replace '\[' -replace '\]')

        $DatastoreID = ($_ | Select-Object -ExpandProperty DatastoreIdList)
        $DataStore = (Get-Datastore | Where-Object {$_.ID -match $DatastoreID})

        $VeeamTime = (($ExpandedNotes | Select-String 'Time:') -replace 'Time: ')
        [string]$VeeamJobName = (($ExpandedNotes | Select-String 'Job name:') -replace 'Job name: ')
        [string]$VeeamBackupFolder = (($ExpandedNotes | Select-String 'Backup folder:') -replace 'Backup folder: ')

        #Parses Notes data & creates a new PSObject that can be piped to additional cmds
        New-Object psobject -Property @{
            Name = $_.Name
            PowerState = $_.PowerState
            HardwareVersion = $_.HardwareVersion
            ID = $_.ID
            VMHost = $_.VMHost
            ResourcePool = $_.ResourcePool
            VeeamJobName = $VeeamJobName
            LastSuccessfulBackup = %{if($VeeamTime){[datetime]$VeeamTime} else{$null}}
            VeeamBackupFolder = $VeeamBackupFolder
            DatastoreID = $DatastoreID
            Datastore = $DataStore
        }
    }
}


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
