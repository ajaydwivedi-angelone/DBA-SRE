/*
Mail Subject -> *** IMPORTANT - Database Password Expiration Notification (Jul 2 2024 8:00AM)

SQLAgent Job -> [(dba) Login_Expiry_Notification]

Step 1-> EXEC DBE_Site.dbo.usp_Login_Expiry_Email
Step 2-> EXEC DBE_Site.dbo.usp_Login_Expiry_EMail_Step_2

Meeting on July 5th
-------------------
20 days - Email Alert
13 days - Page
7 days - Hemanth
3 days - Jyoti

truncate table dbo.all_server_login_expiry_info ;
truncate table dbo.[sma_errorlog] ;

-- Login Owner Mapping Table
select * from dba_admin.dbo.login_email_mapping LM 

Checks 
----------
1) dbo.sma_servers is child of dbo.instance_details
2) Email id validation
3) JSON value validation for [more_info_JSON]

Alerts 
-----------
1) Alert for following scenarios:
	a) Failure entries in table [dbo].[sma_errorlog]
		i) function name 'usp_collect_all_server_login_expiration_info'
		ii) function name 'usp_send_login_expiry_emails'
	b) Collection Job failing [(dba) Collect Login Expiration Info]
	c) Mail Notification Job Failing [(dba) Send Login Expiry EMails]
	d) If not data collection for a specific server which is not in ERROR table


2) Alert for following scenarios:
	a) If login scenario is valid, but no mails in table msdb..sysmail_sentitems
	b) If login scenario is valid for SRE-VP, but no mail exists
	c) If login scenario is valid for CTE, but no mail exists

Dashboards
-------------
1) All Server Dashboard - Panel for CRITICAL LOGIN Expiry
2) "Login Expiry Info" Dashboard
	a) 1st - All Logins Info
	b) 2nd - All Warning
	c) 3rd - All CRITICAL
	d) 4th - Server Application Mapping
	
*/

use DBA_Admin
go

select DATEADD(mi, DATEDIFF(mi, getdate(), getutcdate()), max(collection_time))
from dbo.all_server_login_expiry_info lei
where lei.collection_time >= dateadd(hour,-1,getdate())

select *
from [dbo].[sma_errorlog]

--10.253.33.193\ABMUBO
--10.253.33.33\ANGELBS
--10.253.33.34\ANGELBS

select *
from dbo.instance_details id
where id.sql_instance in ('10.253.33.193\ABMUBO','10.253.33.33\ANGELBS','10.253.33.34\ANGELBS')

select	*
from dbo.all_server_login_expiry_info_dashboard lei
where 1=1
go

insert dbo.purge_table
	(table_name, date_key, retention_days, purge_row_size, reference)
	select	table_name = 'dbo.all_server_login_expiry_info', 
			date_key = 'collection_time', 
			retention_days = 30, 
			purge_row_size = 100000,
			reference = 'Login Expiry Infra'
go

