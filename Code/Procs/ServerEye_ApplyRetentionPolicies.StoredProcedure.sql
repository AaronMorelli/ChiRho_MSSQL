SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[ApplyRetentionPolicies]
/*
	Copyright 2016, 2024 Aaron Morelli

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

		http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.

	------------------------------------------------------------------------

	PROJECT NAME: ChiRho for SQL Server https://github.com/AaronMorelli/ChiRho_MSSQL

	PROJECT DESCRIPTION: A T-SQL toolkit for troubleshooting performance and stability problems on SQL Server instances

	FILE NAME: ServerEye.ApplyRetentionPolicies.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.ApplyRetentionPolicies

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs on the schedule defined via parameters to CoreXR.ChiRhoMaster, 
		and applies various retention policies defined in ServerEye.Options

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.ApplyRetentionPolicies
*/
AS
BEGIN
	SET NOCOUNT ON;

	--No logic actually implement yet. The below logic is a hold-over from the AutoWho purge proc and may be useful once I implement this.
	RETURN 0;


	DECLARE @lv__ErrorMessage NVARCHAR(4000),
			@lv__ErrorState INT,
			@lv__ErrorSeverity INT,
			@lv__ErrorLoc NVARCHAR(100),
			@lv__RowCount BIGINT;

	BEGIN TRY
		SET @lv__ErrorLoc = N'Variable declare';
		DECLARE 
			--from ServerEye.Options table
			@opt__Retention_Days					INT,
			@opt__PurgeUnextractedData						NCHAR(1),
			@max__RetentionHours							INT,

			--misc general purpose
			@lv__ProcRC										INT,
			@lv__tmpStr										NVARCHAR(4000),
			@lv__tmpMinID									BIGINT, 
			@lv__tmpMaxID									BIGINT,
			@lv__nullstring									NVARCHAR(8),
			@lv__nullint									INT,
			@lv__nullsmallint								SMALLINT,

			--derived or intermediate values
			@lv__MaxUTCCaptureTime							DATETIME,
			@lv__MinPurge_UTCCaptureTime					DATETIME,
			@lv__MaxPurge_UTCCaptureTime					DATETIME,
			@lv__TableSize_ReservedPages					BIGINT,
			@lv__HardDeleteCaptureTime						DATETIME,
			@lv__NextDWExtractionCaptureTime				DATETIME
			;

		SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" would collide with a DMV value
		SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
		SET @lv__nullsmallint = -929;			-- overlapping with some special system value

		SET @lv__ErrorLoc = N'Temp table creation';
		CREATE TABLE #ServerEyeDistinctStoreKeys (
			[FKSQLStmtStoreID]		BIGINT NULL,
			[FKSQLBatchStoreID]		BIGINT NULL,
			[FKInputBufferStoreID]	BIGINT NULL,
			[FKQueryPlanBatchStoreID] BIGINT NULL,
			[FKQueryPlanStmtStoreID] BIGINT NULL
		);

		CREATE TABLE #StoreTableIDsToPurge (
			ID BIGINT NOT NULL PRIMARY KEY CLUSTERED
		);

		SET @lv__ErrorLoc = N'Option obtain';
		SELECT 
			@opt__Retention_Days			= [Retention_Days]
		FROM ServerEye.Options;


		--SET @retainAfter__IdleSPIDs_NoTran = DATEADD(HOUR, 0 - @opt__Retention_IdleSPIDs_NoTran, GETUTCDATE());

		SET @lv__ErrorLoc = N'Next extract & Hard Delete';
		SELECT 
			@lv__NextDWExtractionCaptureTime = MIN(ct.UTCCaptureTime)
		FROM ServerEye.CaptureTimes ct
		WHERE ct.ExtractedForDW = 0
		AND ct.CollectionInitiatorID = 255;	--DW extraction only occurs for captures by the background collector.

		IF @lv__NextDWExtractionCaptureTime IS NULL
		BEGIN
			SET @lv__NextDWExtractionCaptureTime = GETUTCDATE();
		END

		/* Calculate our "Hard-delete" policy. Anything older than this *WILL* be deleted by this purge run. 
			It is based on @opt__Retention_Days, but if the administrator has configured this install
			to prevent the purging of unextracted-to-DW capture times, then the hard delete cannot be more
			recent than our @lv__NextDWExtractionCaptureTime.
		*/
		SELECT 
			@lv__HardDeleteCaptureTime = ss.UTCCaptureTime
		FROM (
			SELECT TOP 1 ct.UTCCaptureTime
			FROM ServerEye.CaptureTimes ct
			WHERE ct.CollectionInitiatorID = 255
			AND ct.RunWasSuccessful = 1
			AND ct.UTCCaptureTime < DATEADD(DAY, 0 - @opt__Retention_Days, GETUTCDATE())
			ORDER BY ct.UTCCaptureTime DESC
		) ss;

		IF @lv__HardDeleteCaptureTime IS NULL
		BEGIN
			SET @lv__HardDeleteCaptureTime = DATEADD(DAY, 0 - @opt__Retention_Days, GETUTCDATE());
		END

		IF @opt__PurgeUnextractedData = N'N'
			AND @lv__HardDeleteCaptureTime >= @lv__NextDWExtractionCaptureTime
		BEGIN
			--We raise a warning to the log b/c our hard-delete timeframe was affected by rows that probably
			--should have been extracted by now but haven't yet.
			SET @lv__ErrorMessage = 'Original hard-delete boundary of "' + ISNULL(CONVERT(VARCHAR(20),@lv__HardDeleteCaptureTime),'<null>') + 
					'" has been changed to "' + ISNULL(CONVERT(VARCHAR(20),DATEADD(SECOND, -10, @lv__NextDWExtractionCaptureTime)),'<null>') + '" 
					because of captures not yet extracted to the DW.';

			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=1, @TraceID=NULL, @Location=N'Hard-delete warning', @Message=@lv__ErrorMessage;

			SET @lv__HardDeleteCaptureTime = DATEADD(second, -10, @lv__NextDWExtractionCaptureTime);
		END
	

		/* For the "Store" tables, which aren't tied to any single SPIDCaptureTime, there are 3 main criteria:

			- Store table must be a non-trivial size
			- Store entry is not referenced anymore
			- Store entry's last-touched datetime must be older than our longest retention period (except for the hard-delete retention)
		*/

		/*
		SET @lv__ErrorLoc = N'Store prep';
		SELECT @max__RetentionHours = ss1.col1
		FROM (
			SELECT TOP 1 col1 
			FROM (
				SELECT @opt__Retention_IdleSPIDs_NoTran as col1	UNION
				SELECT @opt__Retention_IdleSPIDs_WithShortTran UNION
				SELECT @opt__Retention_IdleSPIDs_WithLongTran UNION
				SELECT @opt__Retention_IdleSPIDs_HighTempDB UNION
				SELECT @opt__Retention_ActiveLow UNION
				SELECT @opt__Retention_ActiveMedium	UNION
				SELECT @opt__Retention_ActiveHigh UNION
				SELECT @opt__Retention_ActiveBatch
			) ss0
			ORDER BY col1 DESC
		) ss1;
		--if NULL somehow (this shouldn't happen), default to a week.
		SET @max__RetentionHours = ISNULL(@max__RetentionHours,168); 
		*/

		/*
		--One scan through the SAR table to construct a distinct-keys list is much
		-- more efficient than the previous code, which joined SAR in every DELETE
		--Note that we totally ignore CollectionInitiatorID here.
		SET @lv__ErrorLoc = N'Distinct Keys';
		INSERT INTO #ServerEyeDistinctStoreKeys (
			[FKSQLStmtStoreID],
			[FKSQLBatchStoreID],
			[FKInputBufferStoreID],
			[FKQueryPlanBatchStoreID],
			[FKQueryPlanStmtStoreID]
		)
		SELECT DISTINCT 
			sar.FKSQLStmtStoreID,
			sar.FKSQLBatchStoreID,
			sar.FKInputBufferStoreID,
			sar.FKQueryPlanBatchStoreID,
			sar.FKQueryPlanStmtStoreID
		FROM ServerEye.SessionsAndRequests sar WITH (NOLOCK)
		;
		*/

		/*
		SET @lv__ErrorLoc = N'IB delete';
		SELECT @lv__TableSize_ReservedPages = ss.rsvdpgs
		FROM (
			SELECT SUM(ps.reserved_page_count) as rsvdpgs
			FROM sys.dm_db_partition_stats ps
				INNER JOIN sys.objects o
					ON ps.object_id = o.object_id
			WHERE o.name = N'InputBufferStore'
			AND o.type = 'U'
		) ss;

		IF @lv__TableSize_ReservedPages > 250*1024/8		--250 MB
		BEGIN
			TRUNCATE TABLE #StoreTableIDsToPurge;

			INSERT INTO #StoreTableIDsToPurge (
				ID 
			)
			SELECT targ.PKInputBufferStoreID
			FROM (SELECT DISTINCT sar.FKInputBufferStoreID 
					FROM #ServerEyeDistinctStoreKeys sar WITH (NOLOCK)
					WHERE sar.FKInputBufferStoreID IS NOT NULL) sar
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore targ 
					ON targ.PKInputBufferStoreID = sar.FKInputBufferStoreID
			WHERE targ.LastTouchedBy_UTCCaptureTime < DATEADD(HOUR, 0-@max__RetentionHours, GETUTCDATE())
			AND sar.FKInputBufferStoreID IS NULL 
			OPTION(RECOMPILE, FORCE ORDER);

			SELECT @lv__tmpMinID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID ASC) xapp1;

			SELECT @lv__tmpMaxID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID DESC) xapp1;

			DELETE targ 
			FROM #StoreTableIDsToPurge t
				INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore targ
					ON targ.PKInputBufferStoreID = t.ID
			WHERE targ.PKInputBufferStoreID BETWEEN @lv__tmpMinID AND @lv__tmpMaxID
			OPTION(FORCE ORDER, RECOMPILE);

						SET @lv__RowCount = ROWCOUNT_BIG();
						EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore.';
		END
		*/

		/*
		SET @lv__ErrorLoc = N'QPBS delete';
		SELECT @lv__TableSize_ReservedPages = ss.rsvdpgs
		FROM (
			SELECT SUM(ps.reserved_page_count) as rsvdpgs
			FROM sys.dm_db_partition_stats ps
				INNER JOIN sys.objects o
					ON ps.object_id = o.object_id
			WHERE o.name = N'QueryPlanBatchStore'
			AND o.type = 'U'
		) ss;

		IF @lv__TableSize_ReservedPages > 500*1024/8
		BEGIN
			TRUNCATE TABLE #StoreTableIDsToPurge;

			INSERT INTO #StoreTableIDsToPurge (
				ID 
			)
			SELECT targ.PKQueryPlanBatchStoreID
			FROM (SELECT DISTINCT sar.FKQueryPlanBatchStoreID 
					FROM #ServerEyeDistinctStoreKeys sar WITH (NOLOCK)
					WHERE sar.FKQueryPlanBatchStoreID IS NOT NULL) sar
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore targ
					ON targ.PKQueryPlanBatchStoreID = sar.FKQueryPlanBatchStoreID
			WHERE targ.LastTouchedBy_UTCCaptureTime < DATEADD(HOUR, 0-@max__RetentionHours, GETUTCDATE())
			AND sar.FKQueryPlanBatchStoreID IS NULL
			OPTION(RECOMPILE, FORCE ORDER);

			SELECT @lv__tmpMinID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID ASC) xapp1;

			SELECT @lv__tmpMaxID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID DESC) xapp1;

			DELETE targ 
			FROM #StoreTableIDsToPurge t
				INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore targ
					ON targ.PKQueryPlanBatchStoreID = t.ID
			WHERE targ.PKQueryPlanBatchStoreID BETWEEN @lv__tmpMinID AND @lv__tmpMaxID
			OPTION(FORCE ORDER, RECOMPILE);

						SET @lv__RowCount = ROWCOUNT_BIG();
						EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore.';
		END
		*/

		/*
		SET @lv__ErrorLoc = N'QPSS delete';
		SELECT @lv__TableSize_ReservedPages = ss.rsvdpgs
		FROM (
			SELECT SUM(ps.reserved_page_count) as rsvdpgs
			FROM sys.dm_db_partition_stats ps
				INNER JOIN sys.objects o
					ON ps.object_id = o.object_id
			WHERE o.name = N'QueryPlanStmtStore'
			AND o.type = 'U'
		) ss;

		IF @lv__TableSize_ReservedPages > 500*1024/8
		BEGIN
			TRUNCATE TABLE #StoreTableIDsToPurge;

			INSERT INTO #StoreTableIDsToPurge (
				ID 
			)
			SELECT targ.PKQueryPlanStmtStoreID
			FROM (SELECT DISTINCT sar.FKQueryPlanStmtStoreID 
					FROM #ServerEyeDistinctStoreKeys sar WITH (NOLOCK)
					WHERE sar.FKQueryPlanStmtStoreID IS NOT NULL) sar
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore targ
					ON targ.PKQueryPlanStmtStoreID = sar.FKQueryPlanStmtStoreID
			WHERE targ.LastTouchedBy_UTCCaptureTime < DATEADD(HOUR, 0-@max__RetentionHours, GETUTCDATE())
			AND sar.FKQueryPlanStmtStoreID IS NULL
			OPTION(RECOMPILE, FORCE ORDER);

			SELECT @lv__tmpMinID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID ASC) xapp1;

			SELECT @lv__tmpMaxID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID DESC) xapp1;

			DELETE targ 
			FROM #StoreTableIDsToPurge t
				INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore targ
					ON targ.PKQueryPlanStmtStoreID = t.ID
			WHERE targ.PKQueryPlanStmtStoreID BETWEEN @lv__tmpMinID AND @lv__tmpMaxID
			OPTION(FORCE ORDER, RECOMPILE);

						SET @lv__RowCount = ROWCOUNT_BIG();
						EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore.';
		END
		*/

		/*
		SET @lv__ErrorLoc = N'SBS delete';
		SELECT @lv__TableSize_ReservedPages = ss.rsvdpgs
		FROM (
			SELECT SUM(ps.reserved_page_count) as rsvdpgs
			FROM sys.dm_db_partition_stats ps
				INNER JOIN sys.objects o
					ON ps.object_id = o.object_id
			WHERE o.name = N'SQLBatchStore'
			AND o.type = 'U'
		) ss;

		IF @lv__TableSize_ReservedPages > 500*1024/8
		BEGIN
			TRUNCATE TABLE #StoreTableIDsToPurge;

			INSERT INTO #StoreTableIDsToPurge (
				ID 
			)
			SELECT targ.PKSQLBatchStoreID
			FROM (SELECT DISTINCT sar.FKSQLBatchStoreID 
					FROM #ServerEyeDistinctStoreKeys sar WITH (NOLOCK)
					WHERE sar.FKSQLBatchStoreID IS NOT NULL) sar
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore targ
					ON targ.PKSQLBatchStoreID = sar.FKSQLBatchStoreID
			WHERE targ.LastTouchedBy_UTCCaptureTime < DATEADD(HOUR, 0-@max__RetentionHours, GETUTCDATE())
			AND sar.FKSQLBatchStoreID IS NULL
			OPTION(RECOMPILE, FORCE ORDER);

			SELECT @lv__tmpMinID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID ASC) xapp1;

			SELECT @lv__tmpMaxID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID DESC) xapp1;

			DELETE targ 
			FROM #StoreTableIDsToPurge t
				INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore targ
					ON targ.PKSQLBatchStoreID = t.ID
			WHERE targ.PKSQLBatchStoreID BETWEEN @lv__tmpMinID AND @lv__tmpMaxID
			OPTION(FORCE ORDER, RECOMPILE);

						SET @lv__RowCount = ROWCOUNT_BIG();
						EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore.';
		END

		SET @lv__ErrorLoc = N'SSS delete';
		SELECT @lv__TableSize_ReservedPages = ss.rsvdpgs
		FROM (
			SELECT SUM(ps.reserved_page_count) as rsvdpgs
			FROM sys.dm_db_partition_stats ps
				INNER JOIN sys.objects o
					ON ps.object_id = o.object_id
			WHERE o.name = N'SQLStmtStore'
			AND o.type = 'U'
		) ss;
		*/

		/*
		IF @lv__TableSize_ReservedPages > 500*1024/8
		BEGIN
			TRUNCATE TABLE #StoreTableIDsToPurge;

			INSERT INTO #StoreTableIDsToPurge (ID)
			SELECT targ.PKSQLStmtStoreID
			FROM (SELECT DISTINCT sar.FKSQLStmtStoreID 
					FROM #ServerEyeDistinctStoreKeys sar WITH (NOLOCK)
					WHERE sar.FKSQLStmtStoreID IS NOT NULL) sar
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore targ
					ON targ.PKSQLStmtStoreID = sar.FKSQLStmtStoreID
			WHERE targ.LastTouchedBy_UTCCaptureTime < DATEADD(HOUR, 0-@max__RetentionHours, GETUTCDATE())
			AND sar.FKSQLStmtStoreID IS NULL
			OPTION(RECOMPILE, FORCE ORDER);

			SELECT @lv__tmpMinID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID ASC) xapp1;

			SELECT @lv__tmpMaxID = xapp1.ID
			FROM (SELECT NULL as col1) ss
				OUTER APPLY (SELECT TOP 1 t.ID
							FROM #StoreTableIDsToPurge t
							ORDER BY t.ID DESC) xapp1;

			DELETE targ 
			FROM #StoreTableIDsToPurge t
				INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore targ
					ON targ.PKSQLStmtStoreID = t.ID
			WHERE targ.PKSQLStmtStoreID BETWEEN @lv__tmpMinID AND @lv__tmpMaxID
			OPTION(FORCE ORDER, RECOMPILE);

						SET @lv__RowCount = ROWCOUNT_BIG();
						EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore.';
		END
		*/

		/* Will reconsider purge for user collection later
		DELETE targ 
		FROM ServerEye.UserCollectionTimes targ
		WHERE targ.SPIDCaptureTime <= @lv__HardDeleteCaptureTime;

					SET @lv__RowCount = ROWCOUNT_BIG();
					EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from ServerEye.UserCollectionTimes.';
		*/


		--Get rid of metadata
		SET @lv__ErrorLoc = N'Metadata Deletes';
		DELETE ServerEye.CaptureTimes
		WHERE CollectionInitiatorID = 255
		AND UTCCaptureTime <= @lv__MaxUTCCaptureTime
		AND UTCCaptureTime <= @lv__HardDeleteCaptureTime;

					SET @lv__RowCount = ROWCOUNT_BIG();
					EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from ServerEye.CaptureTimes.';


		--We just (potentially) deleted rows from ServerEye.CaptureTimes. Any ordinal caches that contain capture times
		--that were just removed are no longer useful. Delete these, and the position markers that depend on them
		IF OBJECT_ID('tempdb..#invalidOrdCache') IS NOT NULL DROP TABLE #invalidOrdCache;
		CREATE TABLE #invalidOrdCache (
			Utility					NVARCHAR(30) NOT NULL,
			CollectionInitiatorID	TINYINT NOT NULL,
			StartTime				DATETIME NOT NULL,
			EndTime					DATETIME NOT NULL
		);

		INSERT INTO #invalidOrdCache (
			Utility,
			CollectionInitiatorID,
			StartTime,
			EndTime
		)
		SELECT DISTINCT 
			ord.Utility,
			ord.CollectionInitiatorID,
			ord.StartTime, 
			ord.EndTime
		FROM @@CHIRHO_SCHEMA@@.CoreXR_CaptureOrdinalCache ord
		WHERE ord.Utility IN (N'ServerEye')		--ServerEye-related utilities only
		AND NOT EXISTS (
			SELECT *
			FROM ServerEye.CaptureTimes ct
			WHERE ct.UTCCaptureTime = ord.CaptureTimeUTC
		);

		DELETE p
		FROM @@CHIRHO_SCHEMA@@.CoreXR_OrdinalCachePosition p
		WHERE EXISTS (
			SELECT * 
			FROM #invalidOrdCache t
			WHERE t.Utility = p.Utility
			AND t.CollectionInitiatorID = p.CollectionInitiatorID
			AND t.StartTime = p.StartTime
			AND t.EndTime = p.EndTime
		);

					SET @lv__RowCount = ROWCOUNT_BIG();
					EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from ServerEye.CaptureOrdinalPosition.';


		DELETE c
		FROM @@CHIRHO_SCHEMA@@.CoreXR_CaptureOrdinalCache c
		WHERE EXISTS (
			SELECT * 
			FROM #invalidOrdCache t
			WHERE t.Utility = c.Utility
			AND t.CollectionInitiatorID = c.CollectionInitiatorID
			AND t.StartTime = c.StartTime
			AND t.EndTime = c.EndTime
		);

					SET @lv__RowCount = ROWCOUNT_BIG();
					EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from ServerEye.CaptureOrdinalCache.';


		DELETE FROM CoreXR.[Traces]
		WHERE Utility = N'ServerEye'
		AND CreateTimeUTC <= @lv__HardDeleteCaptureTime;

					SET @lv__RowCount = ROWCOUNT_BIG();
					EXEC ServerEye.LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='Rows deleted from CoreXR.Traces.';


		DELETE FROM ServerEye.[Log] WHERE LogDTUTC <= @lv__HardDeleteCaptureTime;
		RETURN 0;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;

		SET @lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorSeverity = ERROR_SEVERITY();

		SET @lv__ErrorMessage = N'Exception occurred at location ("' + ISNULL(@lv__ErrorLoc,N'<null>') + '"). Error #: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()), N'<null>') +
			N'; Severity: ' + ISNULL(CONVERT(NVARCHAR(20),@lv__ErrorSeverity), N'<null>') + 
			N'; State: ' + ISNULL(CONVERT(NVARCHAR(20),@lv__ErrorState),N'<null>') + 
			N'; Message: ' + ISNULL(ERROR_MESSAGE(),N'<null>');

		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@lv__ErrorMessage;

		RAISERROR(@lv__ErrorMessage, @lv__ErrorSeverity, @lv__ErrorState);
		RETURN -999;
	END CATCH
END
GO
