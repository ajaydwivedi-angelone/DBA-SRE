use DBA_Admin
go

/*
	Version -> 2024-07-08
	2024-07-08 - #01 - Initial Draft of Inventory Servers
	-----------------

	https://github.com/imajaydwivedi/SQLMonitor/issues/10

	*** Self Pre Steps ***
	----------------------
	1) Python, Git needs to be installed on Inventory server
	2) Credential Manager needs to be installed on Inventory Server

	*** Steps in this Script ****
	-----------------------------
	1) Create table dbo.sma_servers
	2) Create table dbo.sma_sql_server_extended_info
	3) Create table dbo.sma_sql_server_hosts
	4) Create table dbo.sma_hadr_ag
	5) Create table dbo.sma_hadr_sql_cluster
	6) Create table dbo.sma_hadr_mirroring
	7) Create table dbo.sma_hadr_log_shipping
	8) Create table dbo.sma_hadr_transaction_replication_publishers
	9) Create table dbo.sma_applications
	10) Create table dbo.sma_applications_server_xref
	11) Create table dbo.sma_applications_database_xref
	12) Create table dbo.sma_errorlog
	13) Create view dbo.sma_sql_servers	
*/

IF DB_NAME() = 'master'
	raiserror ('Kindly execute all queries in [DBA] database', 20, -1) with log;
go

/* ***** 1) Create table dbo.sma_servers ***************************** */
	/*
		ALTER TABLE dbo.sma_servers SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_servers
		go
		drop table dbo.sma_servers_history
		go
	*/	
create table dbo.sma_servers
(
	[server] varchar(125) not null,
	[server_port] varchar(10) null,
	[domain] varchar(80) null,
	[friendly_name] varchar(500) null,
	[stability] varchar(20) not null default 'dev',
	[priority] tinyint not null default '2',
	[server_type] varchar(20) not null default 'SQLServer',
	[has_hadr] bit not null default 0,
	[hadr_strategy] varchar(50) null default 'standalone',
	[backup_strategy] varchar(255) null default 'Native',
	[server_owner_email] varchar(500) null,
	[rdp_credential] varchar(125) null,
	[sql_credential] varchar(125) null,
	[is_monitoring_enabled] bit not null default 0,
	[is_maintenance_scheduled] bit not null default 0,
	[is_tde_implemented] bit not null default 0,
	[enabled_restart_schedule] bit not null default 0, /* Remove in General */
	[is_onboarded] bit not null default 1,
	[is_decommissioned] bit not null default 0,
	[more_info_JSON] varchar(2000) null,
	[created_date_utc] datetime2 not null default getutcdate(),
	[updated_date_utc] datetime2 not null default getutcdate(),
	[updated_by] varchar(255) not null default suser_name()

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_servers] primary key clustered ([server])
	,constraint [chk_stability] check ( [stability] in ('dev', 'uat', 'qa', 'stg', 'prod') )
	,constraint [chk_priority] check ([priority] in (0,1,2,3,4,5))
	,constraint [chk_server_type] check ([server_type] in ('SQLServer','PostgreSQL'))
	,constraint [chk_hadr_strategy] check ([hadr_strategy] in ('standalone','mirroring','logshipping','sqlcluster','ag'))
	,constraint [chk_backup_strategy] check ([backup_strategy] in ('Native','CommVault','Rubrik','Redgate','VSS'))

	,constraint [fk_sma_servers__server] foreign key ([sql_instance]) references dbo.instance_details ([sql_instance])
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_servers_history));
go

alter table dbo.sma_servers
	add constraint [fk_sma_servers__server] foreign key ([sql_instance]) references dbo.instance_details ([sql_instance])
go


/* ***** 2) Create table dbo.sma_sql_server_extended_info ***************************** */
	/*
		ALTER TABLE dbo.sma_sql_server_extended_info SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_sql_server_extended_info
		go
		drop table dbo.sma_sql_server_extended_info_history
		go
	*/
