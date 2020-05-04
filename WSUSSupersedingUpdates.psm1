#Requires -Modules UpdateServices
#https://blog.backslasher.net/finding-superseding-wsus-updates-in-wsus-powershell.html

#WSUS Products (Get-WsusProduct -UpdateServer (Get-WsusServer)).Product.Title

function Get-SupersedingUpdates
{
    param(
        [alias('KB','SearchString')]
        [parameter(Mandatory=$true, Position=0)]
        [string]$Knowledgebase,
        
        [alias('OS')]
        [validateset('Windows', 'Windows XP', 'Windows XP x64 Edition',
            'Windows Vista', 'Windows 7', 'Windows RT', 'Windows RT 8.1', 
            'Windows 8', 'Windows 8.1', 'Windows 10', 'Windows Server 2003',
            'Windows Server 2008', 'Windows Server 2008 R2', 'Windows Server 2012',
            'Windows Server 2012 R2', 'Windows Server 2016', 'Windows Server 2019')]
        [string[]]$OperatingSystem = 'Windows Server 2012 R2',

        [string]$WSUSServer = $env:COMPUTERNAME,
        [int]$PortNumber = '8530'
    )
    
    #If the WSUSServer value is different than localhost, runs against specified server & returns value to WSUSObj
    $WSUSObj = if($WSUSServer -ne $env:COMPUTERNAME)
               {Get-WsusServer -Name $WSUSServer -PortNumber $PortNumber}
               else{Get-WsusServer}

    #Grabs all updates that match the provided KB search string
    $AllUpdates = ($WSUSObj).SearchUpdates($KnowledgeBase)

    #Filters all the returned updates for ones that match the specified OperatingSystem values
    $FilteredUpdates =  $OperatingSystem | ForEach-Object{
                            $OpSys = $_
                            $AllUpdates | Where-Object {$_.ProductTitles -contains $OpSys}
                        }

    #Loops through each update in FilteredUpdates & searches for every update that supersedes them
    Foreach($Update in $FilteredUpdates)
    {
        $Update.GetRelatedUpdates('UpdatesThatSupersedeThisUpdate') | 
            Select-Object @{Name = 'SupersededUpdate'; Expression = {"KB$($Update.KnowledgeBaseArticles)"}},
                ProductTitles, IsSuperseded, HasSupersededUpdates, KnowledgeBaseArticles #, SecurityBulletins
    }
}
