<# ****************************************************************************#
## ************** Validate Replication Health using Tracer Tokens *************#
## *************************************************************************** #>
$DistributorConfig = Get-DbaRegisteredServer | ? {$_.Name -eq 'Distributor'}
$Distributor = $DistributorConfig | Connect-DbaInstance
$DistributorName = $DistributorConfig.ServerName
$DistributionDb = 'distribution'

# Local variables
$ErrorActionPreference = 'Stop';
$startTime = Get-Date
$Dtmm = $startTime.ToString('yyyy-MM-dd HH.mm.ss')

# Extract Credentials
$distributorConString = ($DistributorConfig.ConnectionString).Split(';');
$sqlUser = $distributorConString[1]
$sqlUserPassword = ConvertTo-SecureString -String $distributorConString[2] -AsPlainText -Force
$sqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, $sqlUserPassword

# Find all publications
$tsqlGetPublications = @"
IF OBJECT_ID('tempdb..#publications') IS NOT NULL
	DROP TABLE #publications;
select srv.name as publisher, pl.publisher_id, pl.publisher_db, pl.publication, pl.publication_id, 
		pl.publication_type, case pl.publication_type when 0 then 'Transactional' when 1 then 'Snapshot' when 2 then 'Merge' else 'No idea' end as publication_type_desc, 
		pl.immediate_sync, pl.allow_pull, pl.allow_push, pl.description,
		pl.vendor_name, pl.sync_method, pl.allow_initialize_from_backup
into #publications
from dbo.MSpublications pl (nolock) join sys.servers srv on srv.server_id = publisher_id
order by srv.name, pl.publisher_db;

if object_id('tempdb..#subscriptions') is not null
	drop table #subscriptions;
select distinct srv.name as subscriber, sub.subscriber_id, sub.subscriber_db, 
		sub.subscription_type, case sub.subscription_type when 0 then 'Push' when 1 then 'Pull' else 'Anonymous' end as subscription_type_desc,
		sub.publication_id, sub.publisher_db, 
		sub.sync_type, (case sub.sync_type when 1 then 'Automatic' when 2 then 'No synchronization' else 'No Idea' end) as sync_type_desc, 
		sub.status, (case sub.status when 0 then 'Inactive' when 1 then 'Subscribed' when 2 then 'Active' else 'No Idea' end) as status_desc
into #subscriptions
from dbo.MSsubscriptions sub (nolock) join sys.servers srv on srv.server_id = sub.subscriber_id
where sub.subscriber_id >= 0;

select pl.publisher, pl.publisher_db, pl.publication, pl.publication_type_desc, sb.subscriber, sb.subscriber_db, sb.subscription_type_desc, sb.sync_type_desc, sb.status_desc
from #publications pl join #subscriptions sb on sb.publication_id = pl.publication_id and sb.publisher_db = pl.publisher_db
order by pl.publisher, pl.publisher_db, sb.subscriber, sb.subscriber_db, pl.publication;
"@

"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Get publication list for distributor [$Distributor]" | Write-Host -ForegroundColor Cyan
$resultGetPublications = Invoke-DbaQuery -SqlInstance $Distributor -Database $DistributionDb -Query $tsqlGetPublications
#$resultGetPublications | ogv -Title "All publications"

$publishers = $resultGetPublications | Select-Object -ExpandProperty publisher -Unique

# Insert tracer token for each publisher
$tsqlInsertToken = @"
DECLARE @publication AS sysname;
DECLARE @tokenID AS int;
SET @publication = @p_publication; 

-- Insert a new tracer token in the publication database.
EXEC sys.sp_posttracertoken 
  @publication = @publication,
  @tracer_token_id = @tokenID OUTPUT;

SELECT @@SERVERNAME as [publisher], DB_NAME() as publisher_db, getdate() as [current_time], @publication as publication, @tokenID as tokenID;
"@

