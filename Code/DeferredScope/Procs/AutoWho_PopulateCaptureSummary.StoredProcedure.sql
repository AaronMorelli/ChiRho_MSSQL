SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummary
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

	FILE NAME: AutoWho_PopulateCaptureSummary.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_PopulateCaptureSummary

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Pulls data from the AutoWho base tables and aggregates various characteristics of the data into a summary row per SPIDCaptureTime/UTCCaptureTime. 
			This procedure assumes that it will only be called by other AutoWho procs (or by sp_XR_SessionViewer), thus error-handling is limited.
			It catches errors and writes them to the AutoWho.Log table, and simply returns -1 if it does not succeed.

			NOTE: The delta logic has been moved to a sub-proc and is now driven by a new "CaptureSummaryDeltaPopulated" flag in @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes.
			These changes were made for ease of accuracy and understandability of the code.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummary @CollectionInitiatorID=255, @StartTime='2016-04-25 08:00', @EndTime='2016-04-25 09:00'
*/
(
	@CollectionInitiatorID	TINYINT,
	@StartTime				DATETIME,	--We always expect these times to be in local time
	@EndTime				DATETIME	--Logic exists in the proc below to handle the necessary UTC translation
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	BEGIN TRY

		--This block of code copied directly from the AutoWho Collector procedure; they are essentially system constants
		DECLARE
			@enum__waitspecial__none			TINYINT,
			@enum__waitspecial__lck				TINYINT,
			@enum__waitspecial__pgblocked		TINYINT,
			@enum__waitspecial__pgio			TINYINT,
			@enum__waitspecial__pg				TINYINT,
			@enum__waitspecial__latchblocked	TINYINT,
			@enum__waitspecial__latch			TINYINT,
			@enum__waitspecial__cxp				TINYINT,
			@enum__waitspecial__other			TINYINT,
			@codeloc							VARCHAR(20),
			@errmsg								VARCHAR(MAX),
			@scratch_int						INT,
			@lv__nullstring						NVARCHAR(8),
			@lv__nullint						INT,
			@lv__nullsmallint					SMALLINT;

		SET @enum__waitspecial__none =			CONVERT(TINYINT, 0);
		SET @enum__waitspecial__lck =			CONVERT(TINYINT, 5);
		SET @enum__waitspecial__pgblocked =		CONVERT(TINYINT, 7);
		SET @enum__waitspecial__pgio =			CONVERT(TINYINT, 10);
		SET @enum__waitspecial__pg =			CONVERT(TINYINT, 15);
		SET @enum__waitspecial__latchblocked =	CONVERT(TINYINT, 17);
		SET @enum__waitspecial__latch =			CONVERT(TINYINT, 20);
		SET @enum__waitspecial__cxp =			CONVERT(TINYINT, 30);
		SET @enum__waitspecial__other =			CONVERT(TINYINT, 25);

		SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" would collide with a DMV value
		SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
		SET @lv__nullsmallint = -929;			-- overlapping with some special system value

		--If there are no captures between start and end, we need to return 1;
		IF NOT EXISTS (SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct WHERE ct.SPIDCaptureTime BETWEEN @StartTime AND @EndTime)
		BEGIN
			RETURN 1;
		END


		/* Conceptually what we want to do is aggregate info from SAR and TAW down into a single capture time, so that for each capture time,
			we have info about what was observed at that time. This is a fairly simple concept, except that there are some complicating
			edge cases that we need to handle.

			1. We may not have SAR/TAW data at every capture time, so in order to have a "summary row" for the capture time, we need logic
				that inserts a dummy row for every capture that is "empty".

			2. Some of our metrics are delta metrics, i.e. they compare the aggregated metrics for a given capture time with the corresponding
				metrics at the previous capture time. Thus, we need the aggregated data for the previous capture, but it may or may not have been 
				processed already by another run if this proc. Thus, we must proceed with care.

			3. We need to correctly handle cases where the time "falls back" due to Daylight Savings Time. Thus, when the clock falls back
				from 1:59am to 1:00am and we have 2 straight hours with overlapping Capture Times, we need to correctly handle these so
				that delta logic compares to the "true" previous capture, and that we do not accidentally allow certain captures to be
				"skipped".

			The below logic is structured carefully to address these 3 complications.
		*/


		/*
			First, pull the capture times. Since we expect the user to enter local times, we take care of translating to UTC. Note that if 
			the user specifies a time between 1am and 2am on the "fall-back" day for DST, then a single @StartTime/@EndTime range 
			will result in *TWO* UTC ranges. We keep things a bit simpler by just pulling the data for all of the UTC values that
			match this local time range.
		*/
		SET @codeloc = '#CTTP creation';
		CREATE TABLE #CTTP (
			SPIDCaptureTime			DATETIME NOT NULL,
			UTCCaptureTime			DATETIME NOT NULL,
			RunWasSuccessful		TINYINT NOT NULL,
			CaptureSummaryPopulated TINYINT NOT NULL,
			RowsActuallyFound		NCHAR(1) NOT NULL
		);
		CREATE UNIQUE CLUSTERED INDEX CL1 ON #CTTP (UTCCaptureTime);


		SET @codeloc = 'Calc Min/Max';
		DECLARE @MinUTCCaptureTime DATETIME,
				@MaxUTCCaptureTime DATETIME;
				
		SELECT 
			@MinUTCCaptureTime = MIN(ct.UTCCaptureTime),
			@MaxUTCCaptureTime = MAX(ct.UTCCaptureTime)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
		AND ct.SPIDCaptureTime BETWEEN @StartTime AND @EndTime
		AND CaptureSummaryPopulated=0;	--Skip processing for capture times that we've already done before.
										--Note that the delta logic (in the sub-proc) can't apply this filter
										--since it needs info for certain times whether they have been calculated already or not,
										--i.e. to do deltas.

		IF @MinUTCCaptureTime IS NULL OR @MaxUTCCaptureTime IS NULL
		BEGIN
			SET @codeloc = 'Populate Delta';
			--Call the delta logic sub-proc, because there COULD be capture times in the @StartTime/@EndTime range where
			-- CaptureSummaryPopulated=1 but CaptureSummaryDeltaPopulated=0;
			--NOTE that we pass in the same params we received, rather than the UTC times we calculated (which are only for CaptureSummaryPopulated=0)
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummaryDelta @CollectionInitiatorID=@CollectionInitiatorID, @StartTime=@StartTime, @EndTime=@EndTime;
			RETURN 0;
		END

		--Ok, now grab all captures between this UTC range
		SET @codeloc = '#CTTP population';
		INSERT INTO #CTTP (
			SPIDCaptureTime,
			UTCCaptureTime,
			RunWasSuccessful,
			CaptureSummaryPopulated,
			RowsActuallyFound
		)
		SELECT 
			ct.SPIDCaptureTime,
			ct.UTCCaptureTime,
			ct.RunWasSuccessful,		--Note that this could include unsuccessful runs. We'll mark those as "populated" at the end of the proc
										--but won't store any data for them in the summary table and won't calculate delta logic.
			[CaptureSummaryPopulated] = 0,
			[RowsActuallyFound] = N'N'	--will mark Y when we find rows for this capture time
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
		AND ct.UTCCaptureTime BETWEEN @MinUTCCaptureTime AND @MaxUTCCaptureTime
		AND ct.CaptureSummaryPopulated = 0;

		--Even though this proc isn't focused on delta logic (that's the subproc's job), if we're to do delta
		--logic for the earliest time in our range, we need the closest SUCCESSFUL time before that (if it exists!). 
		-- It must be within 2 minutes to be valid.
		DECLARE
				@MinusOne_UTCCaptureTime			DATETIME,
				@MinusOne_SPIDCaptureTime			DATETIME,
				@MinusOne_RunWasSuccessful			TINYINT,
				@MinusOne_CaptureSummaryPopulated	TINYINT

		SET @codeloc = 'Obtain Minus1';
		SELECT 
			@MinusOne_UTCCaptureTime = ss.UTCCaptureTime,
			@MinusOne_SPIDCaptureTime = ss.SPIDCaptureTime,
			@MinusOne_RunWasSuccessful = 1,
			@MinusOne_CaptureSummaryPopulated = ss.CaptureSummaryPopulated
		FROM (
			SELECT TOP 1
				ct.UTCCaptureTime,
				ct.SPIDCaptureTime,
				ct.CaptureSummaryPopulated
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			WHERE ct.UTCCaptureTime < @MinUTCCaptureTime
			AND DATEDIFF(MINUTE, ct.UTCCaptureTime, @MinUTCCaptureTime) <= 2
			AND ct.RunWasSuccessful = 1		--delta logic is only valid if the prev capture was successful
			ORDER BY ct.UTCCaptureTime DESC
		) ss;

		IF ISNULL(@MinusOne_CaptureSummaryPopulated,255) = 0	--do we have a previous cap? And does it still need to be populated?
		BEGIN
			--We insert a row into #CTTP to represent our minus one capture as being a part of the scope of this execution
			INSERT INTO #CTTP (
				SPIDCaptureTime,
				UTCCaptureTime,
				RunWasSuccessful,
				CaptureSummaryPopulated,
				RowsActuallyFound
			)
			SELECT 
				ct.SPIDCaptureTime,
				ct.UTCCaptureTime,
				ct.RunWasSuccessful,
				ct.CaptureSummaryPopulated,
				[RowsActuallyFound] = N'N'
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
			AND ct.UTCCaptureTime = @MinusOne_UTCCaptureTime
		END

		--The below logic is going to pull/aggregate data for all captures in our range AND for the @MinusOne capture time (if it exists)
		DECLARE @EffectiveSearchStartUTC DATETIME,
				@EffectiveSearchEndUTC	DATETIME;

		SELECT 
			@EffectiveSearchStartUTC = MIN(t.UTCCaptureTime),
			@EffectiveSearchEndUTC = MAX(t.UTCCaptureTime)
		FROM #CTTP t;


		SET @codeloc = 'BEGIN TRAN';
		BEGIN TRANSACTION

		SET @codeloc = 'CaptureSummary INSERT';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary (
			CollectionInitiatorID,	--1
			UTCCaptureTime,
			SPIDCaptureTime,
			CapturedSPIDs, 
			Active,					--5
			ActLongest_ms,
			ActAvg_ms,

			--We use histograms (instead of just MIN/MAX/AVG) for the various durations to give the user a better sense of the typical length of most SPIDs.
			-- This can be very helpful when trying to determine when/whether an OLTP-style app's user activity has "shifted to the right".
			Act0to1,
			Act1to5,
			Act10to30,				--10
			Act30to60,
			Act60to300,
			Act300plus,
			IdleWithOpenTran, 
			IdlOpTrnLongest_ms,		--15
			IdlOpTrnAvg_ms,
			IdlOpTrn0to1,
			IdlOpTrn1to5,
			IdlOpTrn5to10,
			IdlOpTrn10to30,			--20
			IdlOpTrn30to60,
			IdlOpTrn60to300,
			IdlOpTrn300plus,
			WithOpenTran,
			TranDurLongest_ms,		--25
			TranDurAvg_ms, 
			TranDur0to1,
			TranDur1to5,
			TranDur5to10,
			TranDur10to30,			--30
			TranDur30to60,
			TranDur60to300,
			TranDur300plus,
			Blocked,
			BlockedLongest_ms,		--35
			BlockedAvg_ms,
			Blocked0to1,
			Blocked1to5,
			Blocked5to10,
			Blocked10to30,			--40
			Blocked30to60,
			Blocked60to300,
			Blocked300plus,
			WaitingSPIDs, 
			WaitingTasks,			--45
			WaitingTaskLongest_ms,
			WaitingTaskAvg_ms,
			WaitingTask0to1, 
			WaitingTask1to5,
			WaitingTask5to10,		--50
			WaitingTask10to30,
			WaitingTask30to60,
			WaitingTask60to300,
			WaitingTask300plus,
			AllocatedTasks,			--55
			QueryMemoryRequested_KB,
			QueryMemoryGranted_KB,
			LargestMemoryGrant_KB,
			TempDB_pages,
			LargestTempDBConsumer_pages, --60
			CPUused, 
			LargestCPUConsumer,
			WritesDone,
			LargestWriter,
			LogicalReadsDone,		--65
			LargestLogicalReader,
			PhysicalReadsDone,
			LargestPhysicalReader,
			TlogUsed_bytes,
			LargestLogWriter_bytes, --70
			BlockingGraph,
			LockDetails,
			TranDetails				--73
		)
		SELECT 
			@CollectionInitiatorID,	--1
			ss3.UTCCaptureTime,
			ss3.SPIDCaptureTime,
			CapturedSPIDs,
			Active,					--5
			ActLongest_ms,
			ActAvg_ms,
			Act0to1,
			Act1to5,
			Act10to30,				--10
			Act30to60,
			Act60to300,
			Act300plus,
			IdleWithOpenTran,
			IdlOpTrnLongest_ms,		--15
			IdlOpTrnAvg_ms,
			IdlOpTrn0to1,
			IdlOpTrn1to5,
			IdlOpTrn5to10,
			IdlOpTrn10to30,			--20
			IdlOpTrn30to60,
			IdlOpTrn60to300,
			IdlOpTrn300plus,
			WithOpenTran,
			TranDurLongest_ms,		--25
			TranDurAvg_ms,
			TranDur0to1,
			TranDur1to5,
			TranDur5to10,
			TranDur10to30,			--30
			TranDur30to60,
			TranDur60to300,
			TranDur300plus,
			ISNULL(Blocked,0),
			BlockedLongest_ms,		--35
			BlockedAvg_ms,
			Blocked0to1,
			Blocked1to5,
			Blocked5to10,
			Blocked10to30,			--40
			Blocked30to60,
			Blocked60to300,
			Blocked300plus,
			ISNULL(WaitingSPIDs,0),
			WaitingTasks,			--45
			WaitingTaskLongest_ms,
			WaitingTaskAvg_ms,
			WaitingTask0to1,
			WaitingTask1to5,
			WaitingTask5to10,		--50
			WaitingTask10to30,
			WaitingTask30to60,
			WaitingTask60to300,
			WaitingTask300plus,
			AllocatedTasks,			--55
			QueryMemoryRequested_KB,
			QueryMemoryGranted_KB,
			LargestMemoryGrant_KB,
			TempDB_pages,
			LargestTempDBConsumer_pages,--60
			CPUused,
			LargestCPUConsumer,
			WritesDone,
			LargestWriter,
			LogicalReadsDone,		--65
			LargestLogicalReader,
			PhysicalReadsDone,
			LargestPhysicalReader,
			--can't use the one from our driving subquery, as this could be double-counted (same tran across sessions): TLogUsed_MB,
			-- Instead, use the one from our "td2" outer apply subquery:
			AggTLog_bytes = ISNULL(td2.Tlog_Agg,0),
			LargestLogWriter_bytes, --70		--this is ok to use from our driving subquery
			hasBG,
			hasLD,
			hasTD					--73
		FROM (
			SELECT 
				UTCCaptureTime,
				SPIDCaptureTime,
				CapturedSPIDs =			SUM(SPIDCounter),
				Active =				SUM(isActive),
				ActLongest_ms	 =		MAX(CASE WHEN isActive=1 AND sess__is_user_process = 1 THEN calc__duration_ms ELSE NULL END),
				ActAvg_ms		 =		AVG(CASE WHEN isActive=1 AND sess__is_user_process = 1 THEN calc__duration_ms ELSE NULL END),
				Act0to1			 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms BETWEEN 0 AND 1000 THEN 1 ELSE 0 END),
				Act1to5			 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms BETWEEN 1001 AND 5000 THEN 1 ELSE 0 END),
				Act5to10		 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms BETWEEN 5001 AND 10000 THEN 1 ELSE 0 END),
				Act10to30		 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms BETWEEN 10001 AND 30000 THEN 1 ELSE 0 END),
				Act30to60		 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms BETWEEN 30001 AND 60000 THEN 1 ELSE 0 END),
				Act60to300		 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms BETWEEN 60001 AND 300000 THEN 1 ELSE 0 END),
				Act300plus		 =		SUM(CASE WHEN isActive=1 AND sess__is_user_process = 1 AND calc__duration_ms > 300000 THEN 1 ELSE 0 END),

				IdleWithOpenTran =		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 THEN 1 ELSE 0 END),
				IdlOpTrnLongest_ms =	MAX(CASE WHEN isActive = 0 AND hasOpenTran = 1 THEN calc__duration_ms ELSE NULL END),
				IdlOpTrnAvg_ms	=		AVG(CASE WHEN isActive = 0 AND hasOpenTran = 1 THEN calc__duration_ms ELSE NULL END),
				IdlOpTrn0to1	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms BETWEEN 0 AND 1000 THEN 1 ELSE 0 END),
				IdlOpTrn1to5	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms BETWEEN 1001 AND 5000 THEN 1 ELSE 0 END),
				IdlOpTrn5to10	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms BETWEEN 5001 AND 10000 THEN 1 ELSE 0 END),
				IdlOpTrn10to30	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms BETWEEN 10001 AND 30000 THEN 1 ELSE 0 END),
				IdlOpTrn30to60	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms BETWEEN 30001 AND 60000 THEN 1 ELSE 0 END),
				IdlOpTrn60to300	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms BETWEEN 60001 AND 300000 THEN 1 ELSE 0 END),
				IdlOpTrn300plus	=		SUM(CASE WHEN isActive = 0 AND hasOpenTran = 1 AND calc__duration_ms > 300000 THEN 1 ELSE 0 END),

				WithOpenTran =			SUM(hasOpenTran),
				[TranDurLongest_ms] =	MAX(CASE WHEN hasOpenTran = 1 THEN TranLength_ms ELSE NULL END),
				TranDurAvg_ms		= 	AVG(CASE WHEN hasOpenTran = 1 THEN TranLength_ms ELSE NULL END),
				TranDur0to1			=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms BETWEEN 0 AND 1000 THEN 1 ELSE 0 END),
				TranDur1to5			=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms BETWEEN 1001 AND 5000 THEN 1 ELSE 0 END),
				TranDur5to10		=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms BETWEEN 5001 AND 10000 THEN 1 ELSE 0 END),
				TranDur10to30		=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms BETWEEN 10001 AND 30000 THEN 1 ELSE 0 END),
				TranDur30to60		=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms BETWEEN 30001 AND 60000 THEN 1 ELSE 0 END),
				TranDur60to300		=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms BETWEEN 60001 AND 300000 THEN 1 ELSE 0 END),
				TranDur300plus		=   SUM(CASE WHEN hasOpenTran = 1 AND TranLength_ms > 300000 THEN 1 ELSE 0 END),

				Blocked =				SUM(SPIDIsBlocked),
				BlockedLongest_ms =		MAX(LongestBlockedTask),
				BlockedAvg_ms		=	AVG(LongestBlockedTask),
				Blocked0to1			=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask BETWEEN 0 AND 1000 THEN 1 ELSE 0 END),
				Blocked1to5			=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask BETWEEN 1001 AND 5000 THEN 1 ELSE 0 END),
				Blocked5to10		=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask BETWEEN 5001 AND 10000 THEN 1 ELSE 0 END),
				Blocked10to30		=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask BETWEEN 10001 AND 30000 THEN 1 ELSE 0 END),
				Blocked30to60		=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask BETWEEN 30001 AND 60000 THEN 1 ELSE 0 END),
				Blocked60to300		=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask BETWEEN 60001 AND 300000 THEN 1 ELSE 0 END),
				Blocked300plus		=	SUM(CASE WHEN SPIDIsBlocked = 1 AND LongestBlockedTask > 300000 THEN 1 ELSE 0 END),

				WaitingSPIDs =			SUM(SPIDIsWaiting),
				WaitingTasks =			ISNULL(SUM(WaitingUserTasks),0),
				WaitingTaskLongest_ms = MAX(LongestWaitingUserTask),
				WaitingTaskAvg_ms	=	AVG(LongestWaitingUserTask),
				WaitingTask0to1		=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask BETWEEN 0 AND 1000 THEN 1 ELSE 0 END),
				WaitingTask1to5		=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask BETWEEN 1001 AND 5000 THEN 1 ELSE 0 END),
				WaitingTask5to10	=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask BETWEEN 5001 AND 10000 THEN 1 ELSE 0 END),
				WaitingTask10to30	=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask BETWEEN 10001 AND 30000 THEN 1 ELSE 0 END),
				WaitingTask30to60	=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask BETWEEN 30001 AND 60000 THEN 1 ELSE 0 END),
				WaitingTask60to300	=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask BETWEEN 60001 AND 300000 THEN 1 ELSE 0 END),
				WaitingTask300plus	=   SUM(CASE WHEN SPIDIsWaiting = 1 AND LongestWaitingUserTask > 300000 THEN 1 ELSE 0 END),

				AllocatedTasks =		ISNULL(SUM(AllocatedTasks),0),
				QueryMemoryRequested_KB =	SUM(CONVERT(BIGINT,ISNULL(QueryMemoryRequest,0))),
				QueryMemoryGranted_KB =		SUM(CONVERT(BIGINT,ISNULL(QueryMemoryGrant,0))),
				LargestMemoryGrant_KB = MAX(CONVERT(BIGINT,ISNULL(QueryMemoryGrant,0))),
				TempDB_pages =				SUM(CONVERT(BIGINT,ISNULL(TempDB_Use_pages,0))),
				LargestTempDBConsumer_pages = MAX(CONVERT(BIGINT,ISNULL(TempDB_Use_pages,0))),
				CPUused =				ISNULL(SUM(CPUused),0),
				LargestCPUConsumer =	MAX(CPUused),
				WritesDone =			ISNULL(SUM(WritesDone),0),
				LargestWriter =			MAX(WritesDone),
				LogicalReadsDone =		ISNULL(SUM(LogicalReadsDone),0),
				LargestLogicalReader =	MAX(LogicalReadsDone),
				PhysicalReadsDone =		ISNULL(SUM(PhysicalReadsDone),0),
				LargestPhysicalReader = SUM(PhysicalReadsDone),
				--can't use this, see note above: TLogUsed_MB =			SUM(TLogUsed)/1024/1024,
				LargestLogWriter_bytes =	CONVERT(BIGINT,MAX(TlogUsed)),
				hasBG =					MAX(hasBG),
				hasLD =					MAX(hasLD),
				hasTD =					MAX(hasTD)
			FROM (
				SELECT 
					UTCCaptureTime,
					SPIDCaptureTime,
					SPIDCounter = 1,
					calc__duration_ms,
					TranLength_ms,
					sess__is_user_process,
					isActive = CASE 
							WHEN request_id = @lv__nullsmallint 
							THEN 0 ELSE 1 END,
					AllocatedTasks = tempdb__CalculatedNumberOfTasks,
					hasOpenTran = CASE 
							WHEN sess__open_transaction_count > 0 OR rqst__open_transaction_count > 0
								OR hasTranDetailData = 1
							THEN 1 ELSE 0 END,
					SPIDIsBlocked,
					SPIDIsWaiting,
					WaitingUserTasks = NumWaitingTasks,
					LongestWaitingUserTask = CASE WHEN sess__is_user_process = 1 THEN LongestWaitingTask ELSE NULL END,
					LongestBlockedTask = LongestBlockedTask,
					QueryMemoryRequest = mgrant__requested_memory_kb,
					QueryMemoryGrant = mgrant__granted_memory_kb,
					TempDB_Use_pages = Tdb_Use_pages,
					CPUused = ss.rqst__cpu_time,
					WritesDone = ss.rqst__writes,
					LogicalReadsDone = ss.rqst__logical_reads,
					PhysicalReadsDone = ss.rqst__reads,
					TLogUsed = TranBytes, 
					hasBG, 
					hasLD,
					hasTD
				FROM (
					SELECT 
						sar.UTCCaptureTime,
						sar.SPIDCaptureTime,
						sar.session_id, 
						sar.request_id,
						sar.TimeIdentifier,		--rqst_start_time if active, last_request_end_time if not active
						sar.sess__is_user_process,
						sar.sess__open_transaction_count,
						sar.rqst__open_transaction_count,
						sar.rqst__cpu_time,
						sar.rqst__reads,
						sar.rqst__writes,
						sar.rqst__logical_reads, 

						Tdb_Use_pages = 
							CASE WHEN (ISNULL(sar.tempdb__sess_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_user_objects_dealloc_page_count,0)) < 0 THEN 0
								ELSE (ISNULL(sar.tempdb__sess_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_user_objects_dealloc_page_count,0))
								END + 
							CASE WHEN (ISNULL(sar.tempdb__sess_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_internal_objects_dealloc_page_count,0)) < 0 THEN 0
								ELSE (ISNULL(sar.tempdb__sess_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_internal_objects_dealloc_page_count,0))
								END + 
							CASE WHEN (ISNULL(sar.tempdb__task_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_user_objects_dealloc_page_count,0)) < 0 THEN 0
								ELSE (ISNULL(sar.tempdb__task_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_user_objects_dealloc_page_count,0))
								END + 
							CASE WHEN (ISNULL(sar.tempdb__task_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_internal_objects_dealloc_page_count,0)) < 0 THEN 0
								ELSE (ISNULL(sar.tempdb__task_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_internal_objects_dealloc_page_count,0))
								END,
						sar.tempdb__CalculatedNumberOfTasks,
						sar.mgrant__requested_memory_kb,
						sar.mgrant__granted_memory_kb,
						sar.calc__duration_ms,
						sar.calc__blocking_session_id,
						--sar.calc__is_blocker,
						hasTranDetailData = CASE WHEN td.UTCCaptureTime IS NOT NULL THEN 1 ELSE 0 END,
						td.TranBytes,
						td.TranLength_ms,
						taw.SPIDIsWaiting,
						taw.SPIDIsBlocked,
						taw.NumBlockedTasks,
						taw.NumWaitingTasks,
						taw.LongestWaitingTask,
						taw.LongestBlockedTask,
						hasLD = CASE WHEN ld.UTCCaptureTime IS NOT NULL THEN 1 ELSE 0 END,
						hasBG = CASE WHEN bg.UTCCaptureTime IS NOT NULL THEN 1 ELSE 0 END,
						hasTD = CASE WHEN td.UTCCaptureTime IS NOT NULL THEN 1 ELSE 0 END
					FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
						INNER JOIN #CTTP ct
							ON ct.UTCCaptureTime = sar.UTCCaptureTime
						LEFT OUTER JOIN (
							--THIS JOIN WAS COPIED OVER, WITH MINOR MODIFICATION, TO AutoWho.ApplyRetentionPolicies.
							-- IF THIS JOIN CHANGES, EVALUATE WHETHER THE CHANGES ARE RELEVANT FOR THAT PROC AS WELL.
							SELECT 
								td.UTCCaptureTime, 
								td.session_id,
								td.TimeIdentifier, 
									--since a spid could have transactions that span databases 
									-- (from the DMV's point of view, "multiple transactions"), we take the duration
									-- of the longest one.
								[TranLength_ms] = MAX(DATEDIFF(MILLISECOND, td.dtat_transaction_begin_time,td.SPIDCaptureTime)),
								[TranBytes] = SUM(ISNULL(td.dtdt_database_transaction_log_bytes_used,0) + 
											ISNULL(td.dtdt_database_transaction_log_bytes_used_system,0))
							FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails td
							WHERE td.CollectionInitiatorID = @CollectionInitiatorID
							AND td.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
							AND ISNULL(td.dtdt_database_id,99999) <> 32767

							--This doesn't seem to mean what I think it means:
							--AND td.dtst_is_user_transaction = 1

							/* not sure whether I actually do want the below criteria
							--dtat transaction_type
							--		1 = Read/write transaction
							--		2 = Read-only transaction
							--		3 = System transaction
							--		4 = Distributed transaction
							AND td.dtat_transaction_type NOT IN (2, 3)		--we don't want trans that are read-only or system trans
							--dtdt database_transaction_type
							--		1 = Read/write transaction
							--		2 = Read-only transaction
							--		3 = System transaction
							AND td.dtdt_database_transaction_type NOT IN (2,3) --we don't want DB trans that are read-only or system trans
							*/
							GROUP BY td.UTCCaptureTime, td.session_id, td.TimeIdentifier
						) td
							ON sar.UTCCaptureTime = td.UTCCaptureTime
							AND sar.session_id = td.session_id
							AND sar.TimeIdentifier = td.TimeIdentifier
						LEFT OUTER JOIN (
							SELECT 
								taw.UTCCaptureTime,
								taw.session_id,
								taw.request_id,
								[SPIDIsWaiting] = MAX(task_is_waiting),
								[SPIDIsBlocked] = MAX(task_is_blocked),
								[NumBlockedTasks] = SUM(task_is_blocked),
								[NumWaitingTasks] = SUM(task_is_waiting),
								[LongestWaitingTask] = MAX(taw.wait_duration_ms),
								[LongestBlockedTask] = MAX(taw.blocked_duration_ms)
							FROM (
								--we treat waits of type cxpacket as "not waiting"... i.e. a query with multiple tasks, and those
								-- tasks either running or cxp waiting, is not considered waiting, since the query is making progress
								SELECT 
									taw.UTCCaptureTime, 
									taw.session_id,
									taw.request_id,
									--note that in this context, "waiting" and "blocking" are completely non-overlapping concepts. The idea is that in the result set,
									-- the user will at a glance be able to see how much blocking is occurring, and how much "other waiting" is occurring.
									[task_is_waiting] = CASE WHEN taw.wait_special_category IN (@enum__waitspecial__none, @enum__waitspecial__cxp, 
																	@enum__waitspecial__lck, @enum__waitspecial__pgblocked, @enum__waitspecial__latchblocked) 
															THEN 0 ELSE 1 END,
									[task_is_blocked] = CASE WHEN taw.wait_special_category IN (@enum__waitspecial__lck, @enum__waitspecial__pgblocked, @enum__waitspecial__latchblocked) 
													THEN 1 ELSE 0 END,
									[wait_duration_ms] = CASE WHEN taw.wait_special_category IN (@enum__waitspecial__none, @enum__waitspecial__cxp,
																	@enum__waitspecial__lck, @enum__waitspecial__pgblocked, @enum__waitspecial__latchblocked) THEN NULL 
															ELSE ISNULL(taw.wait_duration_ms,0)
															END, 
									[blocked_duration_ms] = CASE WHEN taw.wait_special_category IN (@enum__waitspecial__lck, @enum__waitspecial__pgblocked, @enum__waitspecial__latchblocked)
													THEN ISNULL(taw.wait_duration_ms,0) ELSE NULL END
								FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
								WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
								AND taw.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
							) taw
							GROUP BY taw.UTCCaptureTime,
								taw.session_id,
								taw.request_id
						) taw
							ON sar.UTCCaptureTime = taw.UTCCaptureTime
							AND sar.session_id = taw.session_id
							AND sar.request_id = taw.request_id
						LEFT OUTER JOIN ( 
							SELECT DISTINCT UTCCaptureTime 
							FROM AutoWho.BlockingGraphs bg
							WHERE bg.CollectionInitiatorID = @CollectionInitiatorID
							AND bg.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
							) bg
							ON sar.UTCCaptureTime = bg.UTCCaptureTime
						LEFT OUTER JOIN (
							SELECT DISTINCT ld.UTCCaptureTime
							FROM @@CHIRHO_SCHEMA@@.AutoWho_LockDetails ld
							WHERE ld.CollectionInitiatorID = @CollectionInitiatorID
							AND ld.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
							) ld
							ON ld.UTCCaptureTime = sar.UTCCaptureTime
					WHERE sar.CollectionInitiatorID = @CollectionInitiatorID
					AND sar.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
					AND sar.session_id > 0
					AND ISNULL(sar.calc__threshold_ignore,0) = 0

					--occasionally we see spids that are dormant, and have non-sensical time values
					AND NOT (sar.sess__is_user_process = 1 AND sar.sess__last_request_end_time = '1900-01-01 00:00:00.000'
							AND sar.rqst__start_time IS NULL)
				) ss
			) ss2
			GROUP BY UTCCaptureTime, SPIDCaptureTime
		) ss3
			--Since a transaction can be enlisted for several different sessions at once, we have to join
			-- again to TranDetails to get our aggregate number for t-log used
			LEFT OUTER JOIN (
				SELECT UTCCaptureTime,
					[Tlog_Agg] = SUM(
						ISNULL(CONVERT(BIGINT,dtdt_database_transaction_log_bytes_used),0) + 
						ISNULL(CONVERT(BIGINT,dtdt_database_transaction_log_bytes_used_system),0)
						)
				FROM (
					SELECT DISTINCT td.UTCCaptureTime, 
						td.dtat_transaction_id, 
						dtdt_database_id,
						dtdt_database_transaction_log_bytes_used, 
						dtdt_database_transaction_log_bytes_used_system
					FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails td
					WHERE td.CollectionInitiatorID = @CollectionInitiatorID
					AND td.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
				) tsub
				GROUP BY UTCCaptureTime
			) td2
				ON ss3.UTCCaptureTime = td2.UTCCaptureTime;

		--The above logic includes a WHERE ...ISNULL(sar.calc__threshold_ignore,0) = 0 clause.
		-- This makes it not only possible, but probable that certain capture times will not have any rows
		-- placed into the CaptureSummary table. (i.e. when the system is quieter and the only things running
		-- are spids we largely ignore). Thus, we insert a dummy/placeholder row into those times.
		SET @codeloc = 'Update RowsActuallyFound';
		UPDATE targ 
		SET RowsActuallyFound = 'Y'
		FROM #CTTP targ 
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary cs
				ON targ.UTCCaptureTime = cs.UTCCaptureTime
		WHERE cs.CollectionInitiatorID = @CollectionInitiatorID
		AND cs.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC;

		--dummy row!
		SET @codeloc = 'Dummy Row';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary (
			CollectionInitiatorID, 
			UTCCaptureTime,
			SPIDCaptureTime, 
			CapturedSPIDs, 
			Active, --nullable: LongestActive_ms, Act0to1, Act1to5, Act5to10, Act10to30, Act30to60, Act60to300, Act300plus, 
			IdleWithOpenTran, --nullable: IdlOpTrnLongest_ms, IdlOpTrn0to1, IdlOpTrn1to5, IdlOpTrn5to10, IdlOpTrn10to30, IdlOpTrn30to60, IdlOpTrn60to300, IdlOpTrn300plus,
			WithOpenTran, --nullable: TranDurLongest_ms, TranDur0to1, TranDur1to5, TranDur5to10, TranDur10to30, TranDur30to60, TranDur60to300, TranDur300plus,
			Blocked, --nullable: BlockedLongest_ms, Blocked0to1, Blocked1to5, Blocked5to10, Blocked10to30, Blocked30to60, Blocked60to300, Blocked300plus, 
			WaitingSPIDs, WaitingTasks, 
				--nullable: WaitingTaskLongest_ms, WaitingTask0to1, WaitingTask1to5, WaitingTask5to10, WaitingTask10to30, WaitingTask30to60, WaitingTask60to300, WaitingTask300plus, 
			AllocatedTasks, QueryMemoryRequested_KB, QueryMemoryGranted_KB, LargestMemoryGrant_KB, TempDB_pages, LargestTempDBConsumer_pages, 
			CPUused, CPUDelta, LargestCPUConsumer, WritesDone, WritesDelta, LargestWriter, 
			LogicalReadsDone, LogicalReadsDelta, LargestLogicalReader, 
			PhysicalReadsDone, PhysicalReadsDelta, LargestPhysicalReader, 
			TlogUsed_bytes, LargestLogWriter_bytes, BlockingGraph, LockDetails, TranDetails
		)
		SELECT @CollectionInitiatorID,
			ss1.UTCCaptureTime,
			ss1.SPIDCaptureTime, 
			0 as CapturedSPIDs, 
			0 as Active, 
			0 as IdleWithOpenTran,
			0 as WithOpenTran,
			0 as Blocked,
			0 as WaitingSPIDs, 0 as WaitingTasks, 
			0 as AllocatedTasks, 0, 0, null, 0, null, 
			0 as CPUused, null, null, 0, null, null, 
			0 as LogicalReadsDone, null, null,
			0 as PhysicalReadsDone, null, null, 
			null as TlogUsed_bytes, null, 0, 0, 0
		FROM (SELECT t.UTCCaptureTime,
					t.SPIDCaptureTime
				FROM #CTTP t
				WHERE t.RowsActuallyFound = 'N') ss1;

		

		SET @codeloc = 'CaptureTimes UPDATE';
		UPDATE targ 
		SET targ.CaptureSummaryPopulated = 1
		FROM #CTTP t
			INNER loop JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ WITH (ROWLOCK)	--hints to avoid conflicting with the Collector
				ON targ.UTCCaptureTime = t.UTCCaptureTime
		WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
		AND targ.UTCCaptureTime BETWEEN @EffectiveSearchStartUTC AND @EffectiveSearchEndUTC
		AND targ.CaptureSummaryPopulated = 0
		--Note that even unsuccessful runs will be handled by this UPDATE. 
		;

		COMMIT TRANSACTION

		--NOTE that we pass in the same params we received, rather than the UTC times we calculated (which are only for CaptureSummaryPopulated=0)
		EXEC @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummaryDelta @CollectionInitiatorID=@CollectionInitiatorID, @StartTime=@StartTime, @EndTime=@EndTime;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		SET @errmsg = 'Unexpected exception encountered in ' + OBJECT_NAME(@@PROCID) + ' procedure, at location: ' + @codeloc;
		SET @errmsg = @errmsg + ' Error #: ' + CONVERT(varchar(20),ERROR_NUMBER()) + '; State: ' + CONVERT(varchar(20),ERROR_STATE()) + 
			'; Severity: ' + CONVERT(varchar(20),ERROR_SEVERITY()) + '; msg: ' + ERROR_MESSAGE();

		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='CATCH block', @Message=@errmsg;
		RETURN -1;
	END CATCH

	RETURN 0;
END
GO
