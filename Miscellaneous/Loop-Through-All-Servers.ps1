Import-Module dbatools

$sqlInstanceInfo = @"
SELECT [domain_name] = DEFAULT_DOMAIN(), s.is_clustered, srv_name = @@servername, [ip] = CONNECTIONPROPERTY('local_net_address'),
		[service_name] = s.servicename, [startup_type] = s.startup_type_desc, s.service_account
FROM sys.dm_server_services s
WHERE s.servicename like 'SQL Server (%)'
"@

Get-DbaRegServer -Group All | Invoke-DbaQuery -Query $sqlGetLinkedServer | ogv

#Get-DbaRegServer -Group All | ?{$_.ServerName -in @('172.31.18.215','196.1.115.239')} | Invoke-DbaQuery -Query $sqlInstanceInfo | ogv

