[CmdletBinding()]
Param (
    $DistributorIP = '196.1.115.228',
    $DistributionDb = 'distribution',
    $InventoryServer = 'localhost',
    $InventoryDb = 'DBA_Inventory',
    $ReplTokenTableName = '[dbo].[replication_tokens]',
    $ReplTokenHistoryTableName = '[dbo].[replication_tokens]',
    $ReplTokenHistoryErrorTableName = '[dbo].[replication_tokens_insert_log]'
)

<# ****************************************************************************#
## ************** Read Tracer Tokens & Fetch History *************#
## *************************************************************************** #>
"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Get distributor [$DistributorIP] credentials from RegisteredServers List" | Write-Output
$DistributorConfig = Get-DbaRegisteredServer -Group All | ? {$_.ServerName -eq $DistributorIP} | Select-Object -First 1;
$Distributor = $DistributorConfig | Connect-DbaInstance

# Local variables
$ErrorActionPreference = 'Stop';
$startTime = Get-Date
$Dtmm = $startTime.ToString('yyyy-MM-dd HH.mm.ss')

# Extract Credentials
$distributorConString = ($DistributorConfig.ConnectionString).Split(';');
$sqlUser = $distributorConString[1]
$sqlUserPassword = ConvertTo-SecureString -String $distributorConString[2] -AsPlainText -Force
$sqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, $sqlUserPassword

# Fetch oldest unprocessed token from Inventory
"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Fetch unprocessed tokens from [$InventoryServer].[$InventoryDb].$ReplTokenTableName" | Write-Output
$tsqlOldestToken = @"
select top 1 tokenID
from $ReplTokenTableName rt
where rt.is_processed = 0 and rt.collection_time_utc >= DATEADD(HOUR,-5,SYSUTCDATETIME())
order by collection_time_utc
"@
$oldestToken = 0
$oldestToken += Invoke-DbaQuery -SqlInstance $InventoryServer -Database $InventoryDb -Query $tsqlOldestToken -EnableException | Select-Object -ExpandProperty tokenID

if($oldestToken -ne 0)
{
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

    "{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Fetch tracer token history" | Write-Output
    $publishers = @()
    $publishers += $tracerTokens | Select-Object -ExpandProperty publisher -Unique
    [System.Collections.ArrayList]$tokenHistory = @()
    foreach($srv in $publishers)
    {
        "{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(INFO)","Getting history from [$srv] publications" | Write-Output
        $srvPublications = $tokenInserted | Where-Object {$_.publisher -eq $srv}
        $pubSrvObj = Get-DbaRegisteredServer -Name $srv -Group 'Replication-Publisher' | Connect-DbaInstance
        foreach($pub in $srvPublications)
        {
            $resultGetTokenHistory = Invoke-DbaQuery -SqlInstance $pubSrvObj -Database $pub.publisher_db -Query $tsqlGetTokenHistory -SqlParameters @{ p_publication = $($pub.publication); p_tokenID = $($pub.tokenID)}
            foreach($row in $resultGetTokenHistory) {
                $tokenHistory.Add($row) | Out-Null
            }
        }
    }
    $tokenHistory | ogv -Title "Token History"

}
"{0} {1,-7} {2}" -f "($((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))","(FINISH)","Script execution finished" | Write-Output