create table dbo.sma_sql_server_extended_info
(
	[server] varchar(125) not null,
	[at_server_name] varchar(125) not null,
	[server_name] varchar(125) not null,
	[server_ips_CSV] varchar(125) null,
	[alias_names] varchar(100) null,
	[product_version] varchar(30) not null,
	[edition] varchar(50) not null,
	[has_PII_data] bit not null default 0,
	[total_physical_memory_kb] bigint null,
	[cpu_count] smallint not null,
	[rpo_worst_case_minutes] int null,
	[rto_minutes] int null,
	[data_center] varchar(125) null,
	[availability_zone] varchar(125) null,
	[avg_utilization_JSON] varchar(2000) null,
	[ticket] varchar(2000) null,
	[purpose] varchar(2000) null,
	[known_challenges] varchar(2000) null,
	[remarks] varchar(2000) null,
	[more_info_JSON] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_sql_server_extended_info] primary key clustered ([server])
	,index [uq_at_server_name] unique ([at_server_name])
	,index [uq_server_name] unique ([server_name])
	,constraint [fk_sma_sql_server_extended_info__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_sql_server_extended_info_history));
go

alter table dbo.sma_sql_server_extended_info
	add constraint chk_data_center check ([data_center] in ('GPX','NTT'))
go

/* ***** 3) Create table dbo.sma_sql_server_hosts ***************************** */
	/*
		ALTER TABLE dbo.sma_sql_server_hosts SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_sql_server_hosts
		go
		drop table dbo.sma_sql_server_hosts_history
		go
	*/
create table dbo.sma_sql_server_hosts
(
	[server] varchar(125) not null,
	[host_name] varchar(125) not null,
	[host_ips] varchar(80) not null,
	[host_distribution] varchar(200) null,
	[processor_name] varchar(200) null,
	[ram_mb] bigint null,
	[cpu_count] smallint null,
	[wsfc_name] varchar(125) null,
	[wsfc_ip1] varchar(15) null,
	[wsfc_ip2] varchar(15) null,
	[is_quarantined] bit not null default 0,
	[is_decommissioned] bit not null default 0,
	[more_info_JSON] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_sql_server_hosts] primary key clustered ([server],[host_name])
	,constraint [fk_sma_sql_server_hosts__server] foreign key ([server]) references dbo.sma_servers ([server])
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.sma_sql_server_hosts_history));
go


/* ***** 4) Create table dbo.sma_hadr_ag ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_ag SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_ag
		go
		drop table dbo.sma_hadr_ag_history
		go
	*/
create table dbo.sma_hadr_ag
(
	[server] varchar(125) not null,
	[ag_name] varchar(80) not null,
	[ag_replicas_CSV] varchar(2000) not null,
	[preffered_role] varchar(50) not null default 'Secondary',
	[current_role] varchar(50) not null default 'Secondary',
	[ag_databases_CSV] varchar(2000) null,
	[ag_listener_01_name] varchar(80) null,
	[ag_listener_01_ip1] varchar(15) null,
	[ag_listener_01_ip2] varchar(15) null,
	[ag_listener_02_name] varchar(80) null,
	[ag_listener_02_ip1] varchar(15) null,
	[ag_listener_02_ip2] varchar(15) null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_ag] primary key clustered ([server],[ag_name])
	,index [ag_listener_01_ip1] nonclustered ([ag_listener_01_ip1])
	,index [ag_listener_01_ip2] nonclustered ([ag_listener_01_ip2])
	,index [ag_listener_02_ip1] nonclustered ([ag_listener_02_ip1])
	,index [ag_listener_02_ip2] nonclustered ([ag_listener_02_ip2])
	,constraint [fk_sma_hadr_ag__server] foreign key ([server]) references dbo.sma_servers ([server])
	,constraint [chk_preffered_role] check ( [preffered_role] in ('Primary', 'Secondary') )
	,constraint [chk_current_role] check ( [current_role] in ('Primary', 'Secondary') )
)
with (system_versioning = on (history_table = dbo.sma_hadr_ag_history));
go


/* ***** 5) Create table dbo.sma_hadr_sql_cluster ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_sql_cluster SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_sql_cluster
		go
		drop table dbo.sma_hadr_sql_cluster_history
		go
	*/
create table dbo.sma_hadr_sql_cluster
(
	[server] varchar(125) not null,
	[sql_cluster_network_name] varchar(125) not null,
	[preferred_owner_node] varchar(50) null,
	[sql_cluster_ip1] varchar(15) null,
	[sql_cluster_ip2] varchar(15) null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_sql_cluster] primary key clustered ([server])
	,index [sql_cluster_network_name] nonclustered ([sql_cluster_network_name])
	,index [sql_cluster_ip1] nonclustered ([sql_cluster_ip1])
	,index [sql_cluster_ip2] nonclustered ([sql_cluster_ip2])
	,constraint [fk_sma_hadr_sql_cluster__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_sql_cluster_history));
