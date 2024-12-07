SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE   [ServerEye].[Executor]
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

	FILE NAME: ServerEye.Executor.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.Executor

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Sits in a loop for the duration of an ServerEye trace, calling the collector every X minutes. (By default, 1). 
		This proc is called directly by the SQL Agent job "<ChiRho DB name> - Disabled - ServerEye Trace". 

		See the "Control Flow Summary" comment below for more details.

To stop the trace before its end-time: 
	exec @@CHIRHO_SCHEMA@@.CoreXR_AbortTrace @Utility=N'ServerEye',@TraceID = NULL | <number>, @PreventAllDay = N'N' | N'Y'		--null trace ID means the most recent one


DECLARE @ProcRC INT
DECLARE @lmsg VARCHAR(4000)

EXEC @ProcRC = ServerEye.Executor @ErrorMessage = @lmsg OUTPUT

PRINT 'Return Code: ' + CONVERT(VARCHAR(20),@ProcRC)
PRINT 'Return Message: ' + COALESCE(@lmsg,'<NULL>')
*/
(
@ErrorMessage	NVARCHAR(4000) OUTPUT
)
AS
BEGIN

/* Control Flow Summary
	Here's the work done by this proc:

		1. Obtain applock named "ServerEyeBackgroundTrace"

		TODO: fill this in once I have a fairly robust version.

*** after the loop ends:
		15. Delete any one-time abort signals in the signal table and calculate the right text to return in @ErrorMessage

		16. stop the CoreXR trace via CoreXR.StopTrace

		18. Release the "ServerEyeBackgroundTrace" app lock
*/


SET NOCOUNT ON; 
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET ANSI_PADDING ON;	--Aaron M	2015-05-30	If the calling session has set this setting OFF, the XML method 
						--of parsing the @Inclusion/Exclusion parameters will not work

