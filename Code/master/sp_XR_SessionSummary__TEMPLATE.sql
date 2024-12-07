SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_MASTERPROC_SCHEMA@@.sp_XR_SessionSummary
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

	FILE NAME: sp_XR_SessionSummary__TEMPLATE.sql

	PROCEDURE NAME: sp_XR_SessionSummary

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com
					https://github.com/AaronMorelli/ChiRho

	PURPOSE: Returns 1 row per AutoWho capture time, with many aggregation columns indicating
		what was occurring in the system at that time. The goal of this procedure is to help
		the user quickly find "problem times" for this SQL instance, since often end users
		complain in general/vague terms about the nature of the app problem and the time in which
		those problems occurred. Whereas sp_XR_SessionViewer gives detailed info at a particular 
		point in time (the "SPID Capture Time"), and is very useful for determining the root cause
		for problems, it is a poor tool for scanning through a larger time window very quickly.
		Thus, sp_XR_SessionSummary is a complementary tool to help the SQL Server professional 
		focus on the problematic time window quickly, without sifting through mountains of data.

		(Though some might argue that 70+ columns of output is a mountain of data!)

To Execute
------------------------
exec sp_XR_SessionSummary @start='2015-10-08',@end='2015-10-08 14:00',
	@savespace=N'N',@orderby=1, @orderdir=N'A', @help=N'N'

--debug: select * from @@CHIRHO_DB@@.@@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary
*/
(
	@start			DATETIME=NULL,			--the start of the time window. If NULL, defaults to 4 hours ago.
	@end			DATETIME=NULL,			-- the end of the time window. If NULL, defaults to 1 second ago.
	@source			NVARCHAR(20)=N'trace',		--'trace' = standard AutoWho_Executor background trace; 
												-- 'pastsv' reviews data from past sp_XR_SessionViewer calls done in "current" mode
												-- 'pastqp' reviews data from past sp_XR_QueryProgress calls done in "current" or "time series" mode.
												-- This param is ignored if this invocation is "current" mode (i.e. start/end are null)
	@savespace		NCHAR(1)=N'N',			--shorter column header names
	@orderby		INT=1,					-- the column number to order by. Column #'s are part of the column name if @savespace=N'N'
	@orderdir		NCHAR(1)=N'A',			-- (A)scending or (D)escending
	@units			NVARCHAR(20)=N'mb',		-- mb, native, or pages
	@help			NVARCHAR(10)=N'N'		-- "params", "columns", or "all" (anything else <> "N" maps to "all")
)
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET ANSI_PADDING ON;

	DECLARE @scratch__int				INT,
			@lv__StartUTC				DATETIME,
			@lv__EndUTC					DATETIME,
			@lv__CollectionInitiatorID	TINYINT,
			@lv__numCaptures			INT,
			@lv__numNeedPopulation		INT,
			@lv__orderByColumn			NVARCHAR(100),			--Need this so that we can order by native value rather than by formatted string
			@lv__helpexec				NVARCHAR(4000),
			@err__msg					NVARCHAR(MAX),
			@lv__DynSQL					NVARCHAR(MAX),
			@lv__helpstr				NVARCHAR(MAX);

	--We always print out the exec syntax (whether help was requested or not) so that the user can switch over to the Messages
	-- tab and see what their options are.
	SET @lv__helpexec = N'
