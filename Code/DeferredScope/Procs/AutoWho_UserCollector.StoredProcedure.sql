SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_UserCollector
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

	FILE NAME: AutoWho_UserCollector.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_UserCollector

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Called by the sp_XR_SessionViewer and sp_XR_QueryProgress user-facing procedures when current DMV data 
		is requested. This logic is similar to the @@CHIRHO_SCHEMA@@.AutoWho_Executor proc, though in some ways it is simpler and 
		uses a different method of specifying the loop frequency and end time.
		

	FUTURE ENHANCEMENTS: 
		Wrap everything in an outer TRY/CATCH

		What to do about session filtering & thresholds?

		Enable TF 8666?


To Execute
------------------------


*/
(
	@init				TINYINT,
	@optionset			NVARCHAR(50),
	@camrate			INT,
	@camstop			INT,
	@dir				NVARCHAR(512),			-- misc directives
	@omsg				NVARCHAR(4000) OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	SET ANSI_PADDING ON;

	--General variables 
	DECLARE 
		 @lv__AppLockResource			NVARCHAR(100),
		 @lv__ThisRC					INT, 
		 @lv__ProcRC					INT, 
		 @lv__tmpStr					NVARCHAR(4000),
		 @lv__ScratchInt				INT,
		 @lv__ScratchDateTime			DATETIME,
		 @lv__CalcEndTime				DATETIME,
		 @lv__RunTimeMinutes			BIGINT,
		 @lv__LoopStartTimeUTC			DATETIME,
		 @lv__AutoWhoCallCompleteTime	DATETIME,
		 @lv__LoopEndTimeUTC				DATETIME,
		 @lv__LoopNextStartUTC				DATETIME,
		 @lv__LoopNextStartUTCSecondDifferential INT,
		 @lv__WaitForMinutes			INT,
		 @lv__WaitForSeconds			INT,
		 @lv__WaitForString				VARCHAR(20),
		 @lv__IntervalRemainder			INT,
		 @lv__LoopDurationSeconds		INT,
		 @lv__LoopCounter				INT,
		 @lv__IntervalFrequency			INT,
		 @lv__DBInclusionsExist			BIT,
		 @lv__TempDBCreateTime			DATETIME,
		 @lv__NumSPIDsCaptured			INT,
		 @lv__SPIDCaptureTime			DATETIME,
		 @lv__UTCCaptureTime			DATETIME
		 ;

	--variables to hold option table contents
	DECLARE 
		@opt__IntervalLength					INT,
		@opt__IncludeIdleWithTran				NVARCHAR(5),
		@opt__IncludeIdleWithoutTran			NVARCHAR(5),
		@opt__DurationFilter					INT,
		@opt__IncludeDBs						NVARCHAR(500),	
		@opt__ExcludeDBs						NVARCHAR(500),	
		@opt__HighTempDBThreshold				INT,
		@opt__CollectSystemSpids				NCHAR(1),	
		@opt__HideSelf							NCHAR(1),

		@opt__ObtainBatchText					NCHAR(1),	
		@opt__ParallelWaitsThreshold			INT,
		@opt__ObtainLocksForBlockRelevantThreshold	INT,
		@opt__ObtainQueryPlanForStatement		NCHAR(1),	
		@opt__ObtainQueryPlanForBatch			NCHAR(1),
		@opt__InputBufferThreshold				INT,
		@opt__BlockingChainThreshold			INT,
		@opt__BlockingChainDepth				TINYINT,
		@opt__TranDetailsThreshold				INT,
		@opt__ResolvePageLatches				NCHAR(1),
		@opt__ResolveLockWaits					NCHAR(1),
		@opt__Enable8666						NCHAR(1),
		@opt__QueryPlanThreshold				INT,
		@opt__QueryPlanThresholdBlockRel		INT,
		@opt__UseBackgroundThresholdIgnore		NCHAR(1),

		@opt__DebugSpeed						NCHAR(1),
		@opt__SaveBadDims						NCHAR(1)
		;


	DECLARE @FilterTVP AS CoreXRFiltersType;
	/*
	CREATE TYPE CoreXRFiltersType AS TABLE 
	(
		FilterType TINYINT NOT NULL, 
			--0 DB inclusion
			--1 DB exclusion
			--128 threshold filtering (spids that shouldn't be counted against the various thresholds that trigger auxiliary data collection)
			--down the road, more to come (TODO: maybe filter by logins down the road?)
		FilterID INT NOT NULL, 
		FilterName NVARCHAR(255)
	)
	*/
	SET @lv__AppLockResource = N'AutoWhoUserCollector' + CONVERT(NVARCHAR(20),@init);

	EXEC @lv__ProcRC = sp_getapplock @Resource=@lv__AppLockResource,
				@LockOwner='Session',
				@LockMode='Exclusive',
				@LockTimeout=5000;

	IF @lv__ProcRC < 0
	BEGIN
		SET @omsg = N'Unable to obtain exclusive app lock for user collection.';
		RETURN -1;
	END

	SELECT 
		@opt__IncludeIdleWithTran				= [IncludeIdleWithTran],
		@opt__IncludeIdleWithoutTran			= [IncludeIdleWithoutTran],
		@opt__DurationFilter					= [DurationFilter],
		@opt__IncludeDBs						= [IncludeDBs],
		@opt__ExcludeDBs						= [ExcludeDBs],
		@opt__HighTempDBThreshold				= [HighTempDBThreshold],
		@opt__CollectSystemSpids				= [CollectSystemSpids],
		@opt__HideSelf							= [HideSelf],

		@opt__ObtainBatchText					= [ObtainBatchText],
		@opt__ParallelWaitsThreshold			= [ParallelWaitsThreshold],
		@opt__ObtainLocksForBlockRelevantThreshold = [ObtainLocksForBlockRelevantThreshold],
		@opt__ObtainQueryPlanForStatement		= [ObtainQueryPlanForStatement],
		@opt__ObtainQueryPlanForBatch			= [ObtainQueryPlanForBatch],
		@opt__QueryPlanThreshold				= [QueryPlanThreshold], 
		@opt__QueryPlanThresholdBlockRel		= [QueryPlanThresholdBlockRel], 
		@opt__InputBufferThreshold				= [InputBufferThreshold],
		@opt__BlockingChainThreshold			= [BlockingChainThreshold],
		@opt__BlockingChainDepth				= [BlockingChainDepth],
		@opt__TranDetailsThreshold				= [TranDetailsThreshold],
		@opt__ResolvePageLatches				= [ResolvePageLatches],
		@opt__ResolveLockWaits					= [ResolveLockWaits],
		@opt__Enable8666						= [Enable8666],
		@opt__DebugSpeed						= [DebugSpeed],
		@opt__SaveBadDims						= [SaveBadDims],
		@opt__UseBackgroundThresholdIgnore		= [UseBackgroundThresholdIgnore]
	FROM @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions o
	WHERE o.OptionSet = @optionset
	;

	

	IF ISNULL(@opt__IncludeDBs,N'') = N''
	BEGIN
		SET @lv__DBInclusionsExist = 0;		--this flag (only for inclusions) is a perf optimization used by the AutoWho Collector proc
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
			SET @omsg = N'Error occurred when attempting to convert the "IncludeDBs option (comma-separated list of database names) to a table of valid DB names. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
			RETURN -1;
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
			SET @omsg = N'Error occurred when attempting to convert the "ExcludeDBs option (comma-separated list of database names) to a table of valid DB names. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
			RETURN -1;
		END CATCH
	END 

	IF EXISTS (SELECT * FROM @FilterTVP t1 INNER JOIN @FilterTVP t2 ON t1.FilterID = t2.FilterID AND t1.FilterType = 0 AND t2.FilterType = 1)
	BEGIN
		SET @omsg = N'One or more DB names are present in both the IncludeDBs option and ExcludeDBs option. This is not allowed.';
		EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
		RETURN -1;
	END

	IF @opt__UseBackgroundThresholdIgnore = N'Y'
	BEGIN
		INSERT INTO @FilterTVP (FilterType, FilterID)
		SELECT DISTINCT 128, f.ThresholdFilterSpid
		FROM @@CHIRHO_SCHEMA@@.AutoWho_ThresholdFilterSpids f; 
	END

	SET @lv__TempDBCreateTime = (select d.create_date from sys.databases d where d.name = N'tempdb');

	--We are going to write all capture times to the AutoWho.UserCollectionTimes table so that
	-- other presentation-side logic can figure out which collection times belong to this specific
	-- user execution. First, we delete any previous records for this session

	DELETE 
	FROM @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionTimes 
	WHERE CollectionInitiatorID = @init 
	AND session_id = @@SPID
	;

	--Is this a one-time call? If so, call and exit

	IF @camrate = 0
	BEGIN
		SET @lv__NumSPIDsCaptured = -1;
		SET @lv__SPIDCaptureTime = NULL;

		BEGIN TRY
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_Collector
				@CollectionInitiatorID = @init,
				@TempDBCreateTime = @lv__TempDBCreateTime,
				@IncludeIdleWithTran = @opt__IncludeIdleWithTran,
				@IncludeIdleWithoutTran = @opt__IncludeIdleWithoutTran,
				@DurationFilter = @opt__DurationFilter, 
				@FilterTable = @FilterTVP, 
				@DBInclusionsExist = @lv__DBInclusionsExist, 
				@HighTempDBThreshold = @opt__HighTempDBThreshold, 
				@CollectSystemSpids = @opt__CollectSystemSpids, 
				@HideSelf = @opt__HideSelf, 

				@ObtainBatchText = @opt__ObtainBatchText,
				@QueryPlanThreshold = @opt__QueryPlanThreshold,
				@QueryPlanThresholdBlockRel = @opt__QueryPlanThresholdBlockRel,
				@ParallelWaitsThreshold = @opt__ParallelWaitsThreshold, 
				@ObtainLocksForBlockRelevantThreshold = @opt__ObtainLocksForBlockRelevantThreshold,
				@ObtainQueryPlanForStatement = @opt__ObtainQueryPlanForStatement, 
				@ObtainQueryPlanForBatch = @opt__ObtainQueryPlanForBatch,
				@InputBufferThreshold = @opt__InputBufferThreshold, 
				@BlockingChainThreshold = @opt__BlockingChainThreshold,
				@BlockingChainDepth = @opt__BlockingChainDepth, 
				@TranDetailsThreshold = @opt__TranDetailsThreshold,

				@DebugSpeed = N'N',
				@SaveBadDims = @opt__SaveBadDims,
				@NumSPIDs = @lv__NumSPIDsCaptured OUTPUT,
				@SPIDCaptureTime = @lv__SPIDCaptureTime OUTPUT,
				@UTCCaptureTime = @lv__UTCCaptureTime OUTPUT
			;

			INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionTimes 
			(CollectionInitiatorID, session_id, SPIDCaptureTime, UTCCaptureTime)
			SELECT @init, @@SPID, @lv__SPIDCaptureTime, @lv__UTCCaptureTime;

			--Try to link this capture up with a previous successful capture for this same initiator
			UPDATE targ 
			SET PrevSuccessfulUTCCaptureTime = prev.UTCCaptureTime
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
				OUTER APPLY (
					SELECT TOP 1
						ct.UTCCaptureTime
					FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
					WHERE ct.CollectionInitiatorID = @init
					AND ct.UTCCaptureTime < @lv__UTCCaptureTime
					--must be within 5 minutes 
					AND ct.UTCCaptureTime >= DATEADD(MINUTE, -5, @lv__UTCCaptureTime)
					AND ct.RunWasSuccessful = 1
					ORDER BY ct.UTCCaptureTime DESC
				) prev
			WHERE targ.UTCCaptureTime = @lv__UTCCaptureTime;
		END TRY
		BEGIN CATCH
			SET @omsg = 'User Collection: AutoWho Collector procedure generated an exception: Error Number: ' + 
				CONVERT(VARCHAR(20), ERROR_NUMBER()) + '; Error Message: ' + ERROR_MESSAGE();

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='User Collector exception', @Message=@omsg;

			EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
			RETURN -1;
		END CATCH

		EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
		RETURN 0;
	END	--IF @camrate = 0


	--INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_Log
	--(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
	--SELECT SYSDATETIME(),  NULL, 0, N'UserTrc Start', N'Starting AutoWho collection for user on spid ' + CONVERT(NVARCHAR(20),@@SPID) + N'.';

	SET @lv__LoopCounter = 0;

	DECLARE @lv__AutoWhoStartTimeUTC	DATETIME, 
			@lv__AutoWhoEndTimeUTC		DATETIME;

	SET @lv__AutoWhoStartTimeUTC = GETUTCDATE();
	SET @lv__AutoWhoEndTimeUTC = DATEADD(SECOND, @camstop, @lv__AutoWhoStartTimeUTC);
	SET @opt__IntervalLength = @camrate;


	WHILE (GETUTCDATE() < @lv__AutoWhoEndTimeUTC)
	BEGIN
		--reset certain vars every iteration
		SET @lv__LoopStartTimeUTC = GETUTCDATE();
		SET @lv__LoopCounter = @lv__LoopCounter + 1;
		SET @lv__NumSPIDsCaptured = -1;
		SET @lv__SPIDCaptureTime = NULL;

		BEGIN TRY
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_Collector
				@CollectionInitiatorID = @init,
				@TempDBCreateTime = @lv__TempDBCreateTime,
				@IncludeIdleWithTran = @opt__IncludeIdleWithTran,
				@IncludeIdleWithoutTran = @opt__IncludeIdleWithoutTran,
				@DurationFilter = @opt__DurationFilter, 
				@FilterTable = @FilterTVP, 
				@DBInclusionsExist = @lv__DBInclusionsExist, 
				@HighTempDBThreshold = @opt__HighTempDBThreshold, 
				@CollectSystemSpids = @opt__CollectSystemSpids, 
				@HideSelf = @opt__HideSelf, 

				@ObtainBatchText = @opt__ObtainBatchText,
				@QueryPlanThreshold = @opt__QueryPlanThreshold,
				@QueryPlanThresholdBlockRel = @opt__QueryPlanThresholdBlockRel,
				@ParallelWaitsThreshold = @opt__ParallelWaitsThreshold, 
				@ObtainLocksForBlockRelevantThreshold = @opt__ObtainLocksForBlockRelevantThreshold,
				@ObtainQueryPlanForStatement = @opt__ObtainQueryPlanForStatement, 
				@ObtainQueryPlanForBatch = @opt__ObtainQueryPlanForBatch,
				@InputBufferThreshold = @opt__InputBufferThreshold, 
				@BlockingChainThreshold = @opt__BlockingChainThreshold,
				@BlockingChainDepth = @opt__BlockingChainDepth, 
				@TranDetailsThreshold = @opt__TranDetailsThreshold,

				@DebugSpeed = @opt__DebugSpeed,
				@SaveBadDims = @opt__SaveBadDims,
				@NumSPIDs = @lv__NumSPIDsCaptured OUTPUT,
				@SPIDCaptureTime = @lv__SPIDCaptureTime OUTPUT,
				@UTCCaptureTime = @lv__UTCCaptureTime OUTPUT
			;

			INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionTimes 
			(CollectionInitiatorID, session_id, SPIDCaptureTime, UTCCaptureTime)
			SELECT @init, @@SPID, @lv__SPIDCaptureTime, @lv__UTCCaptureTime;

			UPDATE targ 
			SET PrevSuccessfulUTCCaptureTime = prev.UTCCaptureTime
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
				OUTER APPLY (
					SELECT TOP 1
						ct.UTCCaptureTime
					FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
					WHERE ct.CollectionInitiatorID = @init
					AND ct.UTCCaptureTime < @lv__UTCCaptureTime
					--must be within 5 minutes 
					AND ct.UTCCaptureTime >= DATEADD(MINUTE, -5, @lv__UTCCaptureTime)
					AND ct.RunWasSuccessful = 1
					ORDER BY ct.UTCCaptureTime DESC
				) prev
			WHERE targ.UTCCaptureTime = @lv__UTCCaptureTime;
		END TRY
		BEGIN CATCH
			SET @omsg = 'User Collection: AutoWho Collector procedure generated an exception: Error Number: ' + 
				CONVERT(VARCHAR(20), ERROR_NUMBER()) + '; Error Message: ' + ERROR_MESSAGE();
				
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='User Collector exception', @Message=@omsg;

			EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
			RETURN -1;
		END CATCH

		--Calculate how long to WAITFOR DELAY
		--@lv__LoopStartTimeUTC holds the time this iteration of the loop began. i.e. SET @lv__LoopStartTimeUTC = GETDATE()
		SET @lv__LoopEndTimeUTC = GETUTCDATE();
		SET @lv__LoopNextStartUTC = DATEADD(SECOND, @opt__IntervalLength, @lv__LoopStartTimeUTC); 

		--If the Collector proc ran so long that the current time is actually >= @lv__LoopNextStartUTC, we 
		-- increment the target time by the interval until the target is in the future.
		WHILE @lv__LoopNextStartUTC <= @lv__LoopEndTimeUTC
		BEGIN
			SET @lv__LoopNextStartUTC = DATEADD(SECOND, @opt__IntervalLength, @lv__LoopNextStartUTC);
		END

		SET @lv__LoopNextStartUTCSecondDifferential = DATEDIFF(SECOND, @lv__LoopEndTimeUTC, @lv__LoopNextStartUTC);

		SET @lv__WaitForMinutes = @lv__LoopNextStartUTCSecondDifferential / 60;
		SET @lv__LoopNextStartUTCSecondDifferential = @lv__LoopNextStartUTCSecondDifferential % 60;

		SET @lv__WaitForSeconds = @lv__LoopNextStartUTCSecondDifferential;
		
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
	END		--WHILE (GETUTCDATE() < @lv__AutoWhoEndTimeUTC)

	EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';

	RETURN 0;
END
GO