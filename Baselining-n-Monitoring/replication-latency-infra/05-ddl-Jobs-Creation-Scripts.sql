USE [msdb]
GO

/****** Object:  Job [(dba) Partitions-Maintenance]    Script Date: 04-04-2022 14:13:47 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [(dba) Monitoring & Alerting]    Script Date: 04-04-2022 14:13:48 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'(dba) Monitoring & Alerting' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'(dba) Monitoring & Alerting'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Partitions-Maintenance', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job takes care of creating new partitions and removing old partitions', 
		@category_name=N'(dba) Monitoring & Alerting', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'Slack_alerting', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Add partitions - Hourly - Till Next Quarter End]    Script Date: 04-04-2022 14:13:48 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Add partitions - Hourly - Till Next Quarter End', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'set nocount on;
declare @current_boundary_value datetime2;
declare @target_boundary_value datetime2; /* last day of new quarter */
set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, GETDATE()) +2, 0));

select top 1 @current_boundary_value = convert(datetime2,prv.value)
from sys.partition_range_values prv
join sys.partition_functions pf on pf.function_id = prv.function_id
where pf.name = ''pf_dba''
order by prv.value desc;

select [@current_boundary_value] = @current_boundary_value, [@target_boundary_value] = @target_boundary_value;

while (@current_boundary_value < @target_boundary_value)
begin
	set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
	--print @current_boundary_value
	alter partition scheme ps_dba next used [primary];
	alter partition function pf_dba() split range (@current_boundary_value);	
end', 
		@database_name=N'DBA_Inventory', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Remove Partitions - Retain upto 3 Months]    Script Date: 04-04-2022 14:13:48 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Remove Partitions - Retain upto 3 Months', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'set nocount on;
declare @partition_boundary datetime2;
declare @target_boundary_value datetime2; /* 3 months back date */
set @target_boundary_value = DATEADD(mm,DATEDIFF(mm,0,GETDATE())-3,0);
--set @target_boundary_value = ''2022-03-25 19:00:00.000''

declare cur_boundaries cursor local fast_forward for
		select convert(datetime2,prv.value) as boundary_value
		from sys.partition_range_values prv
		join sys.partition_functions pf on pf.function_id = prv.function_id
		where pf.name = ''pf_dba'' and convert(datetime2,prv.value) < @target_boundary_value
		order by prv.value asc;

open cur_boundaries;
fetch next from cur_boundaries into @partition_boundary;
while @@FETCH_STATUS = 0
begin
	--print @partition_boundary
	alter partition function pf_dba() merge range (@partition_boundary);

	fetch next from cur_boundaries into @partition_boundary;
end
CLOSE cur_boundaries
DEALLOCATE cur_boundaries;', 
		@database_name=N'DBA_Inventory', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Partitions-Maintenance - Daily', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=24, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220326, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'b43ab780-6b08-4127-a36f-e2f478409210'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO

