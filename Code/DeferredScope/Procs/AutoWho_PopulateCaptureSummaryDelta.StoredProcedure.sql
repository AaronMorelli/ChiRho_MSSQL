SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummaryDelta
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

	FILE NAME: AutoWho_PopulateCaptureSummaryDelta.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_PopulateCaptureSummaryDelta

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: This proc should normally only be called by @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummary, because it expects the 
		@@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary table to be populated for all capture times between the @StartTime/@EndTime range.
		(And actually, it expects the Min-minus-1 capture time to be populated as well so that the delta stats will
		work correctly).

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummaryDelta @CollectionInitiatorID=255, @StartTime='2016-04-25 08:00', @EndTime='2016-04-25 09:00'
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

	DECLARE
		@codeloc							VARCHAR(20),
		@errmsg								VARCHAR(MAX),
		@scratch_int						INT,
		@MinUTCCaptureTime					DATETIME,
		@MaxUTCCaptureTime					DATETIME,				
		@MinUTCCaptureTime_PreviousCapture	DATETIME;

	BEGIN TRY
		/*
			First, pull the capture times. Since we expect the user to enter local times, we take care of translating to UTC. Note that if 
			the user specifies a time between 1am and 2am on the "fall-back" day for DST, then a single @StartTime/@EndTime range 
			will result in *TWO* UTC ranges. We keep things a bit simpler by just pulling the data for all of the UTC values that
			match this local time range.
		*/
		SET @codeloc = 'Delta Min/Max';
		SELECT 
			@MinUTCCaptureTime = MIN(ct.UTCCaptureTime),
			@MaxUTCCaptureTime = MAX(ct.UTCCaptureTime)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
		AND ct.SPIDCaptureTime BETWEEN @StartTime AND @EndTime;
		--Note that we CANNOT filter on ct.CaptureSummaryDeltaPopulated = 0
		--Because the delta logic by its nature must have a complete list 
		--of times, unprocessed or not, in order to determine the correct "previous time"
		--to do the delta calculation appropriately.

		IF @MinUTCCaptureTime IS NULL OR @MaxUTCCaptureTime IS NULL
		BEGIN
			--We don't expect this, but...no work to do! We return a 1 so the caller knows that there
			--are no captures in this range
			RETURN 1;
		END

		IF OBJECT_ID('#TimesToDelta') IS NOT NULL DROP TABLE #TimesToDelta;
		CREATE TABLE #TimesToDelta (
			SPIDCaptureTime				DATETIME NOT NULL,
			UTCCaptureTime				DATETIME NOT NULL,
			RunWasSuccessful			TINYINT NOT NULL,
			CaptureSummaryPopulated		TINYINT NOT NULL,
			CaptureSummaryDeltaPopulated TINYINT NOT NULL,
			PrevUTCCaptureTime			DATETIME NULL,	--a capture may not have a valid prev for various reasons. See below.
			CPUDelta					BIGINT NULL,
			WritesDelta					BIGINT NULL,
			LogicalReadsDelta			BIGINT NULL,
			PhysicalReadsDelta			BIGINT NULL
		);

		CREATE UNIQUE CLUSTERED INDEX CL1 ON #TimesToDelta (UTCCaptureTime);

		SET @codeloc = '#TimesToDelta population';
		INSERT INTO #TimesToDelta (
			SPIDCaptureTime,
			UTCCaptureTime,
			RunWasSuccessful,
			CaptureSummaryPopulated,
			CaptureSummaryDeltaPopulated
		)
		SELECT 
			ct.SPIDCaptureTime,
			ct.UTCCaptureTime,
			ct.RunWasSuccessful,
			ct.CaptureSummaryPopulated,
			ct.CaptureSummaryDeltaPopulated
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
		AND ct.UTCCaptureTime BETWEEN @MinUTCCaptureTime AND @MaxUTCCaptureTime;

		/* 
			In order to calc the delta for @MinUTCCaptureTime, we need its previous time (if one exists)
			A valid "previous capture" is
				1) a successful capture
				2) no earlier than 2 minutes before @MinUTCCaptureTime

			Insert into our table if this exists. And since the previous capture may not be immediately before
			(because of intervening unsuccessful runs), we get those also so that we can mark them as being processed
		*/
		SET @codeloc = 'Min Previous logic';
		SELECT 
			@MinUTCCaptureTime_PreviousCapture = ss.UTCCaptureTime
		FROM (
			SELECT TOP 1
				ct.UTCCaptureTime
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			WHERE ct.UTCCaptureTime < @MinUTCCaptureTime
			AND ct.RunWasSuccessful = 1
			AND DATEDIFF(MINUTE, ct.UTCCaptureTime, @MinUTCCaptureTime) <= 2
			ORDER BY ct.UTCCaptureTime DESC
		) ss;

		--If we found a previous, insert it and any intervening unsuccessful runs
		IF @MinUTCCaptureTime_PreviousCapture IS NOT NULL
		BEGIN
			INSERT INTO #TimesToDelta (
				SPIDCaptureTime,
				UTCCaptureTime,
				RunWasSuccessful,
				CaptureSummaryPopulated,
				CaptureSummaryDeltaPopulated
			)
			SELECT 
				ct.SPIDCaptureTime,
				ct.UTCCaptureTime,
				ct.RunWasSuccessful,
				ct.CaptureSummaryPopulated,
				ct.CaptureSummaryDeltaPopulated
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
			AND ct.UTCCaptureTime >= @MinUTCCaptureTime_PreviousCapture 
			AND ct.UTCCaptureTime < @MinUTCCaptureTime;
		END

		/*
			Now, update the PrevUTCCaptureTime field so we know which capture times to connect 
			for calculating the delta metrics. As we mentioned above, a previous run must be 
			successful and within 2 minutes of the current run.
		*/
		SET @codeloc = 'All Previous logic';
		UPDATE targ 
		SET PrevUTCCaptureTime = prev.PrevUTCCaptureTime
		FROM #TimesToDelta targ
			OUTER APPLY (
				SELECT TOP 1 
					[PrevUTCCaptureTime] = t2.UTCCaptureTime
				FROM #TimesToDelta t2
				WHERE t2.UTCCaptureTime < targ.UTCCaptureTime
				AND DATEDIFF(MINUTE, t2.UTCCaptureTime, targ.UTCCaptureTime) <= 2
				AND t2.RunWasSuccessful = 1
				ORDER BY t2.UTCCaptureTime DESC
			) prev
		WHERE targ.RunWasSuccessful = 1;	--We only calc delta logic for rows that were successful

		/*
			Before doing the delta calculation, we do a bit more validation.
				1) Every successful run in #TimesToDelta must already have a capture time present in @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary
					If not, then something went wrong in [AutoWho].[PopulateCaptureSummary] or thereabouts

				2) Every PrevUTCCaptureTime must exist in @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary. If not...ditto
		*/
		SET @codeloc = 'Delta Validation';
		IF EXISTS (
			SELECT *
			FROM (
				SELECT [CaptureTime] = UTCCaptureTime
				FROM #TimesToDelta t
				WHERE t.RunWasSuccessful = 1

				UNION	--remove dups

				SELECT [CaptureTime] = PrevUTCCaptureTime
				FROM #TimesToDelta t2
				WHERE t2.PrevUTCCaptureTime IS NOT NULL
			) ss
			WHERE NOT EXISTS (
				SELECT * 
				FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary cs
				WHERE cs.UTCCaptureTime = ss.CaptureTime
				AND cs.CollectionInitiatorID = @CollectionInitiatorID
				)
		)
		BEGIN
			RAISERROR('Attempt to process delta logic for capture times not found in the Capture Summary.', 16, 1);
			RETURN -1;
		END


		--If we get this far, we should be good to do our final logic. Let's begin a tran:
		SET @codeloc = 'Begin Tran';
		BEGIN TRANSACTION;

		SET @codeloc = 'Calc deltas';

		UPDATE targ
		SET CPUDelta = CASE WHEN (targ.RunWasSuccessful = 0 OR targ.PrevUTCCaptureTime IS NULL) THEN -1
							WHEN csCur.CPUused IS NULL OR csPrev.CPUused IS NULL THEN NULL
							ELSE csCur.CPUused - csPrev.CPUused END,
			WritesDelta = CASE WHEN (targ.RunWasSuccessful = 0 OR targ.PrevUTCCaptureTime IS NULL) THEN -1
							WHEN csCur.WritesDone IS NULL OR csPrev.WritesDone IS NULL THEN NULL 
							ELSE csCur.WritesDone - csPrev.WritesDone END,
			LogicalReadsDelta = CASE WHEN (targ.RunWasSuccessful = 0 OR targ.PrevUTCCaptureTime IS NULL) THEN -1
							WHEN csCur.LogicalReadsDone IS NULL OR csPrev.LogicalReadsDone IS NULL THEN NULL 
							ELSE csCur.LogicalReadsDone - csPrev.LogicalReadsDone END,
			PhysicalReadsDelta = CASE WHEN (targ.RunWasSuccessful = 0 OR targ.PrevUTCCaptureTime IS NULL) THEN -1
							WHEN csCur.PhysicalReadsDone IS NULL OR csPrev.PhysicalReadsDone IS NULL THEN NULL 
							ELSE csCur.PhysicalReadsDone - csPrev.PhysicalReadsDone END
		FROM #TimesToDelta targ
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary csCur
				ON targ.UTCCaptureTime = csCur.UTCCaptureTime
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary csPrev
				ON targ.PrevUTCCaptureTime = csPrev.UTCCaptureTime
		WHERE csCur.CollectionInitiatorID = @CollectionInitiatorID
		AND csPrev.CollectionInitiatorID = @CollectionInitiatorID;

		--Apply our results to the CS table
		SET @codeloc = 'Apply Deltas';
		UPDATE cs
		SET CPUDelta = t.CPUDelta,
			WritesDelta = t.WritesDelta,
			LogicalReadsDelta = t.LogicalReadsDelta,
			PhysicalReadsDelta = t.PhysicalReadsDelta
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary cs
			INNER JOIN #TimesToDelta t
				ON cs.UTCCaptureTime = t.UTCCaptureTime
		WHERE cs.CollectionInitiatorID = @CollectionInitiatorID;
		--TODO: Could we safely add AND t.CaptureSummaryDeltaPopulated = 0 here
		--so that we aren't updating records we've updated before?

		UPDATE ct
		SET CaptureSummaryDeltaPopulated = 1
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			INNER JOIN #TimesToDelta t
				ON ct.UTCCaptureTime = t.UTCCaptureTime;

		COMMIT TRANSACTION;
		RETURN 0;
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