exec sp_XR_SessionSummary @start=''<start datetime>'', @end=''<end datetime>'', 
	@source=N''trace'',		-- t/trace, sv/pastsv, qp/pastqp
	@savespace = N''n | y'', @orderby = <integer greater than 0>, 
	@orderdir = N''a | d'', @units=N''mb'',			-- m/mb, p/pages, n/native
	@help = N''n''		--n, p/params, c/columns, a/all
	';

	--handle case-sensitivity and nulls for string parameters
	SELECT 
		@help = LOWER(ISNULL(@help,N'all')),		--unlike the other parms, an invalid help still gets help info rather than raiserror
		@source = LOWER(ISNULL(@source,N'z')),
		@units = LOWER(ISNULL(@units,N'z')),
		@savespace = LOWER(ISNULL(@savespace,N'z')),
		@orderby = LOWER(ISNULL(@orderby,N'z')),
		@orderdir = LOWER(ISNULL(@orderdir,N'z'))
		;


	IF @help <> N'n'
	BEGIN
		GOTO helpbasic
	END

	IF @start IS NULL
	BEGIN
		SET @start = DATEADD(HOUR, -4, GETDATE());
		RAISERROR('Parameter @start set to 4 hours ago because a NULL value was supplied.', 10, 1) WITH NOWAIT;
	END

	IF @end IS NULL
	BEGIN
		SET @end = DATEADD(SECOND,-1, GETDATE());
		RAISERROR('Parameter @end set to 1 second ago because a NULL value was supplied.',10,1) WITH NOWAIT;
	END

	--Now that we have @start and @end values, replace our @lv__helpexec string with them
	SET @lv__helpexec = REPLACE(@lv__helpexec,'<start datetime>', REPLACE(CONVERT(NVARCHAR(20), @start, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @start, 108) + '.' + 
															RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @start)),3)
							);
	SET @lv__helpexec = REPLACE(@lv__helpexec,'<end datetime>', REPLACE(CONVERT(NVARCHAR(20), @end, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @end, 108) + '.' + 
															RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @end)),3)
							);

	SET @lv__StartUTC = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @start);
	SET @lv__EndUTC = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @end);

	--We use UTC for this check b/c of the DST "fall-back" scenario. We don't want to prevent a user from calling this proc for a timerange 
	--that already occurred (e.g. 1:30am-1:45am) at the second occurrence of 1:15am that day.
	IF @lv__StartUTC > GETUTCDATE() OR @lv__EndUTC > GETUTCDATE()
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Neither of the parameters @start or @end can be in the future.',16,1);
		RETURN -1;
	END
	
	IF @end <= @start
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Parameter @end cannot be <= to parameter @start', 16, 1);
		RETURN -1;
	END

	IF @source LIKE N't%'
	BEGIN
		SET @source = N'trace';
		SET @lv__CollectionInitiatorID = 255;	--use the standard historical data collected by @@CHIRHO_SCHEMA@@.AutoWho_Executor
	END
	ELSE IF @source LIKE N'%sv'
	BEGIN
		SET @source = N'pastsv';
		SET @lv__CollectionInitiatorID = 1;		--use the data collected by past calls to sp_XR_SessionViewer
	END
	ELSE IF @source LIKE N'%qp'
	BEGIN
		SET @source = N'pastqp';
		SET @lv__CollectionInitiatorID = 2;		--use the data collected by past calls to sp_XR_QueryProgress
	END
	ELSE
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Parameter @source must be either "trace" (historical data from standard AutoWho trace, default), "pastsv" (data from past sp_XR_SessionViewer executions), or "pastqp" (data from past sp_XR_QueryProgress executions).',16,1);
		RETURN -1;
	END

	IF @units LIKE N'm%'
	BEGIN
		SET @units = N'mb';
	END
	ELSE IF @units LIKE N'n%'
	BEGIN
		SET @units = N'native';
	END
	ELSE IF @units LIKE N'p%'
	BEGIN
		SET @units = N'pages';
	END
	ELSE
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Parameter @units must be either "mb" (megabytes, default), "native" (DMV native units), or "pages" (8kb pages).',16,1);
		RETURN -1;
	END

	IF @savespace NOT IN (N'n', N'y')
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Parameter @savespace must be either "n" (default) or "y"',16,1);
		RETURN -1;
	END

	IF ISNULL(@orderby,-1) < 1 OR ISNULL(@orderby,999) > 83
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Parameter @orderby must be an integer between 1 (default) and 83.',16,1);
		RETURN -1;
	END

	IF @orderdir NOT IN (N'a', N'd') 
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('Parameter @orderdir must be either "a" (ascending, default) or "d" (descending)',16,1);
		RETURN -1;
	END
	
	--If this is a summary run, check to see if there are any AutoWho.CaptureTime entries (in our @st/@et range) that haven't been 
	-- processed (into the @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary table) yet
	SELECT 
		@lv__numCaptures = ss.numCaptures,
		@lv__numNeedPopulation = ss.numNeedPopulation
	FROM (
		SELECT COUNT(*) as numCaptures,
			SUM(CASE WHEN t.CaptureSummaryPopulated = 0 OR t.CaptureSummaryDeltaPopulated = 0 THEN 1 ELSE 0 END) as numNeedPopulation
		FROM @@CHIRHO_DB@@.@@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes t
		WHERE t.CollectionInitiatorID = @lv__CollectionInitiatorID
		AND t.RunWasSuccessful = 1
		AND t.SPIDCaptureTime BETWEEN @start AND @end
	) ss
	;

	IF ISNULL(@lv__numCaptures,0) = 0
	BEGIN
		RAISERROR(@lv__helpexec,10,1);
		RAISERROR('
		***There is no capture data from AutoWho for the time range specified.',10,1) WITH NOWAIT;
		RETURN 0;
	END

	IF ISNULL(@lv__numNeedPopulation,0) > 0 
	BEGIN
		SET @scratch__int = NULL;
		EXEC @scratch__int = @@CHIRHO_DB@@.@@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummary @CollectionInitiatorID = @lv__CollectionInitiatorID, 
			@StartTime = @start, @EndTime = @end;
			--returns 0 if successful
			--returns 1 if there were 0 capture times for this range, which shouldn't happen since we just found CaptureSummaryPopulated > 0 rows
			--returns -1 if an error occurred (the error is logged to the AutoWho log

		IF @scratch__int IS NULL OR @scratch__int < 0
		BEGIN
			SET @err__msg = N'Unexpected error occurred while retrieving the AutoWho summary data. More info is available in the AutoWho log under the tag "SummCapturePopulation".'
			RAISERROR(@err__msg, 16, 1);
			RETURN -1;
		END
	END	--IF there are unprocessed capture times in the range


	--Determine our 
	IF @orderby IN (1,13,24,35,46,58,70,83)
	BEGIN
		SET @lv__orderByColumn = N'UTCCaptureTime';
	END
	ELSE
	BEGIN
		--These are all "raw" values, i.e. numbers, that are not visible in the
		-- final output but are available to be sorted by.
		SELECT @lv__orderByColumn = col1
		FROM (
			SELECT col1 = 
				CASE @orderby
					WHEN 2 THEN N'CapturedSPIDs'
					WHEN 3 THEN N'Active'
					WHEN 4 THEN N'ActLongest_ms'
					WHEN 5 THEN N'ActAvg_ms'
					WHEN 6 THEN N'Act0to1'
					WHEN 7 THEN N'Act1to5'
					WHEN 8 THEN N'Act5to10'
					WHEN 9 THEN N'Act10to30'
					WHEN 10 THEN N'Act30to60'
					WHEN 11 THEN N'Act60to300'
					WHEN 12 THEN N'Act300plus'
					WHEN 14 THEN N'IdleWithOpenTran'
					WHEN 15 THEN N'IdlOpTrnLongest_ms'
					WHEN 16 THEN N'IdlOpTrnAvg_ms'
					WHEN 17 THEN N'IdlOpTrn0to1'
					WHEN 18 THEN N'IdlOpTrn1to5'
					WHEN 19 THEN N'IdlOpTrn5to10'
					WHEN 20 THEN N'IdlOpTrn10to30'
					WHEN 21 THEN N'IdlOpTrn30to60'
					WHEN 22 THEN N'IdlOpTrn60to300'
					WHEN 23 THEN N'IdlOpTrn300plus'
					WHEN 25 THEN N'WithOpenTran'
					WHEN 26 THEN N'TranDurLongest_ms'
					WHEN 27 THEN N'TranDurAvg_ms'
					WHEN 28 THEN N'TranDur0to1'
					WHEN 29 THEN N'TranDur1to5'
					WHEN 30 THEN N'TranDur5to10'
					WHEN 31 THEN N'TranDur10to30'
					WHEN 32 THEN N'TranDur30to60'
					WHEN 33 THEN N'TranDur60to300'
					WHEN 34 THEN N'TranDur300plus'
					WHEN 36 THEN N'Blocked'
					WHEN 37 THEN N'BlockedLongest_ms_fmt'
					WHEN 38 THEN N'BlockedAvg_ms'
					WHEN 39 THEN N'Blocked0to1'
					WHEN 40 THEN N'Blocked1to5'
					WHEN 41 THEN N'Blocked5to10'
					WHEN 42 THEN N'Blocked10to30'
					WHEN 43 THEN N'Blocked30to60'
					WHEN 44 THEN N'Blocked60to300'
					WHEN 45 THEN N'Blocked300plus'
					WHEN 47 THEN N'WaitingSPIDs'
					WHEN 48 THEN N'WaitingTasks'
					WHEN 49 THEN N'WaitingTaskLongest_ms'
					WHEN 50 THEN N'WaitingTaskAvg_ms'
					WHEN 51 THEN N'WaitingTask0to1'
					WHEN 52 THEN N'WaitingTask1to5'
					WHEN 53 THEN N'WaitingTask5to10'
					WHEN 54 THEN N'WaitingTask10to30'
					WHEN 55 THEN N'WaitingTask30to60'
					WHEN 56 THEN N'WaitingTask60to300'
					WHEN 57 THEN N'WaitingTask300plus'
					WHEN 59 THEN N'TlogUsed_bytes'
					WHEN 60 THEN N'LargestLogWriter_bytes'
					WHEN 61 THEN N'QueryMemoryRequested_KB'
					WHEN 62 THEN N'QueryMemoryGranted_KB'
					WHEN 63 THEN N'LargestMemoryGrant_KB'
					WHEN 64 THEN N'TempDB_pages'
					WHEN 65 THEN N'LargestTempDBConsumer_pages'
					WHEN 66 THEN N'CPUused'
					WHEN 67 THEN N'CPUDelta'
					WHEN 68 THEN N'LargestCPUConsumer'
					WHEN 69 THEN N'AllocatedTasks'
					WHEN 71 THEN N'WritesDone'
					WHEN 72 THEN N'WritesDelta'
					WHEN 73 THEN N'LargestWriter'
					WHEN 74 THEN N'LogicalReadsDone'
					WHEN 75 THEN N'LogicalReadsDelta'
					WHEN 76 THEN N'LargestLogicalReader'
					WHEN 77 THEN N'PhysicalReadsDone'
					WHEN 78 THEN N'PhysicalReadsDelta'
					WHEN 79 THEN N'LargestPhysicalReader'
					WHEN 80 THEN N'BlockingGraph'
					WHEN 81 THEN N'LockDetails'
					WHEN 82 THEN N'TranDetails'
				ELSE N'error'
				END
		) ss;
	END


	--	Group 1: Active spids
	SET @lv__DynSQL = N'
	SELECT 
		SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [1_SPIDCaptureTime]' END + N' 
		,CapturedSPIDs' + CASE WHEN @savespace = N'y' THEN N' as [#SPIDs]' ELSE N' as [2_TotCapturedSPIDs]' END + N' 
		,CASE WHEN Active=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Active) END' + CASE WHEN @savespace = N'y' THEN N' as [Act]' ELSE N' as [3_Active]' END + N'
		,CASE WHEN ISNULL(ActLongest_ms,0) <= 0 THEN N'''' 
			ELSE (CASE WHEN ActLongest_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (ActLongest_ms/1000) / 86400) + N''~'' +			--day
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((ActLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActLongest_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN ActLongest_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(ActLongest_ms/1000) / 86400)),1,2)) + N''~'' +			--day
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((ActLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN ActLongest_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((ActLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(ActLongest_ms_fmt, 1, CHARINDEX(''.'',ActLongest_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [MaxAct]' ELSE N' as [4_MaxActive]' END;

	SET @lv__DynSQL = @lv__DynSQL + N' 
	,CASE WHEN ISNULL(ActAvg_ms,0) <= 0 THEN N'''' 
			ELSE (CASE WHEN ActAvg_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (ActAvg_ms/1000) / 86400) + N''~'' +			--day
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((ActAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActAvg_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN ActAvg_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(ActAvg_ms/1000) / 86400)),1,2)) + N''~'' +			--day
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((ActAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN ActAvg_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((ActAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
					REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((ActAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(ActAvg_ms_fmt, 1, CHARINDEX(''.'',ActAvg_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [AvgAct]' ELSE N' as [5_AvgActive]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(Act0to1,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act0to1) END' + CASE WHEN @savespace=N'y' THEN N' as [0to1]' ELSE N' as [6_Act0to1]' END + N'
		,CASE WHEN ISNULL(Act1to5,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act1to5) END' + CASE WHEN @savespace=N'y' THEN N' as [1to5]' ELSE N' as [7_Act1to5]' END + N'
		,CASE WHEN ISNULL(Act5to10,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act5to10) END' + CASE WHEN @savespace=N'y' THEN N' as [5to10]' ELSE N' as [8_Act5to10]' END + N'
		,CASE WHEN ISNULL(Act10to30,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act10to30) END' + CASE WHEN @savespace=N'y' THEN N' as [10to30]' ELSE N' as [9_Act10to30]' END + N'
		,CASE WHEN ISNULL(Act30to60,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act30to60) END' + CASE WHEN @savespace=N'y' THEN N' as [30to60]' ELSE N' as [10_Act30to60]' END + N'
		,CASE WHEN ISNULL(Act60to300,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act60to300) END' + CASE WHEN @savespace=N'y' THEN N' as [60to300]' ELSE N' as [11_Act60to300]' END + N'
		,CASE WHEN ISNULL(Act300plus,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Act300plus) END' + CASE WHEN @savespace=N'y' THEN N' as [300plus]' ELSE N' as [12_Act300plus]' END + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [13_SPIDCaptureTime]' END + N'
	';


	--	Group 2: Idle spids with open trans
	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(IdleWithOpenTran,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdleWithOpenTran) END' + CASE WHEN @savespace = N'y' THEN N' as [IdlTrn]' ELSE N' as [14_IdleTran]' END + N'
		,CASE WHEN ISNULL(IdlOpTrnLongest_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN IdlOpTrnLongest_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (IdlOpTrnLongest_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((IdlOpTrnLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnLongest_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN IdlOpTrnLongest_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(IdlOpTrnLongest_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((IdlOpTrnLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN IdlOpTrnLongest_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((IdlOpTrnLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(IdlOpTrnLongest_ms_fmt, 1, CHARINDEX(''.'',IdlOpTrnLongest_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [MaxIdlTrn]' ELSE N' as [15_MaxIdleTran]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
	,CASE WHEN ISNULL(IdlOpTrnAvg_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN IdlOpTrnAvg_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (IdlOpTrnAvg_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((IdlOpTrnAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnAvg_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN IdlOpTrnAvg_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(IdlOpTrnAvg_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((IdlOpTrnAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN IdlOpTrnAvg_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((IdlOpTrnAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((IdlOpTrnAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(IdlOpTrnAvg_ms_fmt, 1, CHARINDEX(''.'',IdlOpTrnAvg_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [AvgIdlTrn]' ELSE N' as [16_AvgIdleTran]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(IdlOpTrn0to1,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn0to1) END' + CASE WHEN @savespace=N'y' THEN N' as [0to1]' ELSE N' as [17_IdlTrn0to1]' END + N'
		,CASE WHEN ISNULL(IdlOpTrn1to5,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn1to5) END' + CASE WHEN @savespace=N'y' THEN N' as [1to5]' ELSE N' as [18_IdlTrn1to5]' END + N'
		,CASE WHEN ISNULL(IdlOpTrn5to10,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn5to10) END' + CASE WHEN @savespace=N'y' THEN N' as [5to10]' ELSE N' as [19_IdlTrn5to10]' END + N'
		,CASE WHEN ISNULL(IdlOpTrn10to30,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn10to30) END' + CASE WHEN @savespace=N'y' THEN N' as [10to30]' ELSE N' as [20_IdlTrn10to30]' END + N'
		,CASE WHEN ISNULL(IdlOpTrn30to60,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn30to60) END' + CASE WHEN @savespace=N'y' THEN N' as [30to60]' ELSE N' as [21_IdlTrn30to60]' END + N'
		,CASE WHEN ISNULL(IdlOpTrn60to300,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn60to300) END' + CASE WHEN @savespace=N'y' THEN N' as [60to300]' ELSE N' as [22_IdlTrn60to300]' END + N'
		,CASE WHEN ISNULL(IdlOpTrn300plus,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),IdlOpTrn300plus) END' + CASE WHEN @savespace=N'y' THEN N' as [300plus]' ELSE N' as [23_IdlTrn300plus]' END + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [24_SPIDCaptureTime]' END + N'
	';

	--	Group 3: Open Trans (both active and idle spids)
	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(WithOpenTran,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20),WithOpenTran) END' + CASE WHEN @savespace = N'y' THEN N' as [OpTrn]' ELSE N' as [25_OpenTran]' END + N'
		,CASE WHEN ISNULL(TranDurLongest_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN TranDurLongest_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (TranDurLongest_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((TranDurLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurLongest_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN TranDurLongest_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(TranDurLongest_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((TranDurLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN TranDurLongest_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((TranDurLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(TranDurLongest_ms_fmt, 1, CHARINDEX(''.'',TranDurLongest_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [MaxTrn]' ELSE N' as [26_MaxTran]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
	,CASE WHEN ISNULL(TranDurAvg_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN TranDurAvg_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (TranDurAvg_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((TranDurAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurAvg_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN TranDurAvg_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(TranDurAvg_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((TranDurAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN TranDurAvg_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((TranDurAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((TranDurAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(TranDurAvg_ms_fmt, 1, CHARINDEX(''.'',TranDurAvg_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [AvgTrn]' ELSE N' as [27_AvgTran]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(TranDur0to1,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur0to1) END' + CASE WHEN @savespace=N'y' THEN N' as [0to1]' ELSE N' as [28_TranDur0to1]' END + N'
		,CASE WHEN ISNULL(TranDur1to5,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur1to5) END' + CASE WHEN @savespace=N'y' THEN N' as [1to5]' ELSE N' as [29_TranDur1to5]' END + N'
		,CASE WHEN ISNULL(TranDur5to10,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur5to10) END' + CASE WHEN @savespace=N'y' THEN N' as [5to10]' ELSE N' as [30_TranDur5to10]' END + N'
		,CASE WHEN ISNULL(TranDur10to30,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur10to30) END' + CASE WHEN @savespace=N'y' THEN N' as [10to30]' ELSE N' as [31_TranDur10to30]' END + N'
		,CASE WHEN ISNULL(TranDur30to60,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur30to60) END' + CASE WHEN @savespace=N'y' THEN N' as [30to60]' ELSE N' as [32_TranDur30to60]' END + N'
		,CASE WHEN ISNULL(TranDur60to300,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur60to300) END' + CASE WHEN @savespace=N'y' THEN N' as [60to300]' ELSE N' as [33_TranDur60to300]' END + N'
		,CASE WHEN ISNULL(TranDur300plus,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),TranDur300plus) END' + CASE WHEN @savespace=N'y' THEN N' as [300plus]' ELSE N' as [34_TranDur300plus]' END + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [35_SPIDCaptureTime]' END + N'
	';

	--Group 4: Blocked spids
	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(Blocked,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked) END' + CASE WHEN @savespace = N'y' THEN N' as [Blkd]' ELSE N' as [36_Blocked]' END + N'
		,CASE WHEN ISNULL(BlockedLongest_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN BlockedLongest_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (BlockedLongest_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((BlockedLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedLongest_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN BlockedLongest_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(BlockedLongest_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((BlockedLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN BlockedLongest_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((BlockedLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(BlockedLongest_ms_fmt, 1, CHARINDEX(''.'',BlockedLongest_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [MaxBlk]' ELSE N' as [37_MaxBlockedTask]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
	,CASE WHEN ISNULL(BlockedAvg_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN BlockedAvg_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (BlockedAvg_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((BlockedAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedAvg_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN BlockedAvg_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(BlockedAvg_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((BlockedAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN BlockedAvg_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((BlockedAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((BlockedAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(BlockedAvg_ms_fmt, 1, CHARINDEX(''.'',BlockedAvg_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [AvgBlk]' ELSE N' as [38_AvgBlockedTask]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(Blocked0to1,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked0to1) END' + CASE WHEN @savespace=N'y' THEN N' as [0to1]' ELSE N' as [39_Blocked0to1]' END + N'
		,CASE WHEN ISNULL(Blocked1to5,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked1to5) END' + CASE WHEN @savespace=N'y' THEN N' as [1to5]' ELSE N' as [40_Blocked1to5]' END + N'
		,CASE WHEN ISNULL(Blocked5to10,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked5to10) END' + CASE WHEN @savespace=N'y' THEN N' as [5to10]' ELSE N' as [41_Blocked5to10]' END + N'
		,CASE WHEN ISNULL(Blocked10to30,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked10to30) END' + CASE WHEN @savespace=N'y' THEN N' as [10to30]' ELSE N' as [42_Blocked10to30]' END + N'
		,CASE WHEN ISNULL(Blocked30to60,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked30to60) END' + CASE WHEN @savespace=N'y' THEN N' as [30to60]' ELSE N' as [43_Blocked30to60]' END + N'
		,CASE WHEN ISNULL(Blocked60to300,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked60to300) END' + CASE WHEN @savespace=N'y' THEN N' as [60to300]' ELSE N' as [44_Blocked60to300]' END + N'
		,CASE WHEN ISNULL(Blocked300plus,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),Blocked300plus) END' + CASE WHEN @savespace=N'y' THEN N' as [300plus]' ELSE N' as [45_Blocked300plus]' END + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [46_SPIDCaptureTime]' END + N'
	';

	--Group 5: waiting (Unlike SQL Server standard terminology, "waiting" here means not blocked by another spid, but not able to progress)
	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(WaitingSPIDs,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20),WaitingSPIDs) END' + CASE WHEN @savespace = N'y' THEN N' as [WtSPIDs]' ELSE N' as [47_WaitingSPIDs]' END + N'
		,CASE WHEN ISNULL(WaitingTasks,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20), WaitingTasks) END' + CASE WHEN @savespace = N'y' THEN N' as [WtTsk]' ELSE N' as [48_WaitingTasks]' END + N'
		,CASE WHEN ISNULL(WaitingTaskLongest_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN WaitingTaskLongest_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (WaitingTaskLongest_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((WaitingTaskLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskLongest_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN WaitingTaskLongest_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(WaitingTaskLongest_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((WaitingTaskLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN WaitingTaskLongest_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((WaitingTaskLongest_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskLongest_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskLongest_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(WaitingTaskLongest_ms_fmt, 1, CHARINDEX(''.'',WaitingTaskLongest_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [MaxWtTsk]' ELSE N' as [49_MaxWaitingTask]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
	,CASE WHEN ISNULL(WaitingTaskAvg_ms,0) = 0 THEN N'''' 
			ELSE (CASE WHEN WaitingTaskAvg_ms > 863999999 THEN N''(!!) '' + CONVERT(NVARCHAR(20), (WaitingTaskAvg_ms/1000) / 86400) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((WaitingTaskAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskAvg_ms/1000) % 86400)%3600)%60)),1,2)) 					--second

			WHEN WaitingTaskAvg_ms > 86399999 THEN N''(!) '' + REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(WaitingTaskAvg_ms/1000) / 86400)),1,2)) + N''~'' +			--day
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((WaitingTaskAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second

			WHEN WaitingTaskAvg_ms > 59999 THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),((WaitingTaskAvg_ms/1000) % 86400)/3600)),1,2)) + N'':'' +			--hour
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskAvg_ms/1000) % 86400)%3600)/60)),1,2)) + N'':'' +			--minute
				REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(NVARCHAR(20),(((WaitingTaskAvg_ms/1000) % 86400)%3600)%60)),1,2)) 			--second
			ELSE SUBSTRING(WaitingTaskAvg_ms_fmt, 1, CHARINDEX(''.'',WaitingTaskAvg_ms_fmt)-1)
			END)
		END' + CASE WHEN @savespace = N'y' THEN N' as [AvgWtTsk]' ELSE N' as [50_AvgWaitingTask]' END;

	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(WaitingTask0to1,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),   WaitingTask0to1) END' + CASE WHEN @savespace=N'y' THEN N' as [0to1]' ELSE N' as [51_WaitingTask0to1]' END + N'
		,CASE WHEN ISNULL(WaitingTask1to5,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),   WaitingTask1to5) END' + CASE WHEN @savespace=N'y' THEN N' as [1to5]' ELSE N' as [52_WaitingTask1to5]' END + N'
		,CASE WHEN ISNULL(WaitingTask5to10,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),  WaitingTask5to10) END' + CASE WHEN @savespace=N'y' THEN N' as [5to10]' ELSE N' as [53_WaitingTask5to10]' END + N'
		,CASE WHEN ISNULL(WaitingTask10to30,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20), WaitingTask10to30) END' + CASE WHEN @savespace=N'y' THEN N' as [10to30]' ELSE N' as [54_WaitingTask10to30]' END + N'
		,CASE WHEN ISNULL(WaitingTask30to60,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20), WaitingTask30to60) END' + CASE WHEN @savespace=N'y' THEN N' as [30to60]' ELSE N' as [55_WaitingTask30to60]' END + N'
		,CASE WHEN ISNULL(WaitingTask60to300,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),WaitingTask60to300) END' + CASE WHEN @savespace=N'y' THEN N' as [60to300]' ELSE N' as [56_WaitingTask60to300]' END + N'
		,CASE WHEN ISNULL(WaitingTask300plus,0)=0 THEN N'''' ELSE CONVERT(NVARCHAR(20),WaitingTask300plus) END' + CASE WHEN @savespace=N'y' THEN N' as [300plus]' ELSE N' as [57_WaitingTask300plus]' END + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [58_SPIDCaptureTime]' END + N'
	';

	--Group 6: Resources #1
	-- We need to take the @units into account to determine whether we are trimming decimal places or not
	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(TlogUsed_bytes,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native') THEN N'REPLACE(TlogUsed_fmt, N''.00'', N'''')'
					ELSE N'TlogUsed_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [Tlog]' ELSE N' as [59_TLogUsed]' END + N'
		,CASE WHEN ISNULL(LargestLogWriter_bytes,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native') THEN N'REPLACE(LargestLogWriter_fmt, N''.00'', N'''')'
					ELSE N'LargestLogWriter_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [MaxTlog]' ELSE N' as [60_MaxLogUsed]' END + N' 
		,CASE WHEN ISNULL(QueryMemoryRequested_KB,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native') THEN N'REPLACE(QueryMemoryRequested_fmt, N''.00'', N'''')'
					ELSE N'QueryMemoryRequested_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [QMReq]' ELSE N' as [61_QMemReq]' END + N'
		,CASE WHEN ISNULL(QueryMemoryGranted_KB,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native') THEN N'REPLACE(QueryMemoryGranted_fmt, N''.00'', N'''')'
					ELSE N'QueryMemoryGranted_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [QMGr]' ELSE N' as [62_QMemGrant]' END + N'
		,CASE WHEN ISNULL(LargestMemoryGrant_KB,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native') THEN N'REPLACE(LargestMemoryGrant_fmt, N''.00'', N'''')'
					ELSE N'LargestMemoryGrant_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [MaxQMGr]' ELSE N' as [63_MaxQMemGrant]' END + N'
		,CASE WHEN ISNULL(TempDB_pages,0) = 0 THEN N'''' ELSE ' +
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(TempDB_fmt, N''.00'', N'''')'
					ELSE N'TempDB_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [Tdb]' ELSE N' as [64_TempDB]' END + N'
		,CASE WHEN ISNULL(LargestTempDBConsumer_pages,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(LargestTempDBConsumer_fmt, N''.00'', N'''')'
					ELSE N'LargestTempDBConsumer_fmt'
				END + N' END' + 		
				CASE WHEN @savespace = N'y' THEN N' as [MaxTdb]' ELSE N' as [65_MaxTempDB]' END + N'
		,CASE WHEN ISNULL(CPUused,0) = 0 THEN N'''' ELSE REPLACE(CPUused_fmt, N''.00'', N'''') END' + CASE WHEN @savespace = N'y' THEN N' as [CPU]' ELSE N' as [66_CPUused]' END + N'
		,CASE WHEN ISNULL(CPUDelta,0) = 0 THEN N'''' ELSE REPLACE(CPUDelta_fmt, N''.00'', N'''') END' + CASE WHEN @savespace = N'y' THEN N' as [CPUDelt]' ELSE N' as [67_CPUDelta]' END + N'
		,CASE WHEN ISNULL(LargestCPUConsumer,0) = 0 THEN N'''' ELSE REPLACE(LargestCPUConsumer_fmt, N''.00'', N'''') END' + CASE WHEN @savespace = N'y' THEN N' as [MaxCPU]' ELSE N' as [68_MaxCPUused]' END + N'
		,CASE WHEN ISNULL(AllocatedTasks,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20),AllocatedTasks) END' + CASE WHEN @savespace = N'y' THEN N' as [Tasks]' ELSE N' as [69_UserTasks]' END


	--Group 7: Resources #2
	-- We need to take the @units into account to determine whether we are trimming decimal places or not
	SET @lv__DynSQL = @lv__DynSQL + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [70_SPIDCaptureTime]' END + N'
		,CASE WHEN ISNULL(WritesDone,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(WritesDone_fmt, N''.00'', N'''')'
					ELSE N'WritesDone_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [Wri]' ELSE N' as [71_Write]' END + N'
		,CASE WHEN ISNULL(WritesDelta,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(WritesDelta_fmt, N''.00'', N'''')'
					ELSE N'WritesDelta_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [WriDelt]' ELSE N' as [72_WritesDelta]' END + N'
		,CASE WHEN ISNULL(LargestWriter,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(LargestWriter_fmt, N''.00'', N'''')'
					ELSE N'LargestWriter_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [MaxWri]' ELSE N' as [73_MaxWriter]' END + N' 
		,CASE WHEN ISNULL(LogicalReadsDone,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(LogicalReadsDone_fmt, N''.00'', N'''')'
					ELSE N'LogicalReadsDone_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [LRds]' ELSE N' as [74_LReads]' END + N'
		,CASE WHEN ISNULL(LogicalReadsDelta,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(LogicalReadsDelta_fmt, N''.00'', N'''')'
					ELSE N'LogicalReadsDelta_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [LRDelt]' ELSE N' as [75_LReadsDelta]' END + N'
		,CASE WHEN ISNULL(LargestLogicalReader,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(LargestLogicalReader_fmt, N''.00'', N'''')'
					ELSE N'LargestLogicalReader_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [MaxLRd]' ELSE N' as [76_MaxLReader]' END + N'
		,CASE WHEN ISNULL(PhysicalReadsDone,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(PhysicalReadsDone_fmt, N''.00'', N'''')'
					ELSE N'PhysicalReadsDone_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [PRds]' ELSE N' as [77_PReads]' END + N'
		,CASE WHEN ISNULL(PhysicalReadsDelta,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(PhysicalReadsDelta_fmt, N''.00'', N'''')'
					ELSE N'PhysicalReadsDelta_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [PRDelt]' ELSE N' as [78_PReadsDelta]' END + N'
		,CASE WHEN ISNULL(LargestPhysicalReader,0) = 0 THEN N'''' ELSE ' + 
				CASE WHEN @units IN (N'native', N'pages') THEN N'REPLACE(LargestPhysicalReader_fmt, N''.00'', N'''')'
					ELSE N'LargestPhysicalReader_fmt'
				END + N' END' + 
				CASE WHEN @savespace = N'y' THEN N' as [MaxPRd]' ELSE N' as [79_MaxPReader]' END
		
	SET @lv__DynSQL = @lv__DynSQL + N'
		,CASE WHEN ISNULL(BlockingGraph,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20), BlockingGraph) END' + CASE WHEN @savespace = N'y' THEN N' as [hasBG]' ELSE N' as [80_HasBlockingGraph]' END + N'
		,CASE WHEN ISNULL(LockDetails,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20), LockDetails) END ' + CASE WHEN @savespace = N'y' THEN N' as [hasLck]' ELSE N' as [81_HasLockDetails]' END + N'
		,CASE WHEN ISNULL(TranDetails,0) = 0 THEN N'''' ELSE CONVERT(NVARCHAR(20), TranDetails) END ' + CASE WHEN @savespace = N'y' THEN N' as [hasTrnD]' ELSE N' as [82_HasTranDetails]' END + N'
		,SPIDCaptureTime' + CASE WHEN @savespace = N'y' THEN N' as SCT' ELSE N' as [83_SPIDCaptureTime]' END + N' 
	FROM (
		SELECT CollectionInitiatorID, UTCCaptureTime, SPIDCaptureTime, CapturedSPIDs, 
			Active, ActLongest_ms, ActAvg_ms, Act0to1, Act1to5, Act5to10, Act10to30, Act30to60, Act60to300, Act300plus, 
				ActLongest_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,ActLongest_ms),1), 
				ActAvg_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,ActAvg_ms),1), 
			IdleWithOpenTran, IdlOpTrnLongest_ms, IdlOpTrnAvg_ms, IdlOpTrn0to1, IdlOpTrn1to5, IdlOpTrn5to10, IdlOpTrn10to30, IdlOpTrn30to60, IdlOpTrn60to300, IdlOpTrn300plus, 
				IdlOpTrnLongest_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,IdlOpTrnLongest_ms),1),
				IdlOpTrnAvg_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,IdlOpTrnAvg_ms),1), 
			WithOpenTran, TranDurLongest_ms, TranDurAvg_ms, TranDur0to1, TranDur1to5, TranDur5to10, TranDur10to30, TranDur30to60, TranDur60to300, TranDur300plus, 
				TranDurLongest_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,TranDurLongest_ms),1),
				TranDurAvg_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,TranDurAvg_ms),1), 
			Blocked, BlockedLongest_ms, BlockedAvg_ms, Blocked0to1, Blocked1to5, Blocked5to10, Blocked10to30, Blocked30to60, Blocked60to300, Blocked300plus, 
				BlockedLongest_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,BlockedLongest_ms),1),
				BlockedAvg_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,BlockedAvg_ms),1), 
			WaitingSPIDs, WaitingTasks, WaitingTaskLongest_ms, WaitingTaskAvg_ms, WaitingTask0to1, WaitingTask1to5, WaitingTask5to10, WaitingTask10to30, WaitingTask30to60, WaitingTask60to300, WaitingTask300plus, 
				WaitingTaskLongest_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,WaitingTaskLongest_ms),1),
				WaitingTaskAvg_ms_fmt = CONVERT(NVARCHAR(20),CONVERT(money,WaitingTaskAvg_ms),1), 
			AllocatedTasks, BlockingGraph, LockDetails, TranDetails,
			CPUused, CPUDelta, LargestCPUConsumer,
				CPUused_fmt = CONVERT(NVARCHAR(20),CONVERT(money,CPUused),1),
				CPUDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,CPUDelta),1), 
				LargestCPUConsumer_fmt = CONVERT(NVARCHAR(20),CONVERT(money,LargestCPUConsumer),1),

			--needed for comparison w/0 in the above T-SQL
			QueryMemoryRequested_KB, QueryMemoryGranted_KB, LargestMemoryGrant_KB, TempDB_pages, LargestTempDBConsumer_pages,
			PhysicalReadsDone, PhysicalReadsDelta, LargestPhysicalReader, LogicalReadsDone, LogicalReadsDelta, LargestLogicalReader,
			WritesDone, WritesDelta, LargestWriter, TlogUsed_bytes, LargestLogWriter_bytes,
	';

	IF @units = N'mb'
	BEGIN
		SET @lv__DynSQL = @lv__DynSQL + N'
		QueryMemoryRequested_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   QueryMemoryRequested_KB/1024.   ),1),
		QueryMemoryGranted_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   QueryMemoryGranted_KB/1024.   ),1),
		LargestMemoryGrant_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestMemoryGrant_KB/1024.   ),1),

		TempDB_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   TempDB_pages*8./1024.   ),1),
		LargestTempDBConsumer_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestTempDBConsumer_pages*8./1024.   ),1),

		PhysicalReadsDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   PhysicalReadsDone*8./1024.   ),1),
		PhysicalReadsDelta_fmt =  CONVERT(NVARCHAR(20),CONVERT(money,   PhysicalReadsDelta*8./1024.   ),1),
		LargestPhysicalReader_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestPhysicalReader*8./1024.   ),1),

		LogicalReadsDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LogicalReadsDone*8./1024.   ),1),
		LogicalReadsDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LogicalReadsDelta*8./1024.   ),1),
		LargestLogicalReader_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestLogicalReader*8./1024.   ),1),

		WritesDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   WritesDone*8./1024.   ),1),
		WritesDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   WritesDelta*8./1024.   ),1),
		LargestWriter_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestWriter*8./1024.  ),1),

		TLogUsed_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   TlogUsed_bytes/1024./1024.   ),1),
		LargestLogWriter_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestLogWriter_bytes/1024./1024.   ),1)
		';
	END
	ELSE IF @units = N'native'
	BEGIN
		SET @lv__DynSQL = @lv__DynSQL + N'
		QueryMemoryRequested_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   QueryMemoryRequested_KB   ),1),
		QueryMemoryGranted_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   QueryMemoryGranted_KB   ),1),
		LargestMemoryGrant_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestMemoryGrant_KB   ),1),

		TempDB_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   TempDB_pages   ),1),
		LargestTempDBConsumer_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestTempDBConsumer_pages   ),1),

		PhysicalReadsDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   PhysicalReadsDone   ),1),
		PhysicalReadsDelta_fmt =  CONVERT(NVARCHAR(20),CONVERT(money,   PhysicalReadsDelta   ),1),
		LargestPhysicalReader_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestPhysicalReader   ),1),

		LogicalReadsDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LogicalReadsDone   ),1),
		LogicalReadsDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LogicalReadsDelta   ),1),
		LargestLogicalReader_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestLogicalReader   ),1),

		WritesDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   WritesDone   ),1),
		WritesDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   WritesDelta   ),1),
		LargestWriter_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestWriter  ),1),

		TLogUsed_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   TlogUsed_bytes   ),1),
		LargestLogWriter_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestLogWriter_bytes   ),1)
		';
	END
	ELSE	--pages
	BEGIN
		SET @lv__DynSQL = @lv__DynSQL + N'
		QueryMemoryRequested_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   QueryMemoryRequested_KB/8.   ),1),
		QueryMemoryGranted_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   QueryMemoryGranted_KB/8.   ),1),
		LargestMemoryGrant_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestMemoryGrant_KB/8.   ),1),

		TempDB_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   TempDB_pages   ),1),
		LargestTempDBConsumer_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestTempDBConsumer_pages   ),1),

		PhysicalReadsDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   PhysicalReadsDone   ),1),
		PhysicalReadsDelta_fmt =  CONVERT(NVARCHAR(20),CONVERT(money,   PhysicalReadsDelta   ),1),
		LargestPhysicalReader_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestPhysicalReader   ),1),

		LogicalReadsDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LogicalReadsDone   ),1),
		LogicalReadsDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LogicalReadsDelta   ),1),
		LargestLogicalReader_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestLogicalReader   ),1),

		WritesDone_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   WritesDone   ),1),
		WritesDelta_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   WritesDelta   ),1),
		LargestWriter_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestWriter  ),1),

		TLogUsed_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   TlogUsed_bytes/8192.   ),1),
		LargestLogWriter_fmt = CONVERT(NVARCHAR(20),CONVERT(money,   LargestLogWriter_bytes/8192.   ),1)
		';
	END


	SET @lv__DynSQL = @lv__DynSQL + N'
		FROM @@CHIRHO_DB@@.@@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary t
		WHERE t.CollectionInitiatorID = ' + CONVERT(NVARCHAR(20),@lv__CollectionInitiatorID) + N'
		AND t.SPIDCaptureTime BETWEEN @start AND @end
		) t
	ORDER BY ' + @lv__orderByColumn + N' ' + 

		CASE WHEN @orderdir = N'd' THEN N'desc' ELSE N'' END + 

		--Are we ordering by time secondarily?
		CASE WHEN @lv__orderByColumn <> N'UTCCaptureTime' THEN N',UTCCaptureTime ASC' ELSE N'' END + N'
	;
	';

	/* For debugging: 
		SELECT dyntxt, TxtLink
		from (SELECT @lv__DynSQL AS dyntxt) t0
			cross apply (select TxtLink=(select [processing-instruction(q)]=dyntxt
                            for xml path(''),type)) F2
	*/
	EXEC sp_executesql @stmt = @lv__DynSQL,	@params = N'@start DATETIME, @end DATETIME', @start = @start, @end = @end;

	--we always print out at least the EXEC command
	GOTO helpbasic


helpbasic:

	IF @help <> N'n'
	BEGIN
		IF @help LIKE N'p%'
		BEGIN
			SET @help = N'params'
		END
		ELSE IF @help LIKE N'c%'
		BEGIN
			SET @help = N'columns'
		END
		ELSE
		BEGIN	--user may have typed gibberish... which is ok, give him/her all the help
			SET @help = N'all'
		END
	END

	--Because we may have arrived here from a GOTO very early in the proc, we need to set @start & @end
	IF @start IS NULL 
	BEGIN
		SET @start = DATEADD(HOUR, -4, GETDATE());
	END

	IF @end IS NULL
	BEGIN
		SET @end = GETDATE();
	END

	SET @lv__helpexec = REPLACE(@lv__helpexec,'<start datetime>', REPLACE(CONVERT(NVARCHAR(20), @start, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @start, 108) + '.' + 
															RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @start)),3)
							);
	SET @lv__helpexec = REPLACE(@lv__helpexec,'<end datetime>', REPLACE(CONVERT(NVARCHAR(20), @end, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @end, 108) + '.' + 
															RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @end)),3)
							);



	SET @lv__helpstr = @lv__helpexec;
	RAISERROR(@lv__helpstr,10,1) WITH NOWAIT;
	
	IF @help = N'n'
	BEGIN
		--because the user is likely to use sp_SessionViewer next, if they haven't asked for help explicitly, we print out the syntax for 
		--the Session Viewer procedure

		SET @lv__helpstr = '
EXEC sp_XR_SessionViewer @start=''' + REPLACE(CONVERT(NVARCHAR(20), @start, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @start, 108) + '.' + 
		RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @start)),3) + ''',@end=''' + 
		REPLACE(CONVERT(NVARCHAR(20), @end, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @end, 108) + '.' + 
		RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @end)),3) + ''', --@offset=99999,
	@source=N''trace'',@activity=1, @dur=0,@dbs=N'''',@xdbs=N'''',@spids=N'''',@xspids=N'''',
	@blockonly=N''N'',@attr=N''N'',@resources=N''N'',@batch=N''N'',@plan=N''none'',	--none, statement, full
	@ibuf=N''N'',@bchain=0,@tran=N''N'',@waits=0,		--bchain 0-10, waits 0-3
	@savespace=N''N'',@directives=N''''		--"query(ies)"
	';

		print @lv__helpstr;
		RETURN 0;
	END

	SET @lv__helpstr = N'
ChiRho version 2008R2.1

Key Concepts and Terminology
-------------------------------------------------------------------------------------------------------------------------------------------
sp_XR_SessionSummary displays data from AutoWho, a subcomponent of the ChiRho toolkit that snapshots (by default, every 15 seconds) the 
session-centric DMVs and stores the results in tables in the AutoWho schema. sp_XR_SessionSummary aggregates and displays one row per 
AutoWho snapshot (called a "capture"), giving the user a quick summary of what was/wasn''t occurring in the session-centric DMVs at that
point in time. A user can quickly review a window of time looking for problems in blocking, resource utilization, long transactions, or long 
queries. This proc also has cousins: 

	- sp_XR_SessionViewer: shows a single AutoWho capture at a time, giving the user details on actively-running queries, blocking,
						   resource usage, session/connection attributes, and query plans for a particular point in time.

	- sp_XR_LongRequests: searches a time window and identifies longer-running requests, aggregating data up to the individual statements
						  executed by that request (at least as observed by AutoWho snapshotting). This gives the user the ability to
						  review a long-running request/batch to identify the problem statements or compare between "good" and "bad runs.

	- sp_XR_FrequentQueries: searches a time window and identifies frequently-run queries (and input buffers for idle spids), and aggregates
							 statistics for those high-frequency results. This gives the user the ability to identify commonly-observed
							 statements or pauses in transactions and compare between "good" and "bad" windows of time.';
	RAISERROR(@lv__helpstr,10,1);
	SET @lv__helpstr = N'
On a typical install of ChiRho, the AutoWho code typically executes in the context of a background trace, polling every 15 seconds. However, 
the same AutoWho collection code can be run by sp_XR_SessionViewer whenever it is running in "current mode". Regardless of which method is 
used to collect AutoWho data, it is always stored in AutoWho tables. Thus, even a "current mode" run of sp_XR_SessionViewer stores data from 
the DMVs into AutoWho tables before displaying to the user. A tag in the AutoWho tables is used to differentiate which method of collection was 
used for each capture, essentially partitioning (logically) the data into different "sets". The @source parameter allows the user to target these 
different sets.
	';
	RAISERROR(@lv__helpstr,10,1);

	IF @help NOT IN (N'params',N'all')
	BEGIN
		GOTO helpcolumns
	END

helpparams:
	SET @lv__helpstr = N'
Parameters (all string parameters are case-insensitive regardless of server collation)
-------------------------------------------------------------------------------------------------------------------------------------------
@start			Valid Values: NULL, any datetime value in the past

				Defines the start time of the time window/range used to pull & display AutoWho capture summaries from the AutoWho database. 
				The time cannot be in the future, and must be < @end. If NULL is passed, the time defaults to 4 hours before the current time 
				[ DATEADD(hour, -4, GETDATE()) ]
	
@end			Valid Values: NULL, any datetime in the past

				Defines the end time of the time window/range used. The time cannot be in the future, and must be > @start. If NULL is passed, 
				the time defaults to 1 second before the current time. [ DATEADD(second, -1, GETDATE()) ]

@source			Valid Values: "t" or "trace" (default), "sv" or "pastsv", "qp" or "pastqp" (all case-insensitive)

				As mentioned above, AutoWho code is used to capture DMV data whether the background trace is doing the collecting or 
				sp_XR_SessionViewer are collecting the live data and returning to the user. @source allows the user to point to either data 
				collected by the standard background trace (using "trace"), to data collected by past sp_XR_SessionViewer runs ("pastsv") 
				or to data collected by past sp_XR_QueryProgress runs ("pastqp"). Most of the time, the default value "trace" returns the 
				data desired.';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
@units			Valid Values: "m" or "mb" (default), "n" or "native", "p" or "pages"

				Controls the units the following columns: "59_TLogUsed", "60_MaxLogUsed", "61_QMemReq", "62_QMemGrant",
					"63_MaxQMemGrant", "64_TempDB", "65_MaxTempDB", "71_Writes", "72_WritesDelta", "73_MaxWriter",
					"74_LReads", "75_LReadsDelta", "76_MaxLReader", "77_PReads", "78_PReadsDelta", "79_MaxPReader".

				Defaults to megabytes. If "pages", the units are in 8kb blocks (the standard SQL Server database page size). If "native", 
				the units are those that come from the DMVs. For logical and physical readers, writes, and TempDB usage, this is 8kb pages. For
				query memory this is kilobytes and for transaction log usage this is bytes. When a column is not in its native unit type
				(e.g. pages for tempdb allocations), two decimal places are used; otherwise, whole numbers are used.

@savespace		Valid Values: "n" or "y"

				If Y, instructs sp_XR_SessionSummary to use abbreviated column names in the output. This is useful for condensing the 
				resulting data set so that more column data can be viewed at the same time.';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
@orderby		Valid Values: positive number (> 0), but <= the number of columns in the result set

				This integer is used in an ORDER BY in the query to define which column is used to order the result set. The left-most column 
				in the result set is 1, the next one to the right is 2, etc. The value passed in through @orderby cannot be greater than the 
				number of columns in the result set. When @savespace is "N", the column number is prepended to the column name in the output, to 
				aid in choosing the correct column number. Sorting is done via the raw numeric values rather than the formatted strings that
				are actually present in the result set.

@orderdir		Valid Values: "a" or "d"

				Determines whether the result set is ordered ascending or descending.

@help			Valid Values: "n", "p" or "params", "c" or "columns", "all, or even gibberish

				If @help=N''N'', then no help is printed. If =''params'', this section of Help is printed. If =''columns'', the section on 
				result columns is prented. If @help is passed anything else (even gibberish), it is set to ''all'', and all help content
				is printed.';
	RAISERROR(@lv__helpstr,10,1);

	IF @help = N'params'
	BEGIN
		GOTO exitloc
	END
	ELSE
	BEGIN
		SET @lv__helpstr = N'
		';
		RAISERROR(@lv__helpstr,10,1);
	END


helpcolumns:

	SET @lv__helpstr = N'
NOTE 1: AutoWho can be configured to detect certain long-running spids that for whatever reason should not be counted with other activity. 
(For example, a long-running monitoring SPID from a common SQL Server monitoring suite like those from Dell, Idera, or RedGate, or even 
the long-running SPIDs from ChiRho itself). These spids are completely ignored by sp_XR_SessionSummary; if they were not ignored, they
would make the data worthless. E.g. the longest-running request at any time would be the always-running monitoring spid.) This accounts 
for apparent numerical differences between sp_XR_SessionSummary output and sp_SessionViewer output.

NOTE 2: When the value for a given field is 0 or NULL or otherwise "N/A", an empty cell is returned to make the results less crowded.

Result Columns
-------------------------------------------------------------------------------------------------------------------------------------------
1_SPIDCaptureTime						Short name: SCT

										Displays the datetime value (including milliseconds) of each successful AutoWho capture that occurred 
										during the time range specified by @start/@end. There is always 1 row per capture time. Because of the 
										width of output rows, SPIDCaptureTime is displayed multiple times, every few columns, so that the 
										relevant time period can always be seen no matter what scrolling is done.

2_TotCapturedSPIDs						Short name: #SPIDs

										The total number of SPIDs captured by AutoWho. Note that this may not have been the total # of spids 
										connected to SQL Server at the time of the AutoWho execution, since AutoWho can be set to filter by 
										duration, database, state of the SPID (active, idle with tran, idle), etc. 

3_Active								Short name: Act

										The # of captured SPIDs that were running a batch at the time of the AutoWho capture. This will always 
										be a subset of the spids represented by "2_TotCapturedSpids".'
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
4_MaxActive								Short name: MaxAct

										The MAX(duration) of all Active SPIDs. Empty if no active spids were captured. Format is 
										"Seconds,milliseconds" for spids that have been active < 1 minute, HH:MM:SS for spids active less than 
										a day, and <Day>~HH:MM:SS for spids active longer than a day.
										
5_AvgActive								Short name: AvgAct

										The AVG(duration) of all Active SPIDs. Format follows "4_MaxActive".';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
(Active histogram)						A set of "bucket" columns that shows how many active batches had a duration of 0 to 1 second, 1 to 5 
										seconds, 5 to 10 seconds, 10 to 30 seconds, 30 to 60 seconds, 60 to 300 seconds, and 300+ seconds. 
										Durations on the boundary edges are not double-counted (a category starts at 1 ms after the boundary point,
										except for the 0 to 1 second category). 

14_IdleTran								Short name: IdlTrn

										The number of SPIDs that are not running a batch, but have dm_exec_sessions.open_transaction_count > 0.

15_MaxIdleTran							Short name: MaxIdlTrn

										The idle duration of the spid that has been idle the longest (of the spids counted by 14_IdleTran) 
										that also has an open tran. Note that this is the length of time that the spid has been IDLE, not the length 
										of time of its longest open transaction. A spid that has been idle only a short time could have a long-
										running transaction. Format follows "4_MaxActive".

16_AvgIdleTran							Short name: AvgIdlTrn

										The average idle duration of all spids counted by 14_IdleTran). Format follows "4_MaxActive".

(Idle tran histogram)					Similar to the "active histogram", except that the duration involved is the "idle duration", the amount of 
										time since the last batch completed on this spid. Note that this is NOT the duration of the transaction.';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
25_OpenTran								Short name: OpTrn

										The number of spids (whether running or idle) that have an open transaction. Both 
										dm_exec_sessions.open_transaction_count and the presence of trans in the dm_tran* views are taken into 
										consideration. Read-only trans will be counted if the isolation level is Repeatable Read or Serializable 
										(i.e. able to hold locks for a longer time), or Snapshot Isolation (able to hold open row versions in 
										TempDB). Other trans (e.g. Read Committed) will only be captured if the spid has an active or idle w/tran 
										duration >= the TranDetailsThreshold AutoWho option.

26_MaxTran								Short name: MaxTrn

										The duration of the oldest open tran (of spids counted by 25_OpenTran). This is based on the value in
										dm_tran_active_transactions.transaction_begin_time. Format follows "4_MaxActive".

27_AvgTran								Short name: AvgTrn

										The average duration of open transactions. Format follows "4_MaxActive".

(transaction histogram)					Similar to the "active histogram", except that the duration involved is the transaction length.';

	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
36_Blocked								Short name: Blkd

										The # of spids that are actively running a batch but are blocked by another spid. A "blocked" spid here 
										means that at least one of the tasks for the spid in dm_os_waiting_tasks has a non-null blocking_session_id 
										value which is also <> session_id. (Thus, CXPACKET waits are not considered "blocking"). Certain types of 
										page latch waits and even RESOURCE_SEMAPHORE waits can fit this category. 

37_MaxBlockedTask						Short name: MaxBlk

										The MAX(dm_os_waiting_tasks.wait_duration_ms) value for spids that qualify for the "36_Blocked" field. 
										Format follows "4_MaxActive".

38_AvgBlockedTask						Short name: AvgBlk

										The AVG(dm_os_waiting_tasks.wait_duration_ms) value for spids that qualify for the "36_Blocked" field. 
										Format follows "4_MaxActive".

(blocked histogram)						Similar to the "active histogram", except that the duration involved is the MAX(dm_os_waiting_tasks.wait_duration_ms),
										per SPID, of blocked tasks.';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
47_WaitingSPIDs							Short name: WtSPIDs

										The # of spids that are actively running a batch and are waiting but NOT blocked by another spid. 
										Note that normally, SQL Server terminology defines blocking as one type (i.e. a subset) of waiting. 
										However, in sp_XR_SessionSummary, the two categories are non-overlapping, allowing the user to 
										quickly see which type of "slowdown" has occurred. Note that CXPACKET waits are not considered waits. 
										Thus, a parallel query with 16 tasks, 1 of which is running and the other 15 are waiting on CXPACKET, 
										will not be considered to be waiting (or blocked). If that 1 task then becomes blocked (and the other 
										15 are still waiting on CXPACKET), then the spid will be "blocked" but not waiting.

48_WaitingTasks							Short name: WtTsk

										The # of tasks that are waiting in actively-running spids. For example, a parallel query might have 9 
										tasks, 4 of which are running, 3 are in CXPACKET waits, and 2 are waiting on PAGEIOLATCH waits. This 
										spid would only increment the "43_WaitingSPIDs" field by 1 (one spid), but would increment the "21_WaitingTasks" 
										field by 2 because of the 2 PAGEIOLATCH waits. (CXPACKET waits are not counted as "waits"). As mentioned 
										above, tasks that are blocked behind another spid do not count as waiting.

49_MaxWaitingTask						Short name: MaxWtTsk

										The MAX(dm_os_waiting_tasks.wait_duration_ms) value of tasks that are waiting. Waits due to being blocked
										behind another spid and CXPACKET waits are not counted as waiting. Format follows "4_MaxActive".										
										
50_AvgWaitingTask						Short name: AvgWtTsk

										The AVG(dm_os_waiting_tasks.wait_duration_ms) value of tasks that are waiting. Waits due to being blocked
										behind another spid and CXPACKET waits are not counted as waiting. Format follows "4_MaxActive".';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
(waiting histogram)						Similar to the "active histogram", except that the duration involved is the MAX(dm_os_waiting_tasks.wait_duration_ms)
										of tasks that are waiting (but not blocked), per-spid. 

59_TLogUsed								Short name: Tlog

										The SUM() of the 2 dm_tran_database_transactions.database_transaction_log_bytes_used* columns for 
										all user transactions. Note that logic is in place to prevent enlisted trans from being double-counted.
										
60_MaxLogUsed							Short name: MaxTlog

										The MAX() of the addition of the 2 dm_tran_database_transactions.database_transaction_log_bytes_used* 
										columns for all user transactions.

61_QMemReq								Short name: QMReq

										The SUM() of dm_exec_memory_grants.requested_memory_kb. Note that this field uses requested_memory_kb, 
										while the next field uses granted_memory_kb. The idea here is for field 61 to show how much memory is 
										NEEDED across all queries, while field 62 shows what they actually got.

62_QMemGrant							Short name: QMGr

										The SUM() of dm_exec_memory_grants.granted_memory_kb.

62_MaxQMemGrant							Short name: MaxQMGr

										The MAX() of dm_exec_memory_grants.granted_memory_kb. See notes on "61_QMemReq".

64_TempDB								Short name: Tdb

										The SUM() of the various tempdb session and task allocation (minus deallocation) counters from 
										dm_db_session_space_usage and dm_db_task_space_usage. If a given "alloc - dealloc" pair yields a 
										negative number, this pair is "floored" at 0. 

65_MaxTempDB							Short name: MaxTdb

										The MAX() by spid of the tempdb allocation minus deallocation counters.';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
66_CPUused								Short name: CPU

										The SUM() of dm_exec_requests.cpu_time. Only active spids are counted so that long-idle spids do not 
										influence (i.e. flatten) the up-and-down nature of this value over time.

67_CPUDelta								Short name: CPUDelt

										"66_CPUused" of the current row minus "66_CPUused" from the previous row. Negative values are ignored, 
										leaving an empty cell.

68_MaxCPUused							Short name: MaxCPU

										The MAX() of dm_exec_requests.cpu_time

69_UserTasks							Short name: Tasks

										A SUM() of the # of tasks allocated for each user spid. The # of tasks for a spid is calcuted as the 
										COUNT(*) of records in sys.dm_db_task_space_usage.

71_Writes								Short name: Wri

										SUM() on dm_exec_requests.writes, otherwise similar to "66_CPUused"

72_WritesDelta							Short name: WriDelt

										Similar to "67_CPUDelta", but for writes

73_MaxWriter							Short name: MaxWri

										MAX() of dm_exec_requests.writes';
	RAISERROR(@lv__helpstr,10,1);

	SET @lv__helpstr = N'
74_LReads								Short name: LRds

										SUM() on dm_exec_requests.logical_reads, otherwise similar to "66_CPUused"

75_LReadsDelta							Short name: LRDelt

										Similar to "67_CPUDelta", but for logical reads.

76_MaxLReader							Short name: MaxLRd

										MAX() of dm_exec_requests.logical_reads

77_PReads								Short name: PRds

										SUM() of dm_exec_requests.reads, otherwise similar to "66_CPUused"

78_PReadsDelta							Short name: PRDelt

										Similar to "67_CPUDelta", but for physical reads

79_MaxPReader							Short name: MaxPRd

										MAX() of dm_exec_requests.reads

80_HasBlockingGraph						Short name: hasBG

										Indicates whether AutoWho constructed a blocking graph for its run at the time indicated by SPIDCaptureTime.

81_HasLockDetails						Short name: hasLck

										Indicates whether AutoWho collected details from dm_tran_locks about blocker & blockee spids during its 
										run at the time indicated by SPIDCaptureTime.

82_HasTranDetails						Short name: hasTrnD

										Indicates whether AutoWho collected details from the dm_tran* (besides dm_tran_locks) views during its 
										run at the time indicated by SPIDCaptureTime.';
	RAISERROR(@lv__helpstr,10,1);

exitloc:

	RETURN 0;
END

GO
