#$Servers = Get-DbaRegServer -ExcludeGroup local | Select-Object -Property Name, ServerName -Unique
#$Credentials = Get-Credential -Message "SQL Credentials" -UserName 'E84947'

Invoke-DbaQuery -SqlInstance $Servers.ServerName -Query 'select @@servername, @@version' -SqlCredential $Credentials

Import-Module dbatools

Install-DbaFirstResponderKit -SqlInstance $Servers.ServerName -Database master -SqlCredential $Credentials -Verbose

