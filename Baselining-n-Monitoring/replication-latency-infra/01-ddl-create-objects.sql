USE [DBA_Admin]
GO

-- Partition function & scheme for [datetime2]
create partition function pf_dba (datetime2)
as range right for values ('2022-03-25 00:00:00.0000000')
go

create partition scheme ps_dba as partition pf_dba all to ([primary])
go

-- Partition function & scheme for [datetime]
create partition function pf_dba_datetime (datetime)
as range right for values ('2022-03-25 00:00:00.000')
go

create partition scheme ps_dba_datetime as partition pf_dba_datetime all to ([primary])
go

--drop table [dbo].[repl_pub_subs]
CREATE TABLE [dbo].[repl_pub_subs]
(
	[repl_id] [int] NOT NULL IDENTITY(1,1),
	[publisher] [sysname] NOT NULL,
	[publication_display_name] [nvarchar](388) NOT NULL,
	[subscription_display_name] [nvarchar](517) NULL,
	[publisher_db] [sysname] NULL,
	--[publication_id] [int] NOT NULL,
	[publication] [sysname] NULL,
	--[agent_id] [int] NULL,
	[agent_name] [nvarchar](100) NULL,
	[subscriber] [sysname] NOT NULL,
	[subscriber_db] [sysname] NULL,
	[collection_time] [datetime2] NOT NULL DEFAULT SYSDATETIME(),
	[status] char(10) not null default 'active'
	,constraint pk_repl_pub_subs primary key (repl_id)
)
GO

--drop INDEX [nci_repl_pub_subs] ON [dbo].[repl_pub_subs]
create unique nonclustered index [nci_pub_sub_display_name] ON [dbo].[repl_pub_subs]
(
	[publisher] ASC,
	[publication_display_name] ASC,
	[subscription_display_name] ASC
)
GO

create unique nonclustered index nci_publication_id__agent_id ON [dbo].[repl_pub_subs]
(	[publication], [agent_name] )
go

--select * from  [dbo].[repl_pub_subs]

/*
insert [dbo].[repl_pub_subs]
(	publisher, publication_display_name, subscription_display_name, publisher_db, 
	publication, agent_name, subscriber, subscriber_db )
select srv_pub.name as publisher
		,[publication_display_name] = QUOTENAME(a.publisher_db)+': '+a.publication
	,[subscription_display_name] = QUOTENAME(srv_sub.name)+'.'+QUOTENAME(a.subscriber_db)
	,a.publisher_db, a.publication
	,a.name as agent_name, srv_sub.name as subscriber, a.subscriber_db
from distribution.dbo.MSpublications as p with (nolock)
inner join master.sys.servers as srv_pub on srv_pub.server_id = p.publisher_id
left join distribution.dbo.MSdistribution_agents as a with (nolock)
on a.publication = p.publication and a.publisher_db = p.publisher_db and a.publisher_id = p.publisher_id
inner join master.sys.servers as srv_sub on srv_sub.server_id = a.subscriber_id
where not exists (
		select * from [dbo].[repl_pub_subs] i 
		where i.publisher = srv_pub.name 
		and i.publication_display_name = QUOTENAME(a.publisher_db)+': '+a.publication
		and i.subscription_display_name = QUOTENAME(srv_sub.name)+'.'+QUOTENAME(a.subscriber_db)
	);
*/


CREATE TABLE [dbo].[repl_token_header]
(
	[publisher] [varchar](200) NOT NULL,
	[publisher_db] [varchar](200) NOT NULL,
	[publication] [varchar](500) NOT NULL,
	[publication_id] [int] not null,
	[token_id] int NOT NULL,
	[collection_time] [datetime2](7) NOT NULL default sysutcdatetime(),
	[is_processed] bit not null default 0,
	constraint pk_repl_token_header primary key clustered ([publication], [token_id], is_processed, [collection_time]) on ps_dba([collection_time])
) on ps_dba([collection_time])
GO

create index nci_collection_time__filtered on [dbo].[repl_token_header] ([collection_time], [is_processed]) where [is_processed] = 0
go


CREATE TABLE [dbo].[repl_token_insert_log]
(
	[CollectionTimeUTC] [datetime2](7) NULL,
	[Publisher] [varchar](200) NOT NULL,
	[Distributor] [varchar](200) NOT NULL,
	[PublisherDb] [varchar](200) NOT NULL,
	[Publication] [varchar](500) NOT NULL,
	[ErrorMessage] [varchar](4000) NOT NULL,
) on ps_dba([CollectionTimeUTC])
GO

create clustered index ci_replication_tokens_insert_log on [dbo].[repl_token_insert_log]
	([CollectionTimeUTC],[Publisher]) on ps_dba([CollectionTimeUTC])
go



CREATE TABLE [dbo].[repl_token_history]
(
	[repl_id] int not null,
	[publisher_commit] [datetime] NOT NULL,
	[distributor_commit] [datetime] NOT NULL,
	[distributor_latency] int not null, --AS datediff(minute,publisher_commit,distributor_commit),
	[subscriber_commit] [datetime] NOT NULL,
	[subscriber_latency] int not null, -- AS datediff(minute,distributor_commit,subscriber_commit),
	[overall_latency] int not null, --AS datediff(minute,publisher_commit,subscriber_commit),
	[collection_time_utc] [datetime2] NOT NULL DEFAULT sysutcdatetime()
	,constraint pk_repl_token_history primary key clustered ([repl_id],[publisher_commit],[collection_time_utc]) on ps_dba([collection_time_utc])
) on ps_dba([collection_time_utc])
GO

