# Get List of Servers
$Servers = Import-Excel D:\GitHub-Office\Personal\Database-Server-List.xlsx | Select-Object -ExpandProperty 'DB Host (IP)'

# Get my Credentials
$cred = Get-Credential -UserName 'E84947' -Message 'SQL Credentials'

Import-Module dbatools;
foreach($srv in $Servers)
{
    $srvInfo = @()
    $srvInfo += Invoke-DbaQuery -SqlInstance $srv -SqlCredential $cred -Query "select @@servername as srv_name, '$srv' as [ip]"
    
    if($srvInfo.Count -gt 0) {
        Connect-DbaInstance -SqlInstance $srv -SqlCredential $cred | Add-DbaRegServer -Name $srvInfo.srv_name -Group 'All'
        "[$srv ~ $($srvInfo.srv_name)] added " | Write-Host -ForegroundColor Green
    }
    else {
        "[$srv] could not be reached" | Write-Host -ForegroundColor Red
    }
}

#$Regressing = Get-DbaRegServer -Group Regressing
$All = Get-DbaRegServer -Group All



<#

[172.31.16.131] could not be reached
[172.31.15.46] could not be reached
[172.31.18.222] could not be reached
[172.31.25.39] could not be reached
[172.31.25.33] could not be reached
[172.31.25.35] could not be reached
[172.31.25.128] could not be reached
#>