go


/* ***** 6) Create table dbo.sma_hadr_mirroring ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_mirroring SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_mirroring
		go
		drop table dbo.sma_hadr_mirroring_history
		go
	*/
create table dbo.sma_hadr_mirroring
(
	[server] varchar(125) not null,
	[preferred_role] varchar(125) not null default 'Principal',
	[mirroring_partner_server] varchar(125) not null,
	[witness_server] varchar(125) null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_mirroring] primary key clustered ([server])
	,constraint [fk_sma_hadr_mirroring__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_mirroring_history));
go


/* ***** 7) Create table dbo.sma_hadr_log_shipping ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_log_shipping SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_log_shipping
		go
		drop table dbo.sma_hadr_log_shipping_history
		go
	*/
create table dbo.sma_hadr_log_shipping
(
	[server] varchar(125) not null,
	[databases_CSV] varchar(2000) not null,
	[source_server] varchar(125) not null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_log_shipping] primary key clustered ([server],[source_server])
	,constraint [fk_sma_hadr_log_shipping__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_log_shipping_history));
go


/* ***** 8) Create table dbo.sma_hadr_transaction_replication_publishers ***************************** */
	/*
		ALTER TABLE dbo.sma_hadr_transaction_replication_publishers SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_hadr_transaction_replication_publishers
		go
		drop table dbo.sma_hadr_transaction_replication_publishers_history
		go
	*/
create table dbo.sma_hadr_transaction_replication_publishers
(
	[server] varchar(125) not null,
	[distributor_server] varchar(125) not null,
	[subscribers_CSV] varchar(2000) not null,
	[published_databases_CSV] varchar(2000) not null,
	[is_decommissioned] bit not null default 0,
	[remarks] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_hadr_transaction_replication_publishers] primary key clustered ([server])
	,constraint [fk_sma_hadr_transaction_replication_publishers__server] foreign key ([server]) references dbo.sma_servers ([server])
)
with (system_versioning = on (history_table = dbo.sma_hadr_transaction_replication_publishers_history));
go


/* ***** 9) Create table dbo.sma_applications ***************************** */
	/*
		ALTER TABLE dbo.sma_applications SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_applications
		go
		drop table dbo.sma_applications_history
		go
	*/
create table dbo.sma_applications
(
	[application_name] varchar(125) not null,
	[application_owner_email] varchar(125) not null,
	[app_team_email] varchar(125) null,
	[primary_contact_email] varchar(125) null,
	[is_decommissioned] bit not null default 0,
	[more_app_info] varchar(2000) null

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_applications] primary key clustered ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_history));
go

/* ***** 10) Create table dbo.sma_applications_server_xref ***************************** */
	/*
		ALTER TABLE dbo.sma_applications_server_xref SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_applications_server_xref
		go
		drop table dbo.sma_applications_server_xref_history
		go
	*/
create table dbo.sma_applications_server_xref
(
	[server] varchar(125) not null,
	[application_name] varchar(125) not null,
	[is_valid] bit not null default 0

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_applications_server_xref] primary key clustered ([server],[application_name])
	,index [application_name] nonclustered ([application_name])
	,constraint [fk_sma_applications_server_xref__server] foreign key ([server]) references dbo.sma_servers ([server])
	,constraint [fk_sma_applications_server_xref__application_name] foreign key ([application_name]) references dbo.sma_applications ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_server_xref_history));
go


/* ***** 11) Create table dbo.sma_applications_database_xref ***************************** */
	/*
		ALTER TABLE dbo.sma_applications_database_xref SET ( SYSTEM_VERSIONING = OFF)
		go
		drop table dbo.sma_applications_database_xref
		go
		drop table dbo.sma_applications_database_xref_history
		go
	*/
create table dbo.sma_applications_database_xref
(
	[server] varchar(125) not null,
	[database_name] varchar(125) not null,
	[application_name] varchar(125) not null,
	[is_valid] bit not null default 0

	,[valid_from] DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
    ,[valid_to] DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
    ,PERIOD FOR SYSTEM_TIME ([valid_from],[valid_to])

	,constraint [pk_sma_applications_database_xref] primary key clustered ([server],[database_name])
	,index [application_name] nonclustered ([application_name])
	,constraint [fk_sma_applications_database_xref__server] foreign key ([server]) references dbo.sma_servers ([server])
	,constraint [fk_sma_applications_database_xref__application_name] foreign key ([application_name]) references dbo.sma_applications ([application_name])
)
with (system_versioning = on (history_table = dbo.sma_applications_database_xref_history));
go



