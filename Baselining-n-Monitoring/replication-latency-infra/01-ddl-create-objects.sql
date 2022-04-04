USE [DBA_Admin]
GO

create partition function pf_dba (datetime2)
as range right for values ('2022-03-25 00:00:00.0000000')
go

create partition scheme ps_dba as partition pf_dba all to ([primary])
go

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


--drop table [dbo].[repl_token_history]

CREATE TABLE [dbo].[repl_token_history]
(
	[publisher] [sysname] not null,
	[publication_display_name] nvarchar(1000) not null,
	[subscription_display_name] nvarchar(1000) not null,
	[publisher_db] [sysname] not null,
	[publication] [sysname] NOT NULL,
	[publisher_commit] [datetime] NOT NULL,
	[distributor_commit] [datetime] NOT NULL,
	[distributor_latency] int not null, --AS datediff(minute,publisher_commit,distributor_commit),
	[subscriber] [sysname] NOT NULL,
	[subscriber_db] [sysname] NOT NULL,
	[subscriber_commit] [datetime] NOT NULL,
	[subscriber_latency] int not null, -- AS datediff(minute,distributor_commit,subscriber_commit),
	[overall_latency] AS datediff(minute,publisher_commit,subscriber_commit),
	[agent_name] nvarchar(2000) not null,
	[collection_time_utc] [datetime2] NOT NULL DEFAULT sysutcdatetime()
	--,constraint pk_repl_token_history primary key clustered ([collection_time_utc], [publisher], [publication_display_name], [subscription_display_name]) on ps_dba([collection_time_utc])
) on ps_dba([collection_time_utc])
GO

CREATE CLUSTERED INDEX ci_repl_token_history ON [dbo].[repl_token_history]
(
	[collection_time_utc] ASC,
	[publication] ASC
)
GO

CREATE NONCLUSTERED INDEX [NCI_repl_token_history] ON [dbo].[repl_token_history]
(
	[publication] ASC,
	[publisher_commit] ASC
)
go