--Master TRY/CATCH block
BEGIN TRY
	DECLARE @lv__SQLVersion NVARCHAR(10);
	SELECT @lv__SQLVersion = (
	SELECT CASE
			WHEN t.col1 LIKE N'8%' THEN N'2000'
			WHEN t.col1 LIKE N'9%' THEN N'2005'
			WHEN t.col1 LIKE N'10.5%' THEN N'2008R2'
			WHEN t.col1 LIKE N'10%' THEN N'2008'
			WHEN t.col1 LIKE N'11%' THEN N'2012'
			WHEN t.col1 LIKE N'12%' THEN N'2014'
			WHEN t.col1 LIKE N'13%' THEN N'2016'
		END AS val1
	FROM (SELECT CONVERT(SYSNAME, SERVERPROPERTY(N'ProductVersion')) AS col1) AS t);

	IF @lv__SQLVersion IN (N'2000',N'2005')
	BEGIN
		SET @ErrorMessage = N'ServerEye is only compatible with SQL 2008 and above.';
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-1, @TraceID=NULL, @Location='SQLVersion', @Message=@ErrorMessage; 
		RETURN -1;
	END

	--General variables 
	DECLARE 
		@lv__ThisRC					INT, 
		@lv__ProcRC					INT, 
		@lv__tmpStr					NVARCHAR(4000),
		@lv__ScratchInt				INT,
		@lv__EarlyAbort				NCHAR(1),
		@lv__RunTimeSeconds			BIGINT,
		@lv__RunTimeMinutes			INT,
		@lv__LoopStartTimeUTC		DATETIME,
		@lv__SQLServerStartTime		DATETIME,
		@lv__ServerEyeCallCompleteTimeUTC	DATETIME,
		@lv__LoopEndTimeUTC			DATETIME,
		@lv__LoopNextStartUTC		DATETIME,
		@lv__LoopNextStartSecondDifferential INT,
		@lv__WaitForMinutes			INT,
		@lv__WaitForSeconds			INT,
		@lv__WaitForString			VARCHAR(20),
		@lv__LoopCounter			INT,
		@lv__ExceptionThisRun		INT,
		@lv__SuccessiveExceptions	INT,
		@lv__TraceID				INT,
		@lv__DBInclusionsExist		BIT,
		@lv__TempDBCreateTime		DATETIME,
		@lv__LocalCaptureTime		DATETIME,
		@lv__UTCCaptureTime			DATETIME,
		
		@lv__MediumInterval			INT,
		@lv__LowInterval			INT,
		@lv__BatchInterval			INT,
		@lv__MediumFreqThisRun		BIT,
		@lv__LowFreqThisRun			BIT,
		@lv__BatchFreqThisRun			BIT,
		@lv__HighFrequencySuccessful	SMALLINT,
		@lv__MediumFrequencySuccessful	SMALLINT,
		@lv__LowFrequencySuccessful		SMALLINT,
		@lv__BatchFrequencySuccessful	SMALLINT,
		@lv__RunWasSuccessful		BIT;


	--variables to hold option table contents
	DECLARE 
		@opt__IntervalLength					INT,	
		@opt__IncludeDBs						NVARCHAR(500),	
		@opt__ExcludeDBs						NVARCHAR(500),	

		@opt__DebugSpeed						NCHAR(1)
		;

	EXEC @lv__ProcRC = sp_getapplock @Resource='ServerEyeBackgroundTrace',
					@LockOwner='Session',
					@LockMode='Exclusive',
					@LockTimeout=5000;

	IF @lv__ProcRC < 0
	BEGIN
		SET @ErrorMessage = N'Unable to obtain exclusive ServerEye Tracing lock.';
		SET @lv__ThisRC = -3;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='Obtaining applock', @Message=@ErrorMessage;
		RETURN @lv__ThisRC;
	END

	IF HAS_PERMS_BY_NAME(null, null, 'VIEW SERVER STATE') <> 1
	BEGIN
		SET @ErrorMessage = N'The VIEW SERVER STATE permission (or permissions/role membership that include VIEW SERVER STATE) is required to execute ServerEye. Exiting...';
		SET @lv__ThisRC = -5;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='Perms Validation', @Message=@ErrorMessage;

		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END


	--If we have an N'AllDay' AbortTrace flag entry for this day, then exit the procedure
	--Note that this logic should NOT be based on UTC time.
	IF EXISTS (SELECT * FROM ServerEye.SignalTable WITH (ROWLOCK) 
				WHERE LOWER(SignalName) = N'aborttrace' 
				AND LOWER(SignalValue) = N'allday'
				AND DATEDIFF(DAY, InsertTime, GETDATE()) = 0 )
	BEGIN
		SET @ErrorMessage = N'An AbortTrace signal exists for today. This procedure has been told not to run the rest of the day.';
		SET @lv__ThisRC = -7;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='Abort flag exists', @Message=@ErrorMessage;

		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END

	--Delete any OneTime signals in the table, or signals in the past
	DELETE FROM ServerEye.SignalTable
	WHERE LOWER(SignalName) = N'aborttrace' 
	AND (
		LOWER(SignalValue) = N'onetime'
		OR 
		DATEDIFF(DAY, InsertTime, GETDATE()) > 0
		);

	--Obtain the next start/end times... Note that TraceTimeInfo calls the ValidateOption procedure
	DECLARE @lv__ServerEyeStartTimeUTC DATETIME, 
			@lv__ServerEyeEndTimeUTC DATETIME, 
			@lv__ServerEyeEnabled NCHAR(1);

	EXEC CoreXR.TraceTimeInfo @Utility=N'ServerEye', @PointInTimeUTC = NULL, @UtilityIsEnabled = @lv__ServerEyeEnabled OUTPUT,
		@UtilityStartTimeUTC = @lv__ServerEyeStartTimeUTC OUTPUT, @UtilityEndTimeUTC = @lv__ServerEyeEndTimeUTC OUTPUT;

	IF @lv__ServerEyeEnabled = N'N'
	BEGIN
		SET @ErrorMessage = 'According to the option table, ServerEye is not enabled';
		SET @lv__ThisRC = -9;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='NotEnabled', @Message=@ErrorMessage;
	
		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END

	IF NOT (GETUTCDATE() BETWEEN @lv__ServerEyeStartTimeUTC AND @lv__ServerEyeEndTimeUTC)
	BEGIN
		SET @ErrorMessage = 'The Current time is not within the window specified by BeginTime and EndTime options.';
		SET @ErrorMessage = @ErrorMessage + ' Current time: ' + CONVERT(NVARCHAR(20),GETDATE()) + '; UTC time: ' + CONVERT(NVARCHAR(20),GETUTCDATE()) + 
			'; Next ServerEye Start time (UTC): ' + CONVERT(NVARCHAR(20),@lv__ServerEyeStartTimeUTC) + 
			'; Next ServerEye End time (UTC): ' + CONVERT(NVARCHAR(20),@lv__ServerEyeEndTimeUTC);
		SET @lv__ThisRC = -11;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='Outside Begin/End', @Message=@ErrorMessage;
	
		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END

							
	SELECT 
		@opt__IntervalLength					= [IntervalLength],
		@opt__IncludeDBs						= [IncludeDBs],
		@opt__ExcludeDBs						= [ExcludeDBs],
		@opt__DebugSpeed						= [DebugSpeed]
	FROM ServerEye.Options o

	--Parse the DB include/exclude filter options (comma-delimited) into the user-typed table variable
	DECLARE @FilterTVP AS CoreXRFiltersType;
	/*
	CREATE TYPE CoreXRFiltersType AS TABLE 
	(
		FilterType TINYINT NOT NULL, 
			--0 DB inclusion
			--1 DB exclusion
		FilterID INT NOT NULL, 
		FilterName NVARCHAR(255)
	)
	*/

	IF ISNULL(@opt__IncludeDBs,N'') = N''
	BEGIN
		SET @lv__DBInclusionsExist = 0;		--this flag (only for inclusions) is a perf optimization used by the ServerEye Collector proc
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO @FilterTVP (FilterType, FilterID, FilterName)
				SELECT 0, d.database_id, d.name
				FROM (SELECT [dbnames] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @opt__IncludeDBs,  N',' , N'</M><M>') + N'</M>' AS XML) AS dblist) xmlparse
					CROSS APPLY dblist.nodes(N'/M') Split(a)
					) SS
					INNER JOIN sys.databases d			--we need the join to sys.databases so that we can get the correct case for the DB name.
						ON LOWER(SS.dbnames) = LOWER(d.name)	--the user may have passed in a db name that doesn't match the case for the DB name in the catalog,
				WHERE SS.dbnames <> N'';						-- and on a server with case-sensitive collation, we need to make sure we get the DB name exactly right

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @lv__DBInclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @lv__DBInclusionsExist = 1;
			END
		END TRY
		BEGIN CATCH
			SET @ErrorMessage = N'Error occurred when attempting to convert the "IncludeDBs option (comma-separated list of database names) to a table of valid DB names. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			SET @lv__ThisRC = -13;
			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='DB Inclusions', @Message=@ErrorMessage;
	
			EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
			RETURN @lv__ThisRC;
		END CATCH
	END

	IF ISNULL(@opt__ExcludeDBs, N'') <> N''
	BEGIN
		BEGIN TRY 
			INSERT INTO @FilterTVP (FilterType, FilterID, FilterName)
				SELECT 1, d.database_id, d.name
				FROM (SELECT [dbnames] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @opt__ExcludeDBs,  N',' , N'</M><M>') + N'</M>' AS XML) AS dblist) xmlparse
					CROSS APPLY dblist.nodes(N'/M') Split(a)
					) SS
					INNER JOIN sys.databases d			--we need the join to sys.databases so that we can get the correct case for the DB name.
						ON LOWER(SS.dbnames) = LOWER(d.name)	--the user may have passed in a db name that doesn't match the case for the DB name in the catalog,
				WHERE SS.dbnames <> N'';						-- and on a server with case-sensitive collation, we need to make sure we get the DB name exactly right
		END TRY
		BEGIN CATCH
			SET @ErrorMessage = N'Error occurred when attempting to convert the "ExcludeDBs option (comma-separated list of database names) to a table of valid DB names. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			SET @lv__ThisRC = -15;
			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='DB Exclusions', @Message=@ErrorMessage;
	
			EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
			RETURN @lv__ThisRC;
		END CATCH
	END 

	IF EXISTS (SELECT * FROM @FilterTVP t1 INNER JOIN @FilterTVP t2 ON t1.FilterID = t2.FilterID AND t1.FilterType = 0 AND t2.FilterType = 1)
	BEGIN
		SET @ErrorMessage = N'One or more DB names are present in both the IncludeDBs option and ExcludeDBs option. This is not allowed.';

		SET @lv__ThisRC = -17;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='IncludeExclude', @Message=@ErrorMessage;
	
		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END

	SET @lv__RunTimeSeconds = DATEDIFF(SECOND, GETUTCDATE(), @lv__ServerEyeEndTimeUTC);

	IF @lv__RunTimeSeconds < 120
	BEGIN
		SET @ErrorMessage = N'The current time, combined with the BeginTime and EndTime options, have resulted in a trace that will run for < 120 seconds. This is not allowed, and the trace will not be started.';
		SET @lv__ThisRC = -19;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='Less 60sec', @Message=@ErrorMessage;
	
		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END


	--Ok, let's get a valid TraceID value and then start the loop!
	BEGIN TRY
		EXEC @lv__TraceID = CoreXR.CreateTrace @Utility=N'ServerEye', @Type=N'Background', @IntendedStopTimeUTC = @lv__ServerEyeEndTimeUTC;

		IF ISNULL(@lv__TraceID,-1) < 0
		BEGIN
			SET @ErrorMessage = N'TraceID value is invalid. The Create Trace procedure failed silently.';
			SET @lv__ThisRC = -21;
			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='InvalidTraceID', @Message=@ErrorMessage;
	
			EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
			RETURN @lv__ThisRC;
		END
	END TRY
	BEGIN CATCH
		SET @ErrorMessage = N'Exception occurred when creating a new trace: ' + ERROR_MESSAGE();
		SET @lv__ThisRC = -23;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=NULL, @Location='CreateTraceException', @Message=@ErrorMessage;

		EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';
		RETURN @lv__ThisRC;
	END CATCH

	SET @ErrorMessage = N'Starting ServerEye trace using TraceID ''' + CONVERT(varchar(20),@lv__TraceID) + '''.';
	EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=@lv__TraceID, @Location='Print TraceID', @Message=@ErrorMessage;

	SET @ErrorMessage = N'The ServerEye trace is going to run for ''' + convert(varchar(20),@lv__RunTimeSeconds) + ''' seconds.';
	EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=@lv__TraceID, @Location='Runtime calc', @Message=@ErrorMessage;

	--Unsure if I need this for ServerEye.
	SET @lv__TempDBCreateTime = (select d.create_date from sys.databases d where d.name = N'tempdb');


	EXEC ServerEye.PrePopulateDimensions;

	SET @lv__SQLServerStartTime = (select sqlserver_start_time from sys.dm_os_sys_info);

	--When we collect ring buffers, we use track the min & max timestamps that we've observed so that we can avoid the overhead of re-processing
	-- ring buffer entries that we've processed before. Since the ring buffers empty out on a SQL restart, we track the sql server start time 
	-- so we can throw away old entries. The reason we keep min around, and not just max, is in case the timestamp field wraps to negative. 
	DELETE targ 
	FROM ServerEye.RingBufferProgress targ 
	WHERE targ.sqlserver_start_time <> @lv__SQLServerStartTime;

	CREATE TABLE #DistinctRBs (
		ring_buffer_type NVARCHAR(128)
	);

	INSERT INTO #DistinctRBs (
		ring_buffer_type
	)
	SELECT DISTINCT rb.ring_buffer_type
	FROM sys.dm_os_ring_buffers rb;

	-- The current ring buffer contents may not have all of the known types. We want our ServerEye.RingBufferProgress
	-- table to have a record for every type (as much as is possible) so we check that the well-known types are present
	INSERT INTO #DistinctRBs (
		ring_buffer_type
	)
	SELECT subq.ring_buffer_type
	FROM (
		SELECT N'RING_BUFFER_RESOURCE_MONITOR' as ring_buffer_type UNION ALL 
		SELECT N'RING_BUFFER_MEMORY_BROKER' UNION ALL 
		SELECT N'RING_BUFFER_SCHEDULER_MONITOR' UNION ALL 
		SELECT N'RING_BUFFER_MEMORY_BROKER_CLERKS' UNION ALL 
		SELECT N'RING_BUFFER_SECURITY_ERROR' UNION ALL 
		SELECT N'RING_BUFFER_SCHEDULER' UNION ALL 
		SELECT N'RING_BUFFER_EXCEPTION' UNION ALL 
		SELECT N'RING_BUFFER_CONNECTIVITY' UNION ALL 
		SELECT N'RING_BUFFER_HOBT_SCHEMAMGR' UNION ALL 
		SELECT N'RING_BUFFER_XE_BUFFER_STATE' UNION ALL 
		SELECT N'RING_BUFFER_XE_LOG' UNION ALL 
		SELECT N'RING_BUFFER_CLRAPPDOMAIN' 
	) subq
	WHERE NOT EXISTS (
		SELECT * FROM #DistinctRBs t
		WHERE t.ring_buffer_type = subq.ring_buffer_type
	);

	INSERT INTO ServerEye.RingBufferProgress (
		sqlserver_start_time, ring_buffer_type, max_timestamp_processed
	)
	SELECT @lv__SQLServerStartTime, rb.ring_buffer_type, 0
	FROM #DistinctRBs rb
	WHERE NOT EXISTS (
		SELECT *
		FROM ServerEye.RingBufferProgress rb2
		WHERE rb2.ring_buffer_type = rb.ring_buffer_type
	);

	/*
		@opt__IntervalLength can be one of the following: 1, 2, or 5
		This governs how many minutes are between each run of the high-frequency metrics.
	
		We calculate our other frequencies (medium, low, batch) as a multiple of the high-frequency.

			Medium	5x (so every 5, 10, or 25 minutes)

			Low 10x (so every 10, 20, or 50 minutes)

			Batch 30x (so every 30, 60, or 300 minutes)
	*/
	SET @lv__MediumInterval = @opt__IntervalLength * 5;
	SET @lv__LowInterval = @opt__IntervalLength * 10;
	SET @lv__BatchInterval = @opt__IntervalLength * 30;

	SET @lv__LoopCounter = 0;
	SET @lv__SuccessiveExceptions = 0;
	SET @lv__EarlyAbort = N'N';				--O - one time; A - all day

	WHILE (GETUTCDATE() < @lv__ServerEyeEndTimeUTC AND @lv__EarlyAbort = N'N')
	BEGIN
		--reset certain vars every iteration
		SET @lv__LoopStartTimeUTC = GETUTCDATE();
		SET @lv__LoopCounter = @lv__LoopCounter + 1;
		SET @lv__LocalCaptureTime = NULL;
		SET @lv__MediumFreqThisRun = 0;
		SET @lv__LowFreqThisRun = 0;
		SET @lv__BatchFreqThisRun = 0;
		SET @lv__HighFrequencySuccessful = 0;
		SET @lv__MediumFrequencySuccessful = 0;
		SET @lv__LowFrequencySuccessful = 0;
		SET @lv__BatchFrequencySuccessful = 0;
		SET @lv__RunWasSuccessful = 0;
		SET @lv__ExceptionThisRun = 0;

		IF @lv__LoopCounter = 1
		BEGIN
			--When we start up, we grab everything.
			SET @lv__MediumFreqThisRun = 1;
			SET @lv__LowFreqThisRun = 1;
			SET @lv__BatchFreqThisRun = 1;
		END
		ELSE
		BEGIN
			IF @lv__LoopCounter % @lv__MediumInterval = 0
			BEGIN
				SET @lv__MediumFreqThisRun = 1;
			END

			IF @lv__LoopCounter % @lv__LowInterval = 0
			BEGIN
				SET @lv__LowFreqThisRun = 1;
			END

			IF @lv__LoopCounter % @lv__BatchInterval = 0
			BEGIN
				SET @lv__BatchFreqThisRun = 1;
			END
		END

		SET @lv__UTCCaptureTime = GETUTCDATE();
		SET @lv__LocalCaptureTime = DATEADD(MINUTE, 0-DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @lv__UTCCaptureTime);

		--Each collector proc raises an exception if not successful for any reason.
		BEGIN TRY
			EXEC @lv__ProcRC = ServerEye.CollectorHiFreq @init = 255,
					@LocalCaptureTime = @lv__LocalCaptureTime, 
					@UTCCaptureTime = @lv__UTCCaptureTime,
					@SQLServerStartTime	= @lv__SQLServerStartTime;

			SET @lv__HighFrequencySuccessful = 1;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @lv__HighFrequencySuccessful = -1;

			SET @ErrorMessage = 'Executor: ServerEye CollectorHiFreq procedure generated an exception: Error Number: ' + 
				CONVERT(VARCHAR(20), ERROR_NUMBER()) + '; Error Message: ' + ERROR_MESSAGE();
			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-25, @TraceID=@lv__TraceID, @Location='Executor: HiFreq exception', @Message=@ErrorMessage;

			SET @lv__ExceptionThisRun = 1;
		END CATCH

		IF @lv__MediumFreqThisRun = 1
		BEGIN
			BEGIN TRY
				EXEC @lv__ProcRC = ServerEye.CollectorMedFreq @init = 255,
						@LocalCaptureTime = @lv__LocalCaptureTime, 
						@UTCCaptureTime = @lv__UTCCaptureTime,
						@SQLServerStartTime	= @lv__SQLServerStartTime;

				SET @lv__MediumFrequencySuccessful = 1;
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > 0 ROLLBACK;

				SET @lv__MediumFrequencySuccessful = -1;

				SET @ErrorMessage = 'Executor: ServerEye CollectorMedFreq procedure generated an exception: Error Number: ' + 
					CONVERT(VARCHAR(20), ERROR_NUMBER()) + '; Error Message: ' + ERROR_MESSAGE();
				EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-27, @TraceID=@lv__TraceID, @Location='Executor: MedFreq exception', @Message=@ErrorMessage;

				SET @lv__ExceptionThisRun = 1;
			END CATCH
		END


		IF @lv__LowFreqThisRun = 1
		BEGIN
			BEGIN TRY
				EXEC @lv__ProcRC = ServerEye.CollectorLowFreq @init = 255,
						@LocalCaptureTime = @lv__LocalCaptureTime, 
						@UTCCaptureTime = @lv__UTCCaptureTime,
						@SQLServerStartTime	= @lv__SQLServerStartTime;

				SET @lv__LowFrequencySuccessful = 1;
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > 0 ROLLBACK;

				SET @lv__LowFrequencySuccessful = -1;

				SET @ErrorMessage = 'Executor: ServerEye CollectorLowFreq procedure generated an exception: Error Number: ' + 
					CONVERT(VARCHAR(20), ERROR_NUMBER()) + '; Error Message: ' + ERROR_MESSAGE();
				EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-29, @TraceID=@lv__TraceID, @Location='Executor: LowFreq exception', @Message=@ErrorMessage;

				SET @lv__ExceptionThisRun = 1;
			END CATCH
		END

		IF @lv__BatchFreqThisRun = 1
		BEGIN
			BEGIN TRY
				EXEC @lv__ProcRC = ServerEye.CollectorBatchFreq @init = 255,
						@LocalCaptureTime = @lv__LocalCaptureTime, 
						@UTCCaptureTime = @lv__UTCCaptureTime,
						@SQLServerStartTime	= @lv__SQLServerStartTime;

				SET @lv__BatchFrequencySuccessful = 1;
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > 0 ROLLBACK;

				SET @lv__BatchFrequencySuccessful = -1;

				SET @ErrorMessage = 'Executor: ServerEye CollectorBatchFreq procedure generated an exception: Error Number: ' + 
					CONVERT(VARCHAR(20), ERROR_NUMBER()) + '; Error Message: ' + ERROR_MESSAGE();
				EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-29, @TraceID=@lv__TraceID, @Location='Executor: BatchFreq exception', @Message=@ErrorMessage;

				SET @lv__ExceptionThisRun = 1;
			END CATCH
		END

		IF @lv__ExceptionThisRun = 1
		BEGIN
			SET @lv__ExceptionThisRun = @lv__ExceptionThisRun + 1;
		END
		ELSE
		BEGIN
			SET @lv__SuccessiveExceptions = 0;
		END

		SET @ErrorMessage = 'Hi succ: ' + ISNULL(CONVERT(varchar(20),@lv__HighFrequencySuccessful),'<null>') + '
Med This Run: ' + ISNULL(CONVERT(varchar(20),@lv__MediumFreqThisRun),'<null>') + '
Med Succ: ' + ISNULL(CONVERT(varchar(20),@lv__MediumFrequencySuccessful),'<null>') + '
Low This Run: ' + ISNULL(CONVERT(varchar(20),@lv__LowFreqThisRun),'<null>') + '
Low Succ: ' + ISNULL(CONVERT(varchar(20),@lv__LowFrequencySuccessful),'<null>') + '
Batch This Run: ' + ISNULL(CONVERT(varchar(20),@lv__BatchFreqThisRun),'<null>') + '
Batch Succ: ' + ISNULL(CONVERT(varchar(20),@lv__BatchFrequencySuccessful),'<null>')
;
	EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=1, @TraceID=NULL, @Location='Collection Success Statusii', @Message=@ErrorMessage;

		SET @lv__RunWasSuccessful = CASE WHEN @lv__HighFrequencySuccessful = 1
										AND (
											(@lv__MediumFreqThisRun = 1 AND @lv__MediumFrequencySuccessful = 1)
											OR (@lv__MediumFreqThisRun = 0 AND @lv__MediumFrequencySuccessful = 0)
											)
										AND (
											(@lv__LowFreqThisRun = 1 AND @lv__LowFrequencySuccessful = 1)
											OR (@lv__LowFreqThisRun = 0 AND @lv__LowFrequencySuccessful = 0)
											)
										AND (
											(@lv__BatchFreqThisRun = 1 AND @lv__BatchFrequencySuccessful = 1)
											OR (@lv__BatchFreqThisRun = 0 AND @lv__BatchFrequencySuccessful = 0)
											)
									THEN 1
								ELSE 0
								END;

		INSERT INTO [ServerEye].[CaptureTimes] (
			[CollectionInitiatorID],
			[UTCCaptureTime],
			[LocalCaptureTime],
	
			[HighFrequencySuccessful],
			[MediumFrequencySuccessful],
			[LowFrequencySuccessful],
			[BatchFrequencySuccessful],

			[RunWasSuccessful],
			[ExtractedForDW],
			[ServerEyeDuration_ms],
			[DurationBreakdown]
		)
		SELECT 
			255,
			@lv__UTCCaptureTime,
			@lv__LocalCaptureTime,
			@lv__HighFrequencySuccessful,
			@lv__MediumFrequencySuccessful,
			@lv__LowFrequencySuccessful,
			@lv__BatchFrequencySuccessful,
		
			[RunWasSuccessful] = @lv__RunWasSuccessful,
			[ExtractedForDW] = 0,
			[ServerEyeDuration_ms] = 0,		--TODO
			[DurationBreakdown] = NULL;		--TODO
		
		IF @lv__RunWasSuccessful = 1
		BEGIN
			UPDATE targ 
			SET PrevSuccessfulUTCCaptureTime = hi.UTCCaptureTime,

				/*
					NOPE, NOPE, changing my mind on this
						(Old)We only set the prev-successful times for these 3 fields when the CURRENT capture
						actually ran the medium/low/batch code.(/Old)

					Every capture has a pointer to the previous successful collection of each type. The goal here
					is to optimize the viewer procs (and any other consumers of the data) so that instead of having
					to calculate the "Previous Successful X", they already have a correct pointer and can join
					in the correct previous data as needed.
				*/
				PrevSuccessfulMedium = md.UTCCaptureTime,
				PrevSuccessfulLow = lo.UTCCaptureTime,
				PrevSuccessfulBatch = b.UTCCaptureTime
			FROM ServerEye.CaptureTimes targ
				OUTER APPLY (
					SELECT TOP 1
						hi.UTCCaptureTime
					FROM ServerEye.CaptureTimes hi
					WHERE hi.UTCCaptureTime < @lv__UTCCaptureTime
					--must be within 10 minutes (double the highest frequency allowed for @opt__IntervalLength)
					AND hi.UTCCaptureTime >= DATEADD(MINUTE, -10, @lv__UTCCaptureTime)
					AND hi.RunWasSuccessful = 1
					ORDER BY hi.UTCCaptureTime DESC
				) hi
				OUTER APPLY (
					SELECT TOP 1
						md.UTCCaptureTime
					FROM ServerEye.CaptureTimes md
					WHERE md.UTCCaptureTime < @lv__UTCCaptureTime
					--must be within 30 minutes (5 min longer than the longest amount of time allowed for medium frequency)
					AND md.UTCCaptureTime >= DATEADD(MINUTE, -30, @lv__UTCCaptureTime)
					AND md.RunWasSuccessful = 1
					AND md.MediumFrequencySuccessful = 1
					ORDER BY md.UTCCaptureTime DESC
				) md
				OUTER APPLY (
					SELECT TOP 1
						lo.UTCCaptureTime
					FROM ServerEye.CaptureTimes lo
					WHERE lo.UTCCaptureTime < @lv__UTCCaptureTime
					--must be within 60 minutes (10 min longer than the longest amount of time allowed for low frequency)
					AND lo.UTCCaptureTime >= DATEADD(MINUTE, -60, @lv__UTCCaptureTime)
					AND lo.RunWasSuccessful = 1
					AND lo.LowFrequencySuccessful = 1
					ORDER BY lo.UTCCaptureTime DESC
				) lo
				OUTER APPLY (
					SELECT TOP 1
						b.UTCCaptureTime
					FROM ServerEye.CaptureTimes b
					WHERE b.UTCCaptureTime < @lv__UTCCaptureTime
					--must be within 5.5 hours (30 min longer than the longest amount of time allowed for batch frequency)
					AND b.UTCCaptureTime >= DATEADD(MINUTE, -330, @lv__UTCCaptureTime)
					AND b.RunWasSuccessful = 1
					AND b.BatchFrequencySuccessful = 1
					ORDER BY b.UTCCaptureTime DESC
				) b
			WHERE targ.UTCCaptureTime = @lv__UTCCaptureTime;
		END
	

		IF @lv__SuccessiveExceptions >= 5
		BEGIN
			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-35, @TraceID=@lv__TraceID, @Location='Abort b/c exceptions', @Message=N'5 consecutive failures; this procedure is terminating.';

			SET @lv__EarlyAbort = N'E';	--signals (to the logic immediately after the WHILE loop's END) how we exited the loop

			--Ok, we've had 5 straight errors. Something is wrong, and we need a human to intervene.
			--To prevent the procedure from just firing up a few minutes later, we insert a record into the signal table
			INSERT INTO ServerEye.SignalTable
			(SignalName, SignalValue, InsertTime)
			SELECT N'AbortTrace', N'AllDay', GETDATE();
		END

		--Note that we put this outside the TRY/CATCH, so that even if we encounter an exception, we can 
		-- still evaluate how long it took to hit that exception, and (if it was a long time), gather info
		-- about the system in a more lightweight way.
		SET @lv__ServerEyeCallCompleteTimeUTC = GETUTCDATE();


		--now we check to see if someone has asked that we stop the trace (or we've hit our 10-exceptions-in-a-row condition)
		--(this logic implements our manual stop logic)
		SELECT 
			@lv__EarlyAbort = firstchar 
		FROM (
			SELECT TOP 1 
				CASE WHEN LOWER(SignalValue) = N'allday' THEN N'A' 
					WHEN LOWER(SignalValue) = N'onetime' THEN N'O'
					ELSE NULL 
					END as firstchar
			FROM ServerEye.SignalTable WITH (NOLOCK) 
			WHERE SignalName = N'AbortTrace' 
			AND DATEDIFF(DAY, InsertTime, GETDATE()) = 0
			ORDER BY InsertTime DESC		--always used the latest flag if there is more than 1 in a day
		) ss;

		IF @lv__EarlyAbort IS NULL
		BEGIN
			SET @lv__EarlyAbort = N'N';
		END
		ELSE
		BEGIN
			IF @lv__EarlyAbort <> N'N'
			BEGIN
				SET @ErrorMessage = N'An AbortTrace signal value was found (for today), with type: ' + ISNULL(@lv__EarlyAbort,'?');
				EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=1, @TraceID=@lv__TraceID, @Location='Abort b/c signal', @Message=@ErrorMessage;
			END
		END


		--reached the end of our loop. As long as we are not early-aborting, calculate how long to WAITFOR DELAY
		--Note that our Options check constraint on the IntervalLength column allows intervals ranging from 5 seconds to 300 seconds
		IF @lv__EarlyAbort = N'N'
		BEGIN
			--@lv__LoopStartTimeUTC holds the time this iteration of the loop began. i.e. SET @lv__LoopStartTimeUTC = GETUTCDATE()
			SET @lv__LoopEndTimeUTC = GETUTCDATE();
			SET @lv__LoopNextStartUTC = DATEADD(MINUTE, @opt__IntervalLength, @lv__LoopStartTimeUTC); 

			--If the Collector proc ran so long that the current time is actually >= @lv__LoopNextStartUTC, we 
			-- increment the target time by the interval until the target is in the future.
			WHILE @lv__LoopNextStartUTC <= @lv__LoopEndTimeUTC
			BEGIN
				SET @lv__LoopNextStartUTC = DATEADD(MINUTE, @opt__IntervalLength, @lv__LoopNextStartUTC);
			END

			SET @lv__LoopNextStartSecondDifferential = DATEDIFF(SECOND, @lv__LoopEndTimeUTC, @lv__LoopNextStartUTC);

			SET @lv__WaitForMinutes = @lv__LoopNextStartSecondDifferential / 60;
			SET @lv__LoopNextStartSecondDifferential = @lv__LoopNextStartSecondDifferential % 60;

			SET @lv__WaitForSeconds = @lv__LoopNextStartSecondDifferential;
		
			SET @lv__WaitForString = '00:' + 
									CASE WHEN @lv__WaitForMinutes BETWEEN 10 AND 59
										THEN CONVERT(VARCHAR(10), @lv__WaitForMinutes)
										ELSE '0' + CONVERT(VARCHAR(10), @lv__WaitForMinutes)
										END + ':' + 
									CASE WHEN @lv__WaitForSeconds BETWEEN 10 AND 59 
										THEN CONVERT(VARCHAR(10), @lv__WaitForSeconds)
										ELSE '0' + CONVERT(VARCHAR(10), @lv__WaitForSeconds)
										END;
		
			WAITFOR DELAY @lv__WaitForString;
		END -- check @lv__EarlyAbort to see if we should construct/execute WAITFOR
	END		--WHILE (GETUTCDATE() < @lv__ServerEyeEndTimeUTC AND @lv__EarlyAbort = N'N')

	--clean up any signals that are now irrelevant. (Remember, OneTime signals get deleted immediately after their use
	DELETE FROM ServerEye.SignalTable 
	WHERE SignalName = N'AbortTrace' 
	AND (
		LOWER(SignalValue) = N'onetime'
		OR 
		DATEDIFF(DAY, InsertTime, GETDATE()) > 0
		);

	IF @lv__EarlyAbort = N'E'
	BEGIN
		SET @lv__ThisRC = -37;
		SET @ErrorMessage = 'Exiting wrapper procedure due to exception-based abort';
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=@lv__TraceID, @Location='Exception exit', @Message=@ErrorMessage;

		EXEC @@CHIRHO_SCHEMA@@.CoreXR_AbortTrace @Utility = N'ServerEye', @TraceID = @lv__TraceID, @AbortCode = @lv__EarlyAbort, @PreventAllDay = N'Y';
	END
	ELSE IF @lv__EarlyAbort IN (N'O', N'A')
	BEGIN
		SET @lv__ThisRC = -39;
		SET @ErrorMessage = 'Exiting wrapper procedure due to manual abort, type: ' + @lv__EarlyAbort;
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=@lv__TraceID, @Location='Manual abort exit', @Message=@ErrorMessage;

		--We don't need to abort this trace as it should have been aborted already
	END
	ELSE 
	BEGIN
		SET @lv__ThisRC = 0;
		SET @ErrorMessage = 'ServerEye trace successfully completed.';
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=@lv__ThisRC, @TraceID=@lv__TraceID, @Location='Successful complete', @Message=@ErrorMessage;

		EXEC CoreXR.StopTrace @Utility=N'ServerEye', @TraceID = @lv__TraceID, @AbortCode = @lv__EarlyAbort;
	END

	EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session';

	RETURN @lv__ThisRC;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @ErrorMessage = N'Unexpected exception occurred: Error #' + ISNULL(CONVERT(nvarchar(20),ERROR_NUMBER()),N'<null>') + 
		N'; State: ' + ISNULL(CONVERT(nvarchar(20),ERROR_STATE()),N'<null>') + 
		N'; Severity' + ISNULL(CONVERT(nvarchar(20),ERROR_SEVERITY()),N'<null>') + 
		N'; Message: ' + ISNULL(ERROR_MESSAGE(), N'<null>');

	EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='CATCH block', @Message=@ErrorMessage;

	EXEC sp_releaseapplock @Resource = 'ServerEyeBackgroundTrace', @LockOwner = 'Session'

	RETURN -1;
END CATCH
END
GO