/* ***** 12) Create table dbo.sma_errorlog ***************************** */
-- drop table [dbo].[sma_errorlog]
create table [dbo].[sma_errorlog]
( 	[collection_time] datetime2 not null default sysdatetime(), 
    [function_name] varchar(125) not null, 
	[function_call_arguments] varchar(1000) null, 
	[server] varchar(125) null,
	[error] varchar(1000) not null, 
	[is_resolved] bit not null default 0,
    [remark] varchar(1000) null,
	[executed_by] varchar(125) not null default SUSER_NAME(),
	[executor_program_name] varchar(125) not null default program_name()

	,index [ci_sma_errorlog] clustered ([collection_time])
)
go



/*	***** 13) Create view dbo.vw_sma_server **************************** */
create or alter view dbo.sma_sql_servers
as
select 1 as [dummy]
go


/*

select * from dbo.sma_servers
select * from dbo.sma_sql_server_extended_info
select * from dbo.sma_sql_server_hosts
select * from dbo.sma_hadr_ag
select * from dbo.sma_hadr_sql_cluster
select * from dbo.sma_hadr_mirroring
select * from dbo.sma_hadr_log_shipping
select * from dbo.sma_hadr_transaction_replication_publishers
select * from dbo.sma_applications
select * from dbo.sma_applications_server_xref
select * from dbo.sma_applications_database_xref
go


select *
from DBE_Site.dbo.DbInventory2024July02

select di.*, id.*
from DBE_Site.dbo.DbInventory2024July02 di
left join DBA_Admin.dbo.instance_details id
	on id.sql_instance = di.[Server IP]
where 1=1
--and id.sql_instance is not null -- exists => 147 of 129
and id.sql_instance is null -- exists => 14 of 129

select *
from dbo.vw_all_server_info

select * from dbo.sma_servers
*/

select di.*, id.*
from DBE_Site.dbo.DbInventory2024July02 di
left join DBA_Admin.dbo.instance_details id
	on id.sql_instance = di.[Server IP]
where 1=1
and id.sql_instance is not null -- exists => 147 of 129
--and id.sql_instance is null -- exists => 14 of 129

select * from dbo.sma_servers
--select * into #vw_all_server_info from DBA_Admin.dbo.vw_all_server_info asi

/* Populate data from Excel Inventory */
;with cte_servers as 
(
	select	[server] = id.sql_instance, 
			[server_port] = id.sql_instance_port, asi.domain, [friendly_name] = null, [stability] = 'prod',
			[priority] = coalesce(replace(di.Priority,'P',''),3), [server_type] = 'SQLServer', 
			[has_hadr] = case when di.Is_Clustered = 'Y' or di.Is_Always_On = 'Y' then 1 else 0 end, 
			[hadr_strategy] = case when coalesce(di.Is_Always_On,'') = 'Y' then 'ag'
									when coalesce(di.Is_Clustered,'') = 'Y' then 'sqlcluster'
									else null
									end,
			[backup_strategy] = case when di.[Backup Location] = 'N' then 'Native' 
									when di.[Backup Location] is null then 'Rubrik'
									else di.[Backup Location] end, 
			[server_owner_email] = di.[Server Owner], 
			[rdp_credential] = null, [sql_credential] = 'linkadmin',
			[is_monitoring_enabled] = 1, 
			[is_maintenance_scheduled] = case when di.Is_Maintenance_Scheduled = 'Y' then 1 else 0 end, 
			[is_tde_implemented] = case when di.[TDE Implementation] = 'Y' then 1 else 0 end,
			[enabled_restart_schedule] = case when di.[Restart Schedule] = 'Y' then 1 else 0 end, 
			[is_decommissioned] = 0, [more_info_JSON] = null
			,[row_id] = ROW_NUMBER()over(partition by id.sql_instance order by asi.domain)
	from DBE_Site.dbo.DbInventory2024July02 di
	left join DBA_Admin.dbo.instance_details id
		on id.sql_instance = di.[Server IP]
	left join #vw_all_server_info asi
		on asi.srv_name = id.sql_instance
	where 1=1
	and id.sql_instance is not null -- exists => 147 of 129
)
--insert dbo.sma_servers
--(	[server], [server_port], [domain], [friendly_name], [stability], 
--	[priority], [server_type], 
--	[has_hadr], [hadr_strategy], [backup_strategy], 
--	[server_owner_email], [rdp_credential], [sql_credential], 
--	[is_monitoring_enabled], [is_maintenance_scheduled], [is_tde_implemented], 
--	[enabled_restart_schedule], [is_decommissioned], [more_info_JSON]
--)
select [server], [server_port], [domain], [friendly_name], [stability], 
	[priority], [server_type], 
	[has_hadr], [hadr_strategy], [backup_strategy], 
	[server_owner_email], [rdp_credential], [sql_credential], 
	[is_monitoring_enabled], [is_maintenance_scheduled], [is_tde_implemented], 
	[enabled_restart_schedule], [is_decommissioned], [more_info_JSON]
