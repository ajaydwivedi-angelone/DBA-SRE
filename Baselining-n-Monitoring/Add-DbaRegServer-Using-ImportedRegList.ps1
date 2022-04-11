# Get List of Servers
$Servers = Import-Excel D:\Ajay-Dwivedi\RegisteredServers.xlsx 

# Get my Credentials
$cred = Get-Credential -UserName 'DBMonitor' -Message 'SQL Credentials'

Import-Module dbatools;
$failedServers = @()
foreach($srv in $Servers)
{
    try {
        Connect-DbaInstance -SqlInstance $srv.ServerName -SqlCredential $cred | Add-DbaRegServer -Name $srv.Name
        "[$($srv.ServerName) ~ $($srv.Name)] added " | Write-Host -ForegroundColor Green
    }
    catch {
        "[$($srv.ServerName)] could not be reached" | Write-Host -ForegroundColor Red
        $failedServers += $srv.ServerName
    }
}

$failedServers | ogv -Title "Failed Servers"