create nonclustered index nci_collection_time_utc on [dbo].[repl_token_history] ([collection_time_utc]) on ps_dba([collection_time_utc])
go


-- Get Latest Latency
create or alter view dbo.vw_repl_latency
with schemabinding
as
select sub.publisher, sub.publication_display_name, sub.subscription_display_name, last_token_time = h.publisher_commit, last_token_latency_seconds = h.overall_latency
		,current_latency_seconds = datediff(second,h.collection_time_utc,SYSUTCDATETIME()), h.collection_time_utc
from dbo.repl_pub_subs as sub
outer apply (select top 1 h.publisher_commit, h.overall_latency, h.collection_time_utc from dbo.repl_token_history h with (forceseek)
			where h.repl_id = sub.repl_id order by publisher_commit desc) as h;
go

select *
from dbo.vw_repl_latency
go


/*
-- [datetime2] - Add partitions - Hourly - Till Next Quarter End
use [DBA_Admin];

set nocount on;
SET QUOTED_IDENTIFIER ON;

declare @current_boundary_value datetime2;
declare @target_boundary_value datetime2; /* last day of new quarter */
set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, GETDATE()) +2, 0));

select top 1 @current_boundary_value = convert(datetime2,prv.value)
from sys.partition_range_values prv
join sys.partition_functions pf on pf.function_id = prv.function_id
where pf.name = 'pf_dba'
order by prv.value desc;

select [@current_boundary_value] = @current_boundary_value, [@target_boundary_value] = @target_boundary_value;

while (@current_boundary_value < @target_boundary_value)
begin
	set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
	--print @current_boundary_value
	alter partition scheme ps_dba next used [primary];
	alter partition function pf_dba() split range (@current_boundary_value);	
end
go

-- [datetime] - Add partitions - Hourly - Till Next Quarter End
use [DBA_Admin];

set nocount on;
SET QUOTED_IDENTIFIER ON;

declare @current_boundary_value datetime;
declare @target_boundary_value datetime; /* last day of new quarter */
set @target_boundary_value = DATEADD (dd, -1, DATEADD(qq, DATEDIFF(qq, 0, GETDATE()) +2, 0));

select top 1 @current_boundary_value = convert(datetime,prv.value)
from sys.partition_range_values prv
join sys.partition_functions pf on pf.function_id = prv.function_id
where pf.name = 'pf_dba_datetime'
order by prv.value desc;

select [@current_boundary_value] = @current_boundary_value, [@target_boundary_value] = @target_boundary_value;

while (@current_boundary_value < @target_boundary_value)
begin
	set @current_boundary_value = DATEADD(hour,1,@current_boundary_value);
	--print @current_boundary_value
	alter partition scheme ps_dba_datetime next used [primary];
	alter partition function pf_dba_datetime() split range (@current_boundary_value);	
end
go

-- [datetime2] - Remove Partitions - Retain upto 3 Months
use [DBA_Admin];

set nocount on;
SET QUOTED_IDENTIFIER ON;

declare @partition_boundary datetime2;
declare @target_boundary_value datetime2; /* 3 months back date */
set @target_boundary_value = DATEADD(mm,DATEDIFF(mm,0,GETDATE())-3,0);
--set @target_boundary_value = '2022-03-25 19:00:00.000'

declare cur_boundaries cursor local fast_forward for
		select convert(datetime2,prv.value) as boundary_value
		from sys.partition_range_values prv
		join sys.partition_functions pf on pf.function_id = prv.function_id
		where pf.name = 'pf_dba' and convert(datetime2,prv.value) < @target_boundary_value
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
DEALLOCATE cur_boundaries;
go

-- [datetime] - Remove Partitions - Retain upto 3 Months
use [DBA_Admin];

set nocount on;
SET QUOTED_IDENTIFIER ON;

declare @partition_boundary datetime;
declare @target_boundary_value datetime; /* 3 months back date */
set @target_boundary_value = DATEADD(mm,DATEDIFF(mm,0,GETDATE())-3,0);
--set @target_boundary_value = '2022-03-25 19:00:00.000'

declare cur_boundaries cursor local fast_forward for
		select convert(datetime,prv.value) as boundary_value
		from sys.partition_range_values prv
		join sys.partition_functions pf on pf.function_id = prv.function_id
		where pf.name = 'pf_dba_datetime' and convert(datetime,prv.value) < @target_boundary_value
		order by prv.value asc;

open cur_boundaries;
fetch next from cur_boundaries into @partition_boundary;
while @@FETCH_STATUS = 0
begin
	--print @partition_boundary
	alter partition function pf_dba_datetime() merge range (@partition_boundary);

	fetch next from cur_boundaries into @partition_boundary;
end
CLOSE cur_boundaries
DEALLOCATE cur_boundaries;
go

*/

/*
-- Get partitioned Data Distribution
select object_name(p.object_id) as table_name, s.name as partition_scheme_name, p.partition_number, 
		f.name as partition_function_name,
		lv.value leftValue, rv.value rightValue, 
		p.rows AS NumberOfRows
from sys.partitions p
join sys.allocation_units a
on p.hobt_id = a.container_id
join sys.indexes i
on p.object_id = i.object_id
join sys.partition_schemes s
on i.data_space_id = s.data_space_id
join sys.partition_functions f
on s.function_id = f.function_id
left join sys.partition_range_values rv
on f.function_id = rv.function_id
and p.partition_number = rv.boundary_id
left join sys.partition_range_values lv
on f.function_id = lv.function_id
and p.partition_number - 1 = lv.boundary_id
order by partition_number;

*/
