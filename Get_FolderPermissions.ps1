#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
   Creates a list of permissions for a specified folder - pulls recursive members if permitted obj is AD group.
.EXAMPLE
   Get-FolderPermissions '\\TestServer\Share01\Folder\'

   Will return all permissions on folder \\TestServer\Share01\Folder
#>

param(
    #Parent directory to return all child directories
    [Parameter(Mandatory=$true,Position=0)]
    [string]$folderPath
)

# https://stackoverflow.com/a/44191424/13853660
# Clones an input object - useful for cloning the ACL objects since they don't have a clone method
[scriptblock]$cloneObj = {
    param($objectToClone)
    $newobj = New-Object -TypeName PsObject
    $objectToClone.psobject.Properties | 
        ForEach-Object{Add-Member -MemberType NoteProperty -InputObject $newobj -Name $_.Name -Value $_.Value}
    $newobj
}

# Filter for creating the return object from pipeline input
filter createReturnObject {
    $inputObject = $_

    [PSCustomObject][ordered]@{
        FolderPath              = $folderPath
        PermittedUserOrGroup    = $inputObject.PermittedUserOrGroup
        PermittedObjectType     = $inputObject.PermittedOBjectType
        MemberOfGroup           = $inputObject.MemberOfGroup
        FileSystemRights        = $inputObject.FileSystemRights
        AccessControlType       = $inputObject.AccessControlType
        IsInherited             = $inputObject.IsInherited
    }
}

# Filter for checking object type before creating the return object
# If piped object is group, filter will grab all group members & recursively call itself on each member for processing
filter parseFolderPermissions {
    $inputObject = $_
    [string]$samAccountName = $null
    $adObjectInfo = $null
    
    # Excludes NT Auth, Builtin, & creator owner entries from AD queries
    if(!($inputObject.IdentityReference -match '^NT AUTHORITY\\|^BUILTIN\\|^CREATOR OWNER$'))
    {
        $samAccountName = $inputObject.IdentityReference -replace '^.*?\\'
        $adObjectInfo = Get-ADObject -Filter {SamAccountName -eq $samAccountName} -Properties SamAccountName
    }
    
    if($adObjectInfo)
    {
        $inputObject.PermittedUserOrGroup = $adObjectInfo.SamAccountName
        $inputObject.PermittedObjectType = $adObjectInfo.ObjectClass

        if($adObjectInfo.ObjectClass -eq 'group')
        {
            [string[]]$recursiveMembers = $null

            # Returns the group ACL info
            $inputObject | createReturnObject

            # Grabs all the recursive members of the AD group & loops through them calling this filter recursively
            $recursiveMembers = (Get-ADGroupMember $samAccountName -Recursive).SamAccountName
            foreach($recursiveMember in $recursiveMembers)
            {
                # Resets the tempObject on each loop then clones the object input from the pipeline - 
                #   this avoids overwriting the pipeline data
                $tempObject = $null
                $tempObject = &$cloneObj -objectToClone $inputObject
                $tempObject.identityReference = $recursiveMember
                $tempObject.MemberOfGroup = $adObjectInfo.SamAccountName
                $tempObject | parseFolderPermissions
            }
        }
        else{$inputObject | createReturnObject}
    }
    else{
        $inputObject.PermittedUserOrGroup = $inputObject.IdentityReference
        $inputObject.PermittedObjectType = 'LocalUserOrGroup'
        $inputObject | createReturnObject
    }
}

# Grabs folder permissions & appends new properties for the pipeline filters
(Get-Acl $folderPath).Access |
    Add-Member -MemberType 'NoteProperty' -Name 'MemberOfGroup' -Value $null -PassThru |
        Add-Member -MemberType 'NoteProperty' -Name 'PermittedUserOrGroup' -Value $null -PassThru |
            Add-Member -MemberType 'NoteProperty' -Name 'PermittedObjectType' -Value $null -PassThru |
                parseFolderPermissions
