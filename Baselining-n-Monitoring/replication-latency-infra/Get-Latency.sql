use DBA_Inventory
go

IF OBJECT_ID('tempdb..#publications') IS NOT NULL
	DROP TABLE #publications;
select srv.name as publisher, pl.publisher_id, pl.publisher_db, pl.publication, pl.publication_id, 
		pl.publication_type, case pl.publication_type when 0 then 'Transactional' when 1 then 'Snapshot' when 2 then 'Merge' else 'No idea' end as publication_type_desc, 
		pl.immediate_sync, pl.allow_pull, pl.allow_push, pl.description,
		pl.vendor_name, pl.sync_method, pl.allow_initialize_from_backup
into #publications
from [196.1.115.228].distribution.dbo.MSpublications pl (nolock) 
join [196.1.115.228].distribution.sys.servers srv on srv.server_id = publisher_id
order by srv.name, pl.publisher_db;

if object_id('tempdb..#subscriptions') is not null
	drop table #subscriptions;
select distinct srv.name as subscriber, sub.subscriber_id, sub.subscriber_db, 
		sub.subscription_type, case sub.subscription_type when 0 then 'Push' when 1 then 'Pull' else 'Anonymous' end as subscription_type_desc,
		sub.publication_id, sub.publisher_db, 
		sub.sync_type, (case sub.sync_type when 1 then 'Automatic' when 2 then 'No synchronization' else 'No Idea' end) as sync_type_desc, 
		sub.status, (case sub.status when 0 then 'Inactive' when 1 then 'Subscribed' when 2 then 'Active' else 'No Idea' end) as status_desc
into #subscriptions
from [196.1.115.228].distribution.dbo.MSsubscriptions sub (nolock) 
join [196.1.115.228].distribution.sys.servers srv on srv.server_id = sub.subscriber_id
where sub.subscriber_id >= 0;

if object_id('tempdb..#repls') is not null
	drop table #repls;
select pl.publisher, pl.publisher_db, pl.publication, pl.publication_id, pl.publication_type_desc, sb.subscriber, sb.subscriber_db, sb.subscription_type_desc, sb.sync_type_desc, sb.status_desc
into #repls
from #publications pl join #subscriptions sb on sb.publication_id = pl.publication_id and sb.publisher_db = pl.publisher_db
order by pl.publisher, pl.publisher_db, sb.subscriber, sb.subscriber_db, pl.publication;

select top 2 * from #repls as rpl

select [distributor] = CONNECTIONPROPERTY('local_net_address'), 
		rpl.publisher as publisher, rpl.publisher_db, rpl.publication,
		rpl.subscriber as subscriber, rpl.subscriber_db, 
		[subscription] = quotename(s_srv.name)+'.'+agnt.subscriber_db,
		tkn.publisher_commit, tkn.distributor_commit, hist.subscriber_commit, 
		agnt.name as agent_name
		--,row_id = ROW_NUMBER()over(partition by p_srv.name, agnt.publisher_db, agnt.publication, agnt.name order by publisher_commit desc)
--into #MStracer_tokens
from #repls as rpl
left join [DBA_Inventory].[dbo].[replication_tokens] rt
	on rt.publication = rpl.publication and rt.publisher = rpl.publisher 
	and rt.publisher_db = rpl.publisher_db and rt.publication_id = rpl.publication_id
left join [196.1.115.228].distribution.dbo.MStracer_tokens as tkn with (nolock)
	on tkn.publication_id = rt.publication_id and tkn.tracer_id = rt.tokenID
left join [196.1.115.228].distribution.dbo.MStracer_history as hist with (nolock)
	on hist.parent_tracer_id = tkn.tracer_id
left join [196.1.115.228].distribution.dbo.MSdistribution_agents as agnt with (nolock)
	on agnt.id = hist.agent_id
left join [196.1.115.228].distribution.dbo.MSpublications as pbls with (nolock)
	on pbls.publication = agnt.publication and pbls.publication_id = tkn.publication_id
--left join [196.1.115.228].distribution.dbo.MSsubscriptions as sp with (nolock)
--on sp.agent_id = histagent_id
left join [196.1.115.228].master.sys.servers as s_srv on s_srv.server_id = agnt.subscriber_id
left join [196.1.115.228].master.sys.servers as p_srv on p_srv.server_id = agnt.publisher_id
order by publisher, publisher_db, publication, subscriber, subscriber_db


select * from distribution.dbo.MSpublications as pbls with (nolock) where publication_id = 83
select top 5 * from distribution.dbo.MSdistribution_agents where publication = 'broktable' and publisher_db = 'NSEFO' and publisher_id = 5




/*
DECLARE @VAR char(2)
SELECT  @VAR = 'CA'
EXEC MyLinkedServer.master.dbo.sp_executesql
N'SELECT * FROM pubs.dbo.authors WHERE state = @state',
N'@state char(2)',
@VAR
*/