SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_UpdateStoreLastTouched
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

	FILE NAME: @@CHIRHO_SCHEMA@@.AutoWho_UpdateStoreLastTouched.StoredProcedure.sql

	PROCEDURE NAME: @@CHIRHO_SCHEMA@@.AutoWho_UpdateStoreLastTouched

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Each "store" table (e.g. @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore, @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore) has a
		LastTouchedBy_UTCCaptureTime field that holds a UTC datetime of when that entry was last referenced.
		By updating reference times, we prevent the purge routine from deleting query plans or SQL statements
		that are frequently referenced, and thus avoid the cost of re-inserting them again the next time 
		they are seen. 

		At this time, AutoWho is fairly stable while ServerEye is very early in development. So things
		may change, but here is how the LastTouchedBy logic works: 

			- In ServerEye:
				nothing implemented yet. Thus, this field is not yet relevant for that module

			- In AutoWho: 

				- InputBuffer store and Query plan stores (Batch & Statement) 
					Every time an IB or a QP is identified as being needed for a SPID (i.e. the SPIDs duration
					is >= the IB or QP thresholds), it is pulled and compared to the store. If missing, it is
					inserted into the store but if already present, the store "LastTouchedBy" field is updated
					with the @UTCCaptureTime of that collection run.
					This logic is primarily due to the fact that we need to hash the IB and QP to compare to the store,
					so we need to access that table a bit more heavily anyways, so we might as well incur the hit of 
					touching the LastTouchedBy field.
					The bottom line is that this proc does not need to touch those tables.

				- SQL Stmt and Batch stores
					Because we do not use a hash value that we calculate for the key for these stores, we can compare
					to the store using sql_handle and the offset fields. This means we do not need to pull the statement
					from the cache and hash it to see if it is already in the store. Thus, instead we have a very lightweight
					statement that joins the SQL stmt/batch stores and compares to the #SAR table and updates the FK columns
					with the store entries (if already present). To keep things lightweight, we do not update the store entries
					with that @UTCCaptureTime. However, to make sure that the LastTouchedBy field is ultimately updated and things
					are not wastefully purged, this procedure is called every X minutes by the AutoWho Executor and 
					updates LastTouchedBy appropriately. 

		Because the Executor is doing this (in between collector runs), we do not need to worry about these
		statements conflicting with the Collector (like we have to worry about w/Purge).

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_UpdateStoreLastTouched
*/
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @lv__errormsg					NVARCHAR(4000),
			@lv__errorsev					INT,
			@lv__errorstate					INT,
			@lv__erroroccurred				INT,
			@lv__AutoWhoStoreLastTouched	DATETIME2(7),
			@lv__AutoWhoStoreLastTouchedUTC DATETIME2(7),
			@lv__CurrentExecTime			DATETIME2(7),
			@lv__CurrentExecTimeUTC			DATETIME2(7),
			@lv__MinUTCCaptureTime			DATETIME,
			@lv__MaxUTCCaptureTime			DATETIME,
			@lv__RC							BIGINT,
			@lv__DurationStartUTC			DATETIME,
			@lv__DurationEndUTC				DATETIME,
			@lv__MinFKSQLStmtStoreID		BIGINT,
			@lv__MaxFKSQLStmtStoreID		BIGINT,
			@lv__MinFKSQLBatchStoreID		BIGINT,
			@lv__MaxFKSQLBatchStoreID		BIGINT;

	--SET @lv__CurrentExecTime = DATEADD(SECOND, -10, SYSDATETIME());	--a fudge factor to avoid race conditions
	SET @lv__CurrentExecTimeUTC = DATEADD(SECOND, -10, SYSUTCDATETIME()); --a fudge factor to avoid race conditions
	SET @lv__DurationStartUTC = SYSUTCDATETIME();
	SET @lv__erroroccurred = 0;

	SELECT 
		@lv__AutoWhoStoreLastTouched = p.LastProcessedTime,
		@lv__AutoWhoStoreLastTouchedUTC = p.LastProcessedTimeUTC
	FROM @@CHIRHO_SCHEMA@@.CoreXR_ProcessingTimes p WITH (FORCESEEK)
	WHERE p.Label = N'AutoWhoStoreLastTouched';

	IF @lv__AutoWhoStoreLastTouched IS NULL
	BEGIN
		--Set to the very first capture time in SAR that we have
		SELECT 
			@lv__AutoWhoStoreLastTouched = ss.SPIDCaptureTime,
			@lv__AutoWhoStoreLastTouchedUTC = ss.UTCCaptureTime
		FROM (
			SELECT TOP 1 
				UTCCaptureTime,
				SPIDCaptureTime
			FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
			ORDER BY sar.UTCCaptureTime ASC
		) ss;

		--No records, just return, and leave the CoreXR.ProcessingTimes tag with NULL time values
		IF @lv__AutoWhoStoreLastTouched IS NULL
		BEGIN
			RETURN 0;
		END
	END

	--If we get here, we have a last-touched value that is the most recent @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes.UTCCaptureTime value
	--that has been processed by this procedure previously. We want to grab SAR rows for all capture times after that watermark 
	-- up to about 10 seconds ago.
	IF OBJECT_ID('tempdb..#StoreCaptureTimeList') IS NOT NULL DROP TABLE #StoreCaptureTimeList;
	CREATE TABLE #StoreCaptureTimeList (
		SPIDCaptureTime	DATETIME NOT NULL,
		UTCCaptureTime  DATETIME NOT NULL
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #StoreCaptureTimeList(UTCCaptureTime);

	INSERT INTO #StoreCaptureTimeList (
		SPIDCaptureTime,
		UTCCaptureTime
	)
	SELECT 
		ct.SPIDCaptureTime,
		ct.UTCCaptureTime
	FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
	WHERE ct.UTCCaptureTime > @lv__AutoWhoStoreLastTouchedUTC
	AND ct.UTCCaptureTime <= @lv__CurrentExecTimeUTC;

	SET @lv__RC = ROWCOUNT_BIG();

	IF @lv__RC = 0
	BEGIN
		--This scenario occurs when the Collector isn't running but the ChiRho master job IS running.
		--We leave the high watermark where it is and exit.
		RETURN 0;
	END

	--Ok, we have new capture times to process. Get the time range that we'll filter SAR by.
	SELECT 
		   @lv__MinUTCCaptureTime = MIN(t.UTCCaptureTime),
		   @lv__MaxUTCCaptureTime = MAX(t.UTCCaptureTime)
	FROM #StoreCaptureTimeList t;

	--use an intermediate table to calculate the distinct values, so we don't have to scan SAR once for each store.
	CREATE TABLE #DistinctStoreFKsWithMaxCaptureTime (
		FKSQLStmtStoreID	BIGINT, 
		FKSQLBatchStoreID	BIGINT,
		MaxUTCCaptureTime	DATETIME
	);

	INSERT INTO #DistinctStoreFKsWithMaxCaptureTime (
		FKSQLStmtStoreID,
		FKSQLBatchStoreID,
		MaxUTCCaptureTime
	)
	SELECT 
		sar.FKSQLStmtStoreID,
		sar.FKSQLBatchStoreID,
		MAX(sar.UTCCaptureTime)
	FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK)
	WHERE sar.UTCCaptureTime BETWEEN @lv__MinUTCCaptureTime AND @lv__MaxUTCCaptureTime
	AND (sar.FKSQLStmtStoreID IS NOT NULL OR sar.FKSQLBatchStoreID IS NOT NULL)
	GROUP BY sar.FKSQLStmtStoreID,
		sar.FKSQLBatchStoreID
	OPTION(RECOMPILE);

	--Since the store tables are clustered on their StoreID, find the min/max Store IDs
	--so we can seek on that clustered index
	SELECT 
		@lv__MinFKSQLStmtStoreID = MIN(d.FKSQLStmtStoreID),
		@lv__MaxFKSQLStmtStoreID = MAX(d.FKSQLStmtStoreID),
		@lv__MinFKSQLBatchStoreID = MIN(d.FKSQLBatchStoreID),
		@lv__MaxFKSQLBatchStoreID = MAX(d.FKSQLBatchStoreID)
	FROM #DistinctStoreFKsWithMaxCaptureTime d;

	IF @lv__MinFKSQLStmtStoreID IS NOT NULL
	BEGIN
		BEGIN TRY
			SET @lv__RC = 0;

			UPDATE targ 
			SET targ.LastTouchedBy_UTCCaptureTime = ss.LastTouched 
			FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore targ
				INNER JOIN (
				SELECT t.FKSQLStmtStoreID, MAX(t.MaxUTCCaptureTime) as LastTouched
				FROM #DistinctStoreFKsWithMaxCaptureTime t
				WHERE t.FKSQLStmtStoreID IS NOT NULL
				GROUP BY t.FKSQLStmtStoreID
				) ss
					ON targ.PKSQLStmtStoreID = ss.FKSQLStmtStoreID
			WHERE targ.PKSQLStmtStoreID BETWEEN @lv__MinFKSQLStmtStoreID AND @lv__MaxFKSQLStmtStoreID
			AND ss.LastTouched > targ.LastTouchedBy_UTCCaptureTime
			OPTION(RECOMPILE);

			SET @lv__RC = ROWCOUNT_BIG();
			SET @lv__DurationEndUTC = SYSUTCDATETIME();

			IF @lv__RC > 0
			BEGIN
				SET @lv__errormsg = N'Updated LastTouched for ' + CONVERT(NVARCHAR(20),@lv__RC) + 
					' SQL stmt entries in ' + 
					CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStartUTC, @lv__DurationEndUTC)) + 
					N' milliseconds.';

				EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='SQLStmtLastTouch', @Message=@lv__errormsg; 
			END
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @lv__errorsev = ERROR_SEVERITY();
			SET @lv__errorstate = ERROR_STATE();
			SET @lv__erroroccurred = 1;

			SET @lv__errormsg = N'Update of SQL Stmt Store LastTouched field failed with error # ' + 
				CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; severity: ' + CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + 
				N'; state: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; message: ' + ERROR_MESSAGE();

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='CATCH block', @Message=@lv__errormsg;
		END CATCH
	END 

	SET @lv__DurationStartUTC = SYSUTCDATETIME();

	IF @lv__erroroccurred = 0 AND @lv__MinFKSQLBatchStoreID IS NOT NULL 
	BEGIN
		BEGIN TRY
			IF EXISTS (SELECT * FROM #DistinctStoreFKsWithMaxCaptureTime d WHERE d.FKSQLBatchStoreID IS NOT NULL)
			BEGIN
				SET @lv__RC = 0;

				UPDATE targ 
				SET targ.LastTouchedBy_UTCCaptureTime = ss.LastTouched
				FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore targ
					INNER JOIN (
					SELECT t.FKSQLBatchStoreID, MAX(t.MaxUTCCaptureTime) as LastTouched
					FROM #DistinctStoreFKsWithMaxCaptureTime t
					WHERE t.FKSQLBatchStoreID IS NOT NULL
					GROUP BY t.FKSQLBatchStoreID
					) ss
						ON targ.PKSQLBatchStoreID = ss.FKSQLBatchStoreID
				WHERE targ.PKSQLBatchStoreID BETWEEN @lv__MinFKSQLBatchStoreID AND @lv__MaxFKSQLBatchStoreID
				AND ss.LastTouched > targ.LastTouchedBy_UTCCaptureTime;

				SET @lv__RC = ROWCOUNT_BIG();
				SET @lv__DurationEndUTC = SYSUTCDATETIME();

				IF @lv__RC > 0
				BEGIN
					SET @lv__errormsg = N'Updated LastTouched for ' + CONVERT(NVARCHAR(20),@lv__RC) + 
						' SQL batch entries in ' + 
						CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStartUTC, @lv__DurationEndUTC)) + 
						N' milliseconds.';

					EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='SQLBatchLastTouch', @Message=@lv__errormsg; 
				END
			END --if batches exist
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @lv__errorsev = ERROR_SEVERITY();
			SET @lv__errorstate = ERROR_STATE();
			SET @lv__erroroccurred = 1;

			SET @lv__errormsg = N'Update of SQL Batch Store LastTouched field failed with error # ' + 
				CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; severity: ' + CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + 
				N'; state: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; message: ' + ERROR_MESSAGE();

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='CATCH block', @Message=@lv__errormsg;
		END CATCH
	END 

	IF @lv__erroroccurred = 1
	BEGIN
		--If we have multiple failures of this procedure, we don't want it to fail to move the high watermark forward.
		--If there are any capture times in #StoreCaptureTimeList that are older than 45 minutes ago, then we've
		--probably been failing multiple times in a row (the default interval should be about 15 minutes), so we 
		--set the high watermark to the most recent capture time older than 45 minutes ago. If there AREN'T any 
		-- capture times that old in #StoreCaptureTimeList, then we probably haven't been failing for very long,
		-- and perhaps it is transient. So we simply don't update the watermark at all.
		IF EXISTS (SELECT * FROM #StoreCaptureTimeList l
					WHERE l.UTCCaptureTime < DATEADD(MINUTE, -45, @lv__CurrentExecTimeUTC))
		BEGIN
			UPDATE targ 
			SET LastProcessedTime = ss.SPIDCaptureTime,
				LastProcessedTimeUTC = ss.UTCCaptureTime
			FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
				CROSS JOIN (
					SELECT TOP 1
						l.UTCCaptureTime,
						l.SPIDCaptureTime
					FROM #StoreCaptureTimeList l
					WHERE l.UTCCaptureTime < DATEADD(MINUTE, -45, @lv__CurrentExecTimeUTC)
					ORDER BY l.UTCCaptureTime DESC
				) ss
			WHERE targ.Label = N'AutoWhoStoreLastTouched';
		END
	END
	ELSE
	BEGIN
		--When no error occurs, we set the last-touched values to 
		-- the maximum capture times that we processed in this run
		UPDATE targ 
		SET LastProcessedTime = ss.SPIDCaptureTime,
			LastProcessedTimeUTC = ss.UTCCaptureTime
		FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
			CROSS JOIN (
				SELECT TOP 1
					l.UTCCaptureTime,
					l.SPIDCaptureTime
				FROM #StoreCaptureTimeList l
				ORDER BY l.UTCCaptureTime DESC
			) ss
		WHERE targ.Label = N'AutoWhoStoreLastTouched';
	END

	RETURN 0;
END
GO