"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Insert tracer token using [sp_posttracertoken]" | Write-Host -ForegroundColor Cyan
[System.Collections.ArrayList]$tokenInserted = @()
$tokenInsertFailure = @()
foreach($srv in $publishers)
{
    "{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Post token on Publications of [$srv]" | Write-Host -ForegroundColor Cyan
    $srvPublications = $resultGetPublications | Where-Object {$_.publisher -eq $srv}
    #$pubSrvObj = Connect-DbaInstance -SqlInstance $srv -SqlCredential $sqlCredential
    $pubSrvObj = Get-DbaRegisteredServer -Name $srv -Group 'Replication-Publisher' | Connect-DbaInstance
    foreach($pub in $srvPublications)
    {
        try {
            $resultInsertToken = Invoke-DbaQuery -SqlInstance $pubSrvObj -Database $pub.publisher_db -Query $tsqlInsertToken `
                                            -SqlParameters @{ p_publication = $($pub.publication)} -EnableException
            $tokenInserted.Add($resultInsertToken) | Out-Null
        }
        catch {
            $err = $_
            $tokenInsertFailure += (New-Object psobject -Property @{CollectionTimeUTC = $startTime.ToUniversalTime(); Distributor = $DistributorName; Publisher = $srv; PublisherDb = $pub.publisher_db; Publication = $pub.publication; ErrorMessage = $err.ToString()})
            $_ | Write-Host -ForegroundColor Red
        }
    }
}
#$tokenInserted | ogv -Title "Tokens inserted"
#$tokenInsertFailure | ogv

"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(SLEEP)","Sleep for 15 seconds" | Write-Host -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Get token history
$tsqlGetTokenHistory = @"
SET NOCOUNT ON;
DECLARE @publication AS sysname;
DECLARE @tokenID AS int;
SET @publication = @p_publication;
SET @tokenID = @p_tokenID

IF OBJECT_ID('tempdb..#tokens') IS NOT NULL
	DROP TABLE #tokens
CREATE TABLE #tokens (tracer_id int, publisher_commit datetime);

-- Return tracer token information to a temp table.
INSERT #tokens (tracer_id, publisher_commit)
EXEC sys.sp_helptracertokens @publication = @publication;

IF OBJECT_ID('tempdb..#tokenhistory') IS NOT NULL
	DROP TABLE #tokenhistory;
CREATE TABLE #tokenhistory (distributor_latency bigint, subscriber sysname, subscriber_db sysname, subscriber_latency bigint, overall_latency bigint);

-- Get history for the tracer token.
INSERT #tokenhistory
EXEC sys.sp_helptracertokenhistory 
  @publication = @publication, 
  @tracer_id = @tokenID;

IF EXISTS (SELECT * FROM #tokenhistory where overall_latency is not null)
BEGIN
	select 'success' as status, @@SERVERNAME as [publisher], DB_NAME() as publisher_db, h.subscriber, h.subscriber_db, @publication as publication, @tokenID as tokenID, getdate() as [current_time], t.publisher_commit, h.distributor_latency, h.subscriber_latency, h.overall_latency
	from #tokenhistory as h join #tokens t on t.tracer_id = @tokenID
END
ELSE
BEGIN	
	select 'failure' as status, @@SERVERNAME as [publisher], DB_NAME() as publisher_db, h.subscriber, h.subscriber_db, @publication as publication, @tokenID as tokenID, getdate() as [current_time], t.publisher_commit, h.distributor_latency, h.subscriber_latency, h.overall_latency
	from #tokenhistory as h join #tokens t on t.tracer_id = @tokenID
END
"@

"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Fetch tracer token history" | Write-Host -ForegroundColor Cyan
[System.Collections.ArrayList]$tokenHistory = @()
foreach($srv in $publishers)
{
    "{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Getting history from [$srv] publications" | Write-Host -ForegroundColor Cyan
    $srvPublications = $tokenInserted | Where-Object {$_.publisher -eq $srv}
    $pubSrvObj = Connect-DbaInstance -SqlInstance $srv
    foreach($pub in $srvPublications)
    {
        $resultGetTokenHistory = Invoke-DbaQuery -SqlInstance $pubSrvObj -Database $pub.publisher_db -Query $tsqlGetTokenHistory -SqlParameters @{ p_publication = $($pub.publication); p_tokenID = $($pub.tokenID)}
        foreach($row in $resultGetTokenHistory) {
            $tokenHistory.Add($row) | Out-Null
        }
    }
}
$tokenHistory | ogv -Title "Token History"
"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(FINISH)","Script execution finished" | Write-Host -ForegroundColor Cyan