from cte_servers
where row_id = 1
go

/* Update Alias/FriendlyName */
update s
set 
--select s.server, 
		[friendly_name] = case when di.[Instance Alias] = 'N' then null
								else di.[Instance Alias]
								end
from dbo.sma_servers s
join DBE_Site.dbo.DbInventory2024July02 di
on di.[Server IP] = s.server

--select distinct di.[Instance Alias]
--from DBE_Site.dbo.DbInventory2024July02 di
go


/* Update Owner Email */
select distinct server, server_owner_email = ltrim(rtrim(s.server_owner_email))
from dbo.sma_servers s
where ltrim(rtrim(s.server_owner_email)) not like '%@%' or s.server_owner_email is null;

begin tran
	update dbo.sma_servers
	set server_owner_email = 'mitesh.p@angelbroking.com'
	where ltrim(rtrim(server_owner_email)) = 'KYC_Team' and server = '10.253.78.164'

	select @@TRANCOUNT, @@ROWCOUNT;

commit tran

select *
from DBA_Admin.dbo.instance_details id
join #vw_all_server_info vw
	on vw.srv_name = id.sql_instance
where 1=1
and id.is_enabled = 1
and id.is_alias = 0
and id.is_available = 1
and id.sql_instance not in (select s.server from DBA_Admin.dbo.sma_servers s where s.is_decommissioned = 0)

/* Add more servers which are in SQLMonnitor but not Excel Inventory */
/* Populate data from Excel Inventory */
;with cte_servers as 
(
	select	[server] = id.sql_instance, 
			[server_port] = id.sql_instance_port, asi.domain, [friendly_name] = null, [stability] = 'prod',
			[priority] = 3, [server_type] = 'SQLServer', 
			[has_hadr] = 0, 
			[hadr_strategy] = null,
			[backup_strategy] = null, 
			[server_owner_email] = null, 
			[rdp_credential] = null, [sql_credential] = 'linkadmin',
			[is_monitoring_enabled] = 1, 
			[is_maintenance_scheduled] = 0, 
			[is_tde_implemented] = case when cm.server_ip is not null then 1 else 0 end,
			[enabled_restart_schedule] = 0, 
			[is_decommissioned] = 0, [more_info_JSON] = null
			,[row_id] = ROW_NUMBER()over(partition by id.sql_instance order by asi.domain)
	from DBA_Admin.dbo.instance_details id
	join #vw_all_server_info asi
		on asi.srv_name = id.sql_instance
	outer apply (select top 1 server_ip from DBA_Inventory.dbo.credential_manager where user_name = 'master key' and server_ip = id.sql_instance) cm
	where 1=1
	and id.is_enabled = 1
	and id.is_alias = 0
	and id.is_available = 1
	and id.sql_instance not in (select s.server from DBA_Admin.dbo.sma_servers s where s.is_decommissioned = 0)
)
insert dbo.sma_servers
(	[server], [server_port], [domain], [friendly_name], [stability], 
	[priority], [server_type], 
	[has_hadr], [hadr_strategy], [backup_strategy], 
	[server_owner_email], [rdp_credential], [sql_credential], 
	[is_monitoring_enabled], [is_maintenance_scheduled], [is_tde_implemented], 
	[enabled_restart_schedule], [is_decommissioned], [more_info_JSON]
)
select [server], [server_port], [domain], [friendly_name], [stability], 
	[priority], [server_type], 
	[has_hadr], [hadr_strategy], [backup_strategy], 
	[server_owner_email], [rdp_credential], [sql_credential], 
	[is_monitoring_enabled], [is_maintenance_scheduled], [is_tde_implemented], 
	[enabled_restart_schedule], [is_decommissioned], [more_info_JSON]