/****** Object:  Job [(dba) Replication-Insert-Tokens]    Script Date: 04-04-2022 14:13:56 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [(dba) Monitoring & Alerting]    Script Date: 04-04-2022 14:13:56 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'(dba) Monitoring & Alerting' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'(dba) Monitoring & Alerting'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Replication-Insert-Tokens', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job inserts replication tokens on each publisherdb', 
		@category_name=N'(dba) Monitoring & Alerting', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'Slack_alerting', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [01-post-tracer-token.ps1]    Script Date: 04-04-2022 14:13:56 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'01-post-tracer-token.ps1', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		@command=N'powershell.exe -executionpolicy bypass -Noninteractive  D:\Ajay-Dwivedi\GitHub-Office\DBA-SRE\Baselining-n-Monitoring\replication-latency-infra\03-post-tracer-token.ps1', 
		@flags=40
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Replication-Insert-Tokens', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=2, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220401, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'3c5f78c2-22c4-4b98-81b5-28346a927ade'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO



USE [msdb]
GO

/****** Object:  Job [(dba) Replication-Token-History-Fetch]    Script Date: 04-04-2022 14:14:09 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Data Collector]    Script Date: 04-04-2022 14:14:09 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Replication-Token-History-Fetch', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'Data Collector', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Process-Repl-Tokens]    Script Date: 04-04-2022 14:14:09 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Process-Repl-Tokens', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'set nocount on;
set quoted_identifier on;

declare @c_publication varchar(200);
declare @c_publication_id int;
declare @c_dbName varchar(200);
declare @c_publisher_commit datetime;
declare @c_is_processed bit;
declare @c_tracer_id bigint;
declare @oldest_pending_publisher_commit datetime;
declare @tsqlString nvarchar(4000);

-- Find oldest tracer token yet to be processed in DBA table
select @oldest_pending_publisher_commit = dateadd(second,-5,min(collection_time))
from dbo.repl_token_header h where h.is_processed = 0;

if object_id(''tempdb..#subs'') is not null
	drop table #subs;
select srv_pub.name as publisher
		,[publication_display_name] = QUOTENAME(a.publisher_db)+'': ''+a.publication
	,[subscription_display_name] = QUOTENAME(srv_sub.name)+''.''+QUOTENAME(a.subscriber_db)
	,a.publisher_db, p.publication_id, a.publication, a.id as agent_id
	,a.name as agent_name, srv_sub.name as subscriber, a.subscriber_db
into #subs
from distribution.dbo.MSpublications as p with (nolock)
inner join master.sys.servers as srv_pub on srv_pub.server_id = p.publisher_id
left join distribution.dbo.MSdistribution_agents as a with (nolock)
on a.publication = p.publication and a.publisher_db = p.publisher_db and a.publisher_id = p.publisher_id
inner join master.sys.servers as srv_sub on srv_sub.server_id = a.subscriber_id


if object_id(''tempdb..#tokens'') is not null
	drop table #tokens;
select d.tracer_id, d.publication_id, d.publisher_commit, d.distributor_commit, h.parent_tracer_id, h.agent_id, h.subscriber_commit
into #tokens
from distribution.dbo.MStracer_tokens as d with (nolock)
left join distribution.dbo.MStracer_history as h with (nolock)
on h.parent_tracer_id = d.tracer_id
where d.publisher_commit >= @oldest_pending_publisher_commit;

--select top 3 * from #subs
--select top 3 * from #tokens

-- Find all tracer token history since oldest pending tracer token 
if object_id(''tempdb..#MStracer_tokens'') is not null
	drop table #MStracer_tokens;
select	subs.publisher, subs.[publication_display_name], subs.[subscription_display_name]
		,subs.publisher_db, subs.publication_id, subs.publication, tkn.tracer_id, tkn.publisher_commit, tkn.distributor_commit		
		,subs.agent_name, tkn.subscriber_commit, subs.subscriber, subs.subscriber_db		
		,[subscription_counts] = COUNT(*)OVER(PARTITION BY subs.publisher, subs.publisher_db, subs.publication_id)
into #MStracer_tokens
from #subs as subs
left join #tokens as tkn
on tkn.publication_id = subs.publication_id and tkn.agent_id = subs.agent_id;

/*
select * from #MStracer_tokens where tracer_id is null
select top 10 * from #subs where publication_id = 83
select top 3 * from #MStracer_tokens where publisher = ''ANAND1\ANAND1'' --and publication_display_name = ''[MCDX]: mcdx_CLient2_to35'' order by [subscription_display_name]
select top 3 * from dbo.repl_token_header where is_processed = 0
*/
begin tran
	--	Insert processed tokens in History Table
	insert dbo.[repl_token_history]
	(	[publisher], [publication_display_name], [subscription_display_name], [publisher_db], publication, publisher_commit, 
		distributor_commit, [distributor_latency], subscriber, subscriber_db, subscriber_commit, [subscriber_latency],
		[overall_latency], [agent_name]
	)
	select h.[publisher], h.[publication_display_name], h.[subscription_display_name], h.[publisher_db], h.publication, h.publisher_commit, 
			h.distributor_commit, [distributor_latency] = datediff(minute,h.publisher_commit,h.distributor_commit), h.subscriber, h.subscriber_db, 
			h.subscriber_commit, [subscriber_latency] = datediff(minute,h.distributor_commit,h.subscriber_commit),
			[overall_latency] = datediff(minute,h.publisher_commit,h.subscriber_commit), [agent_name] = h.agent_name
	from #MStracer_tokens as h
	join dbo.repl_token_header as b
	on b.publisher = h.publisher
	and b.publisher_db = h.publisher_db
	and b.publication_id = h.publication_id
	and b.token_id = h.tracer_id
	where b.is_processed = 0
	and h.subscriber_commit is not null;

	-- List Tokens pending for any subscription	
	if object_id(''tempdb..#pending_tokens'') is not null
		drop table #pending_tokens
	select distinct publisher, publisher_db, publication, publication_id, h.tracer_id
	into #pending_tokens
	from #MStracer_tokens as h
	where h.subscriber_commit is null;
	
	-- Mark tokens processed if reached all subscriptions
	update b
	set is_processed = 1
	-- select b.*, pt.tracer_id
	from #MStracer_tokens as h
	join dbo.repl_token_header as b
	on b.publisher = h.publisher
	and b.publisher_db = h.publisher_db
	and b.publication = h.publication 
	and b.publication_id = h.publication_id
	and b.token_id = h.tracer_id
	left join #pending_tokens pt
	on pt.publisher = h.publisher
	and pt.publisher_db = h.publisher_db
	and pt.publication = h.publication
	and pt.publication_id = h.publication_id
	and pt.tracer_id = h.tracer_id
	where b.is_processed = 0
	and pt.tracer_id is null;
commit tran
/*
 select top 3 * from dbo.[repl_token_history]
 select top 3 * from dbo.repl_token_header as b
 select top 3 * from #MStracer_tokens as h
*/

--	Update process flag for lost tokens
;with t_Repl_TracerToken_Lastest_Processed as (
	select publisher, publisher_db, publication, publication_id, max(collection_time) as last_publisher_commit 
	from dbo.repl_token_header 
	where is_processed = 1 
	group by publisher, publisher_db, publication, publication_id
)
update h
set is_processed = 1
--select h.*
from dbo.repl_token_header as h
inner join t_Repl_TracerToken_Lastest_Processed as l
on l.publication = h.publication and h.collection_time < l.last_publisher_commit
where h.is_processed = 0

/*
-- Get Latest Latency
select top 1 with ties h.publisher, publication_display_name, subscription_display_name, last_token_time = publisher_commit, last_token_latency_seconds = overall_latency
		,current_latency_seconds = datediff(second,collection_time_utc,SYSUTCDATETIME())
from dbo.[repl_token_history] h
order by ROW_NUMBER()over(partition by publisher, publication_display_name, subscription_display_name order by publisher_commit desc);

*/
', 
		@database_name=N'DBA_Admin', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Replication-Token-History-Fetch', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=30, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220404, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'b7af41ea-4ea8-4110-bd78-b768cf872c7e'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO

/****** Object:  Job [(dba) Purge-Tables]    Script Date: 04-04-2022 16:08:14 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Data Collector]    Script Date: 04-04-2022 16:08:14 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'(dba) Purge-Tables', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'Data Collector', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [dbo.repl_token_header]    Script Date: 04-04-2022 16:08:14 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'dbo.repl_token_header', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET QUOTED_IDENTIFIER ON;
DECLARE @r INT;
	
SET @r = 1;
while @r > 0
begin
	delete top (100000) th
	from dbo.repl_token_header th
	where th.collection_time < dateadd(day,-30,sysutcdatetime())

	set @r = @@ROWCOUNT
end', 
		@database_name=N'DBA_Admin', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [dbo.repl_token_insert_log]    Script Date: 04-04-2022 16:08:14 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'dbo.repl_token_insert_log', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET QUOTED_IDENTIFIER ON;
DECLARE @r INT;
	
SET @r = 1;
while @r > 0
begin
	delete top (100000) th
	from dbo.repl_token_insert_log th
	where th.CollectionTimeUTC < dateadd(day,-30,sysutcdatetime())

	set @r = @@ROWCOUNT
end

', 
		@database_name=N'DBA_Admin', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [dbo.repl_token_history]    Script Date: 04-04-2022 16:08:14 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'dbo.repl_token_history', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET QUOTED_IDENTIFIER ON;
DECLARE @r INT;
	
SET @r = 1;
while @r > 0
begin
	delete top (100000) th
	from dbo.repl_token_history th
	where th.collection_time_utc < dateadd(day,-30,sysutcdatetime())

	set @r = @@ROWCOUNT
end', 
		@database_name=N'DBA_Admin', 
		@flags=12
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'(dba) Purge-Tables', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=24, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220404, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'01714360-5983-4f8c-9563-91ddbbe6e372'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

