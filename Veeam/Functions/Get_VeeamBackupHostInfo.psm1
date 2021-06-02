Import-Module Veeam.Backup.PowerShell -Global -DisableNameChecking -Force

function Get-VeeamBackupHostInfo
{
    # Collects all current licensed hosts
    $vbrLicensedHosts = (Get-VBRInstalledLicense).SocketLicenseSummary.Workload.Name |
        Sort-Object -Descending

    # Collects all protection groups
    $vbrProtectionGroups = (Get-VBRProtectionGroup)

    # Creates an empty object for appending results
    $collectedRestorePoints = @()

    # Collects all backup & backup agent jobs
    $vbrBackupJobs = Get-VBRJob | Where-Object {$_.JobType -match '^Backup$|^EpAgentBackup$'} | 
        Sort-Object Name

    # Processes each backup job individually
    foreach($backupJob in $vbrBackupJobs)
    {
        # Grabs restore points for each object in each backup job
        foreach($restorePointGroup in (&{
                try{
                    if($backupJob.JobType -eq 'Backup'){Get-VBRRestorePoint -Backup $backupJob.Name | Group-Object VMName}
                    # If job type agent, throws error to can poll by device instead of job name - no agent results when polling by job name
                    else{throw 'Veeam Agent Backup'}
                }
                catch{
                    try{
                        # Resets vars on each loop
                        $loopBackupJobObjects = $null
                        [string[]]$loopObjectNames = $null

                        # Grabs all job objects under the current loop backup job & loops through each returned result
                        $loopBackupJobObjects = (Get-VBRJobObject -Job $backupJob.Name)
                        foreach($loopJobObject in $loopBackupJobObjects)
                        {
                            # If Location value found under protection group names, attempts to parse protection group members
                            if($vbrProtectionGroups.Name -contains $loopJobObject.Location)
                            {
                                # Resets group ID on each loop - matches protection group w/job object location & selects only ID
                                $loopProtectionGroup = $null
                                $loopProtectionGroup = ($vbrProtectionGroups | 
                                    Where-Object {$_.Name -eq $loopJobObject.Location}).ID
                                
                                # Grabs all discovered computers w/protection group matching the Location group's ID
                                $loopObjectNames += (Get-VBRDiscoveredComputer -ProtectionGroup $loopProtectionGroup).Name
                            }
                            # If loop object NOT match protection group, assumes it's a single machine
                            else{$loopObjectNames += $loopJobObject.Name}
                        }

                        # Attempts to grab restore points for all job objects & protection group children (where applicable)
                        Get-VBRRestorePoint -Name $loopObjectNames | Group-Object VMName
                    }
                    catch{
                        $collectedRestorePoints += New-Object PSObject -Property @{
                            BackupJob = $backupJob.Name
                            VMName = 'FAILED_TO_COLLECT_JOB_INFO'
                            RestorePoint = 'FAILED_TO_COLLECT_JOB_INFO'
                            RestorePointType = 'FAILED_TO_COLLECT_JOB_INFO'
                            IsConsistent = 'FAILED_TO_COLLECT_JOB_INFO'
                            HasIndex = 'FAILED_TO_COLLECT_JOB_INFO'
                            HostIsLicensed = $null
                            VMHost = 'FAILED_TO_COLLECT_JOB_INFO'
                            HostName = 'FAILED_TO_COLLECT_JOB_INFO'
                            NIC = 'FAILED_TO_COLLECT_JOB_INFO'
                        }
                        $null
                    }
                }
            }))
        {
            # Resetes temp restore point on each loop, then grabs latest restore for current loop object
            $tempRestorePoint = $null
            $tempRestorePoint = $restorePointGroup.Group | Sort-Object CreationTime -Descending | Select-Object -First 1

            # Appends desired return info to return object
            $collectedRestorePoints += New-Object PSObject -Property @{
                BackupJob = $backupJob.Name
                VMName = $tempRestorePoint.VMName
                RestorePoint = $tempRestorePoint.CreationTime
                RestorePointType = $tempRestorePoint.Type
                IsConsistent = $tempRestorePoint.IsConsistent
                HasIndex = $tempRestorePoint.HasIndex
                HostIsLicensed = (&{
                                    if($tempRestorePoint.AuxData.EsxName)
                                    {$vbrLicensedHosts -contains $tempRestorePoint.AuxData.EsxName}
                                    else{$null}
                                })
                VMHost = $tempRestorePoint.AuxData.EsxName
                HostName = $tempRestorePoint.AuxData.HostName
                NIC = ($tempRestorePoint.AuxData.NICs -Join '; ')
            }
        }
    }

    # Returns objects w/properties in desired order
    $collectedRestorePoints | 
        Select-Object BackupJob, VMName, RestorePoint, RestorePointType, 
            IsConsistent, HasIndex, HostIsLicensed, VMHost, HostName, NIC
}