from cte_servers
where row_id = 1
go

select * from dbo.instance_details id where id.is_enabled = 1 --and id.is_alias = 0
	and id.sql_instance in ('10.253.33.188','10.253.33.151','10.253.33.152');
select * from dbo.sma_servers s where s.is_decommissioned = 0
	and s.server in ('10.253.33.188','10.253.33.151','10.253.33.152');

/* Populate Ag table */
;with cte_ag as (
	select	[server] = '10.253.33.152', 
			[ag_name] = 'AG_EDIS_GPX_2', 
			[ag_replicas_CSV] = 'ATGPXEDISDAGPN1, ATGPXEDISDAGPN2', 
			[preffered_role] = 'Secondary', 
			[current_role] = 'Primary', 
			[ag_databases_CSV] = 'HOLDINGS_GPX', 
			[ag_listener_01_name] = 'ATGPXEDISDBL02', 
			[ag_listener_01_ip1] = '10.253.33.188', 
			[ag_listener_01_ip2] = null, 
			[ag_listener_02_name] = null, 
			[ag_listener_02_ip1] = null, 
			[ag_listener_02_ip2] = null, 
			[is_decommissioned] = 0, 
			[remarks] = ''
)
insert dbo.sma_hadr_ag
([server], [ag_name], [ag_replicas_CSV], [preffered_role], [current_role], [ag_databases_CSV], [ag_listener_01_name], [ag_listener_01_ip1], [ag_listener_01_ip2], [ag_listener_02_name], [ag_listener_02_ip1], [ag_listener_02_ip2], [is_decommissioned], [remarks] )
select [server], [ag_name], [ag_replicas_CSV], [preffered_role], [current_role], [ag_databases_CSV], [ag_listener_01_name], [ag_listener_01_ip1], [ag_listener_01_ip2], [ag_listener_02_name], [ag_listener_02_ip1], [ag_listener_02_ip2], [is_decommissioned], [remarks]
from cte_ag
go

/* Populate SqlCluster table */
;with cte_sqlcluster as (
	select	[server] = '10.254.33.66', 
			[sql_cluster_network_name] = 'AONTTDRGM4', 
			[preferred_owner_node] = 'AODR0SPSDBN04', 
			[sql_cluster_ip1] = '10.254.33.66', 
			[sql_cluster_ip2] = null, 
			[is_decommissioned] = 0, 
			[remarks] = ''
)
insert dbo.sma_hadr_sql_cluster
([server], [sql_cluster_network_name], [preferred_owner_node], [sql_cluster_ip1], [sql_cluster_ip2], [is_decommissioned], [remarks] )
select [server], [sql_cluster_network_name], [preferred_owner_node], [sql_cluster_ip1], [sql_cluster_ip2], [is_decommissioned], [remarks]
from cte_sqlcluster
go


select * 
--delete s
-- update s set is_decommissioned = 0
from dbo.sma_servers s 
where 1=1
	and s.is_decommissioned = 0
	and s.server in ('10.254.80.187','10.254.80.188');
go

/* Find servers not present in SQLMonitor */
select *
from DBA_Admin.dbo.sma_servers s
where 1=1
and s.is_decommissioned = 0
and s.server not in ('10.253.33.160')
and not exists (select * from DBA_Admin.dbo.instance_details id where s.server = id.sql_instance and id.is_enabled = 1 and id.is_alias = 0 and id.is_available = 1)
go

/* Servers without Owner Mapping */
select *
from DBA_Admin.dbo.sma_servers s
where s.is_decommissioned = 0
and (	s.server_owner_email is null
	);

/* Servers where we don't have Server Owner Team Email id */
select server, server_owner_email
from DBA_Admin.dbo.sma_servers s
where s.is_decommissioned = 0
and not exists (select * from DBA_Admin.dbo.sma_applications_server_xref app where app.is_valid = 1 and app.server = s.server)
go



select *
from DBE_Site.dbo.DbInventory2024July02 di

select *
from dbo.sma_hadr_ag