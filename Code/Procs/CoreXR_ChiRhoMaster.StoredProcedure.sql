SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE   @@CHIRHO_SCHEMA@@.CoreXR_ChiRhoMaster
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

	FILE NAME: CoreXR_ChiRhoMaster.StoredProcedure.sql

	PROCEDURE NAME: CoreXR_ChiRhoMaster

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs regularly throughout the day (by default, every 15 minutes), and checks whether the various
		traces (that drive data collection) should be running, and if they should but are not, starts them.
		Also runs the purge/retention procedures for AutoWho & ServerEye (and in the future, other components of
		the ChiRho suite) to keep data volumes manageable.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
DECLARE @lmsg VARCHAR(MAX)
EXEC @@CHIRHO_SCHEMA@@.CoreXR_ChiRhoMaster @ErrorMessage=@lmsg OUTPUT 
PRINT ISNULL(@lmsg, '<null>')
*/
(
	@AutoWhoJobName		NVARCHAR(255) = NULL,
	@ServerEyeJobName	NVARCHAR(255) = NULL,
	@PurgeDOW			NVARCHAR(21) = 'Sun',	-- to do every day of the week: 'SunMonTueWedThuFriSat'
	@PurgeHour			TINYINT	= 3,			-- 3am
	@PurgeDOWHourIsUTC	NCHAR(1) = N'N',		-- If purge should be run at a time when DST can interfere (i.e. 1 or 2 am local), specify the hour in UTC to avoid problems.
	@ErrorMessage		VARCHAR(MAX) = NULL OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;

	IF @AutoWhoJobName IS NULL
	BEGIN
		SET @AutoWhoJobName = DB_NAME() + N' - AlwaysDisabled - AutoWho Trace';
	END

	IF @ServerEyeJobName IS NULL
	BEGIN
		SET @ServerEyeJobName = DB_NAME() + N' - AlwaysDisabled - ServerEye Trace'
	END

	BEGIN TRY
		--General variables
		DECLARE @lv__masterErrorString		NVARCHAR(MAX),
				@lv__curError				NVARCHAR(MAX),
				@lv__ProcRC					INT,
				@lv__PostProcRawStartUTC	DATETIME,
				@lv__PostProcRawEndUTC		DATETIME,
				@lv__PostProcStartUTC		DATETIME,
				@lv__PostProcEndUTC			DATETIME,
				@lv__ShouldRunPurge			NCHAR(1) = N'N',
				@lv__CurTimeUTC				DATETIME,
				@lv__TodayDOW				NVARCHAR(10),
				@lv__TodayDOWInUTC			NVARCHAR(10),
				@lv__ThisHour				INT,
				@lv__ThisHourInUTC			INT;

		DECLARE 
				@AutoWho__IsEnabled		NCHAR(1), 
				@AutoWho__StartTimeUTC	DATETIME, 
				@AutoWho__EndTimeUTC	DATETIME,

				@ServerEye__IsEnabled	NCHAR(1), 
				@ServerEye__StartTimeUTC DATETIME,
				@ServerEye__EndTimeUTC	DATETIME;

		IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs where name = @AutoWhoJobName)
		BEGIN
			RAISERROR('Job specified in parameter @AutoWhoJobName not found.',16,1);
			RETURN -1;
		END

		IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs where name = @ServerEyeJobName)
		BEGIN
			RAISERROR('Job specified in parameter @ServerEyeJobName not found.',16,1);
			RETURN -3;
		END

		SET @PurgeDOW = LOWER(@PurgeDOW);

		IF @PurgeDOW IS NULL
			OR (@PurgeDOW NOT LIKE N'%sun%'
				AND @PurgeDOW NOT LIKE N'%mon%'
				AND @PurgeDOW NOT LIKE N'%tue%'
				AND @PurgeDOW NOT LIKE N'%wed%'
				AND @PurgeDOW NOT LIKE N'%thu%'
				AND @PurgeDOW NOT LIKE N'%fri%'
				AND @PurgeDOW NOT LIKE N'%sat%'
				AND @PurgeDOW NOT LIKE N'%never%'
			)
		BEGIN
			RAISERROR('Parameter @PurgeDOW must contain one or more 3-letter day-of-week tags (e.g. "Sun", "SunWed"), or contain the tag "Never".',16,1);
			RETURN -5;
		END

		IF @PurgeHour IS NULL OR @PurgeHour > 24
		BEGIN
			RAISERROR('Parameter @PurgeHour must be between 0 and 24 inclusive',16,1);
			RETURN -7;
		END

		SET @PurgeDOWHourIsUTC = ISNULL(@PurgeDOWHourIsUTC,N'N');

		IF @PurgeDOWHourIsUTC NOT IN (N'N', N'Y')
		BEGIN
			RAISERROR('Parameter @PurgeDOWHourIsUTC must be either Y or N.',16,1);
			RETURN -9;
		END

		SET @lv__TodayDOW = LOWER(SUBSTRING(LTRIM(RTRIM(DATENAME(dw,GETDATE()))),1,3));
		SET @lv__TodayDOWInUTC = LOWER(SUBSTRING(LTRIM(RTRIM(DATENAME(dw,GETUTCDATE()))),1,3));
		SET @lv__ThisHour = DATEPART(HOUR, GETDATE());
		SET @lv__ThisHourInUTC = DATEPART(HOUR, GETUTCDATE());

		--Update our DBID mapping table
		EXEC @@CHIRHO_SCHEMA@@.CoreXR_UpdateDBMapping;

		IF OBJECT_ID('tempdb..#CurrentlyRunningJobs1') IS NOT NULL
			BEGIN
				DROP TABLE #CurrentlyRunningJobs1;
			END 
			CREATE TABLE #CurrentlyRunningJobs1( 
				Job_ID uniqueidentifier,
				Last_Run_Date int,
				Last_Run_Time int,
				Next_Run_Date int,
				Next_Run_Time int,
				Next_Run_Schedule_ID int,
				Requested_To_Run int,
				Request_Source int,
				Request_Source_ID varchar(100),
				Running int,
				Current_Step int,
				Current_Retry_Attempt int, 
				aState int
			);

		INSERT INTO #CurrentlyRunningJobs1 
			EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, 'hullabaloo'; --undocumented
			--cannot use this because we cannot nest an INSERT EXEC: exec msdb.dbo.sp_help_job @execution_status=1

		SET @lv__CurTimeUTC = GETUTCDATE();

		/*
			In this proc, we do these things

			1. Check whether the AutoWho and ServerEye jobs are running, and start, if appropriate.

			2. After we begin (or not) each job, we run supporting procs for each:
				a. @@CHIRHO_SCHEMA@@.AutoWho_UpdateStoreLastTouched
				b. TODO: ServerEye_UpdateStoreLastTouche	<-- this proc does not exist yet, but likely will at some point
				c. @@CHIRHO_SCHEMA@@.AutoWho_PostProcessor
				d. AutoWho Purge
				e. AutoWho index maintenance
				f. ServerEye Purge
				g. ServerEye index maintenance

		*/

		/*************************************** AutoWho Job stuff ***************************/
		--This proc gives us the next time range when the AutoWho trace should be running. If @lv__CurTimeUTC is within a time range when AutoWho
		--should be running, we will get the start/end of the time range that AutoWho should be running for right now.
		EXEC @lv__ProcRC = @@CHIRHO_SCHEMA@@.CoreXR_TraceTimeInfo @Utility=N'AutoWho', 
			@PointInTimeUTC = @lv__CurTimeUTC, @UtilityIsEnabled = @AutoWho__IsEnabled OUTPUT,
			@UtilityStartTimeUTC = @AutoWho__StartTimeUTC OUTPUT, @UtilityEndTimeUTC = @AutoWho__EndTimeUTC OUTPUT;

		IF @lv__CurTimeUTC BETWEEN @AutoWho__StartTimeUTC AND @AutoWho__EndTimeUTC 
			AND @AutoWho__IsEnabled = N'Y'
		BEGIN
			--the trace SHOULD be running. check to see if it is already.
			--if not, then start it.

			IF NOT EXISTS (SELECT * 
					FROM #CurrentlyRunningJobs1 t
						INNER JOIN msdb.dbo.sysjobs j 
							ON t.Job_ID = j.job_id
				WHERE j.name = @AutoWhoJobName
				AND t.Running = 1)
			BEGIN
				IF NOT EXISTS (SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_SignalTable t WITH (NOLOCK) 
								WHERE LOWER(SignalName) = N'aborttrace' 
								AND LOWER(t.SignalValue) = N'allday'
								AND DATEDIFF(DAY, InsertTime, GETDATE()) = 0)	--we use local instead of UTC because the DST 1am-2am issue does not affect this logic 
																				--and everything thinks in local time anyway (so there is no value in aborting for the full UTC day)
				--any abort requests will, by default, continue their effect the rest of the day.
				BEGIN
					EXEC msdb.dbo.sp_start_job @job_name = @AutoWhoJobName;
					EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode = 0, @TraceID = NULL, @Location = N'XRMaster AutoWho Job Start', @Message = N'AutoWho Trace job started.';
				END
				ELSE
				BEGIN
					EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode = -1, @TraceID = NULL, @Location = N'XRMaster AutoWho Signal', @Message = N'An AbortTrace signal exists for today. This procedure has been told not to run the rest of the day.';
				END
			END	 
		END		--IF @lv__CurTimeUTC BETWEEN @AutoWho__StartTimeUTC AND @AutoWho__EndTimeUTC 
				-- that is, "IF trace should be running"
		/*************************************** AutoWho Job stuff ***************************/


		/*************************************** ServerEye Job stuff ***************************/
		--This proc gives us the next time range when the ServerEye trace should be running. If @lv__CurTimeUTC is within a time range when ServerEye
		--should be running, we will get the start/end of the time range that ServerEye should be running for right now.
		EXEC @lv__ProcRC = @@CHIRHO_SCHEMA@@.CoreXR_TraceTimeInfo @Utility=N'ServerEye', 
			@PointInTimeUTC = @lv__CurTimeUTC, @UtilityIsEnabled = @ServerEye__IsEnabled OUTPUT,
			@UtilityStartTimeUTC = @ServerEye__StartTimeUTC OUTPUT, @UtilityEndTimeUTC = @ServerEye__EndTimeUTC OUTPUT;

		IF @lv__CurTimeUTC BETWEEN @ServerEye__StartTimeUTC AND @ServerEye__EndTimeUTC 
			AND @ServerEye__IsEnabled = N'Y'
		BEGIN
			--the trace SHOULD be running. check to see if it is already.
			--if not, then start it.

			IF NOT EXISTS (SELECT * 
					FROM #CurrentlyRunningJobs1 t
						INNER JOIN msdb.dbo.sysjobs j 
							ON t.Job_ID = j.job_id
				WHERE j.name = @ServerEyeJobName
				AND t.Running = 1)
			BEGIN
				IF NOT EXISTS (SELECT * FROM @@CHIRHO_SCHEMA@@.ServerEye_SignalTable t WITH (NOLOCK) 
								WHERE LOWER(SignalName) = N'aborttrace' 
								AND LOWER(t.SignalValue) = N'allday'
								AND DATEDIFF(DAY, InsertTime, GETDATE()) = 0)	--we use local instead of UTC because the DST 1am-2am issue does not affect this logic 
																				--and everything thinks in local time anyway (so there is no value in aborting for the full UTC day)
				--any abort requests will, by default, continue their effect the rest of the day.
				BEGIN
					EXEC msdb.dbo.sp_start_job @job_name = @ServerEyeJobName;
					EXEC @@CHIRHO_SCHEMA@@.ServerEye_LogEvent @ProcID=@@PROCID, @EventCode = 0, @TraceID = NULL, @Location = N'XRMaster ServerEye Job Start', @Message = N'ServerEye Trace job started.';
				END
				ELSE
				BEGIN
					EXEC @@CHIRHO_SCHEMA@@.ServerEye_LogEvent @ProcID=@@PROCID, @EventCode = -1, @TraceID = NULL, @Location = N'XRMaster ServerEye Signal', @Message = N'An AbortTrace signal exists for today. This procedure has been told not to run the rest of the day.';
				END
			END	 
		END		--IF @lv__CurTimeUTC BETWEEN @ServerEye__StartTimeUTC AND @ServerEye__EndTimeUTC 
				-- that is, "IF trace should be running"
		/*************************************** ServerEye Job stuff ***************************/
		

		BEGIN TRY
			SET @lv__ProcRC = 0;
			EXEC @lv__ProcRC = @@CHIRHO_SCHEMA@@.AutoWho_UpdateStoreLastTouched;
		END TRY
		BEGIN CATCH
			--inside the loop, we swallow the error and just log it
			SET @ErrorMessage = N'Exception occurred when updating the store LastTouched values: ' + ERROR_MESSAGE();
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode = -999, @TraceID = NULL, @Location = N'ErrorLastTouch', @Message = @ErrorMessage;
		END CATCH

		BEGIN TRY
			/*
				We need to pass in valid @@CHIRHO_SCHEMA@@.AutoWho_CaptureTime.UTCCaptureTime values into the post-processor. We go back 45 minutes,
				though the various sub-procs inside the PostProcessor keep track of what they have already processed in that range.
			*/
			SET @lv__PostProcRawEndUTC = DATEADD(SECOND, -30, GETUTCDATE());		--we steer clear of the tail of the table where data is being inserted regularly.
			SET @lv__PostProcRawStartUTC = DATEADD(MINUTE, -45, @lv__PostProcRawEndUTC);

			SELECT 
				@lv__PostProcStartUTC = MIN(ct.UTCCaptureTime),
				@lv__PostProcEndUTC = MAX(ct.UTCCaptureTime)
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			WHERE ct.CollectionInitiatorID = 255
			AND ct.UTCCaptureTime >= @lv__PostProcRawStartUTC
			AND ct.UTCCaptureTime <= @lv__PostProcRawEndUTC;

			IF @lv__PostProcStartUTC IS NOT NULL	--Only post-process if we have background captures in the last 45 minutes
			BEGIN
				SET @lv__ProcRC = 0;
				EXEC @lv__ProcRC = @@CHIRHO_SCHEMA@@.AutoWho_PostProcessor @optionset=N'BackgroundTrace', @init=255, @startUTC=@lv__PostProcStartUTC, @endUTC=@lv__PostProcEndUTC;
			END
		END TRY
		BEGIN CATCH
			--inside the loop, we swallow the error and just log it
			SET @ErrorMessage = N'Exception occurred when post-processing AutoWho captures: ' + ERROR_MESSAGE();
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode = -999, @TraceID = NULL, @Location = N'ErrorPostProcess', @Message = @ErrorMessage;
		END CATCH

		/*************************************** AutoWho Purge ***************************/
		--Evaluate whether we should run AutoWho purge
		IF @PurgeDOWHourIsUTC = N'N'
			AND @PurgeDOW LIKE '%' + @lv__TodayDOW + '%'
			AND (
				@lv__ThisHour = @PurgeHour
					OR (@lv__ThisHour = 0 AND @PurgeHour = 24)
				)
			--AND the log doesn't show any purge as having run in the last 75 minutes (use UTC time to avoid weirdness on DST-change days)
			AND NOT EXISTS (
				SELECT *
				FROM @@CHIRHO_SCHEMA@@.AutoWho_Log l
				WHERE l.LocationTag = 'XRMaster AutoWho Purge'
				AND l.LogMessage = 'Purge procedure completed'
				AND l.LogDTUTC > DATEADD(MINUTE, -75, GETUTCDATE())
			)
		BEGIN
			SET @lv__ShouldRunPurge = N'Y';
		END
		ELSE IF @PurgeDOWHourIsUTC = N'Y'
			AND @PurgeDOW LIKE '%' + @lv__TodayDOWInUTC + '%'
			AND (
				@lv__ThisHourInUTC = @PurgeHour
					OR (@lv__ThisHourInUTC = 0 AND @PurgeHour = 24)
				)
			--AND the log doesn't show any purge as having run in the last 75 minutes (use UTC time to avoid weirdness on DST-change days)
			AND NOT EXISTS (
				SELECT *
				FROM @@CHIRHO_SCHEMA@@.AutoWho_Log l
				WHERE l.LocationTag = 'XRMaster AutoWho Purge'
				AND l.LogMessage = 'Purge procedure completed'
				AND l.LogDTUTC > DATEADD(MINUTE, -75, GETUTCDATE())
			)
		BEGIN
			SET @lv__ShouldRunPurge = N'Y';
		END

		IF @lv__ShouldRunPurge = N'Y'
		BEGIN
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_ApplyRetentionPolicies;

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode = 0, @TraceID = NULL, @Location = N'XRMaster AutoWho Purge', @Message = N'Purge procedure completed';

			--Now that we have (potentially) deleted a bunch of rows, do some index maint
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_MaintainIndexes;
		END
		/*************************************** AutoWho Purge ***************************/



		/*************************************** ServerEye Purge ***************************/
		--Evaluate whether we should run ServerEye purge
		SET @lv__ShouldRunPurge = N'N';
		IF @PurgeDOWHourIsUTC = N'N'
			AND @PurgeDOW LIKE '%' + @lv__TodayDOW + '%'
			AND (
				@lv__ThisHour = @PurgeHour
					OR (@lv__ThisHour = 0 AND @PurgeHour = 24)
				)
			--AND the log doesn't show any purge as having run in the last 75 minutes (use UTC time to avoid weirdness on DST-change days)
			AND NOT EXISTS (
				SELECT *
				FROM @@CHIRHO_SCHEMA@@.ServerEye_Log l
				WHERE l.LocationTag = 'XRMaster ServerEye Purge'
				AND l.LogMessage = 'Purge procedure completed'
				AND l.LogDTUTC > DATEADD(MINUTE, -75, GETUTCDATE())
			)
		BEGIN
			SET @lv__ShouldRunPurge = N'Y';
		END
		ELSE IF @PurgeDOWHourIsUTC = N'Y'
			AND @PurgeDOW LIKE '%' + @lv__TodayDOWInUTC + '%'
			AND (
				@lv__ThisHourInUTC = @PurgeHour
					OR (@lv__ThisHourInUTC = 0 AND @PurgeHour = 24)
				)
			--AND the log doesn't show any purge as having run in the last 75 minutes (use UTC time to avoid weirdness on DST-change days)
			AND NOT EXISTS (
				SELECT *
				FROM @@CHIRHO_SCHEMA@@.ServerEye_Log l
				WHERE l.LocationTag = 'XRMaster ServerEye Purge'
				AND l.LogMessage = 'Purge procedure completed'
				AND l.LogDTUTC > DATEADD(MINUTE, -75, GETUTCDATE())
			)
		BEGIN
			SET @lv__ShouldRunPurge = N'Y';
		END

		IF @lv__ShouldRunPurge = N'Y'
		BEGIN
			EXEC @@CHIRHO_SCHEMA@@.ServerEye_ApplyRetentionPolicies;

			EXEC @@CHIRHO_SCHEMA@@.ServerEye_LogEvent @ProcID=@@PROCID, @EventCode = 0, @TraceID = NULL, @Location = N'XRMaster ServerEye Purge', @Message = N'Purge procedure completed';

			--Now that we have (potentially) deleted a bunch of rows, do some index maint
			EXEC @@CHIRHO_SCHEMA@@.ServerEye_MaintainIndexes;
		END
		/*************************************** ServerEye Purge ***************************/

		RETURN 0;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;

		SET @ErrorMessage = N'Unexpected exception occurred: Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
			N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + 
			N'; Severity: ' + CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + 
			N'; Message: ' + ISNULL(ERROR_MESSAGE(),N'<null>');

		RAISERROR(@ErrorMessage, 16, 1);
		RETURN -999;
	END CATCH
END;
GO
