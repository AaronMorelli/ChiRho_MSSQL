SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_MASTERPROC_SCHEMA@@.sp_XR_JobMatrix
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

	FILE NAME: sp_XR_JobMatrix.sql

	PROCEDURE NAME: sp_XR_JobMatrix

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Uses msdb job history to construct a history matrix showing durations and results, to present
	a quick graphical view of job execution for troubleshooting sessions. Also notes non-default SQL Agent config
	options and shows the contents of the most recent 3 SQL Agent log files.

	FUTURE ENHANCEMENTS: 
		Considering these:
			Add a JobAttributes header to the right of the "LineHeader" header row (but only the one above the first matrix???)
					(blank text above the job names area, and then column headers for "CrModDate" (either create or last modified date), 
						"Notifies", "Owner", and "StepTypes")
					We only want this info if the user asks for it, except for CrModDate, which if @JobAttrib is 1 it could print Create or Mod dates
					if they were within the last 3 days of the end-time of the matrix

		Perhaps add a NVARCHAR(MAX) parameter that receives a comma-delimited list of job names and only returns those in the output

		Debug=1 is not really usable. =2 is ok, but there are too many result sets w/o any contextual info for =1, so that needs to be cleaned up.

To Execute
------------------------
--Note that these procs may be created in the master DB (the ideal location), but could be located elsewhere:
-- - in the ChiRho database itself (e.g. if person installing did not have rights to create in master)
-- - in TempDB (i.e. in a "short-term" situation where all objects are installed into TempDB), in
--		which case it would be called via ##sp_XR_JobMatrix
	exec sp_XR_JobMatrix @Help=N'Y'

	exec sp_XR_JobMatrix	@PointInTime = <past datetime>,	@HoursBack = 12,
							@ToConsole = N'N',				@FitOnScreen = N'Y',
							@DisplayConfigOptions = 1,		@DisplayAgentLog = 1, 
							@Queries = 0,					@Help='N',					
							@Debug=0
*/
(
	@PointInTime					DATETIME		= NULL,
	@HoursBack						TINYINT			= 12,			--0 to 48
	@ToConsole						NCHAR(1)		= N'N',
	@FitOnScreen					NCHAR(1)		= N'Y',
	@DisplayConfigOptions			TINYINT			= 1,			-- 0 = No; 1 = Only different from default; 2 = All (important) config opts
	@DisplayAgentLog				INT				= 1,			-- 0 = No; 1 = only when Sev 1 records exist; 2 Always display the first file; 3 Display All Files
	@Queries						NVARCHAR(10)	= N'N',			-- saving room for tags (i.e. if # of queries grows, categorize them and let user focus)
	@Help							NCHAR(1)		= N'N',
	@Directives						NVARCHAR(512)	= N'',
	@Debug							TINYINT			= 0				-- 1: debug result sets; 2: performance
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	/* 
														Part 0: Variables, Validation, Temp Table Definitions
	*/
	--General variables
	DECLARE 
		@lv__HelpText						VARCHAR(MAX),
		@helpstr							NVARCHAR(MAX),
		@helpexec							NVARCHAR(4000),
		@lv__ErrorText						VARCHAR(MAX),
		@lv__ErrorSeverity					INT,
		@lv__ErrorState						INT,
		@lv__OutputVar						NVARCHAR(MAX),
		@lv__OutputLength					INT,
		@lv__CurrentPrintLocation			INT,
		@lv__beforedt						DATETIME,
		@lv__afterdt						DATETIME,
		@lv__slownessthreshold				SMALLINT
		;

	SET @Help = UPPER(ISNULL(@Help,N'Z'));
	IF @Directives LIKE N'%wrapper%'
	BEGIN
		SET @helpexec = N'';
	END
	ELSE
	BEGIN
		SET @helpexec = N'
EXEC sp_XR_JobMatrix	@PointInTime = NULL,			@HoursBack = 12,
						@ToConsole = N''N'',  			@FitOnScreen = N''Y'',
						@DisplayConfigOptions = 1,		@DisplayAgentLog = 1,
						@Queries = 0,					@Help=''N'',	--params, columns, matrix, all
						@Debug=0
';
	END

	IF @Help <> N'N'
	BEGIN
		GOTO helpbasic
	END

	SET @lv__beforedt = GETDATE();
	SET @lv__slownessthreshold = 250;		--number of milliseconds over which a ***dbg message will be printed; aids
											--immediate review of where in the proc a given execution was slow

	--Matrix variables		
	DECLARE 
		@lv__mtx__SQLAgentStartTime			DATETIME, 
		@lv__mtx__SQLServerStartTime		DATETIME,
		@lv__mtx__SQLStartTimeResult		SMALLINT,		--0 NULL, 1 success, 2 more recent than @lv__mtx__OverallWindowEndTime
		@lv__mtx__SQLAgentTimeResult		SMALLINT,		--0 NULL, 1 success, 2 @lv__mtx__OverallWindowEndTime is still older than the oldest Agent log looked at
		@lv__mtx__WindowLength_minutes		SMALLINT,
		@lv__mtx__MatrixWidth				SMALLINT,
		@lv__mtx__HeaderLine				NVARCHAR(4000), 
		@lv__mtx__HeaderHours				NVARCHAR(4000),
		@lv__mtx__Replicate1				SMALLINT, 
		@lv__mtx__Replicate2				SMALLINT,
		@lv__mtx__CountMatrixRows_1			INT, 
		@lv__mtx__CountMatrixRows_3			INT,
		@lv__mtx__CountMatrixRows_5			INT,
		@lv__mtx__Matrix3HasHeader			BIT,
		@lv__mtx__LineHeaderMod				INT, 
		@lv__mtx__TimeHeaderMod				INT,
		@lv__mtx__EmptyChar					NCHAR(1),
		@lv__mtx__CurrentTime_WindowBegin	DATETIME,
		@lv__mtx__CurrentTime_WindowEnd		DATETIME,
		@lv__mtx__OverallWindowBeginTime	DATETIME, 
		@lv__mtx__OverallWindowEndTime		DATETIME,
		@lv__mtx__MaxJobNameLength			SMALLINT,
		--@lv__mtx__Replicate1				SMALLINT, 
		--@lv__mtx__Replicate2				SMALLINT,
		--@lv__mtx__CountMatrixRows_1			INT, 
		--@lv__mtx__CountMatrixRows_3			INT,
		--@lv__mtx__CountMatrixRows_5			INT,
		--@lv__mtx__Matrix3HasHeader			BIT,
		@lv__mtx__PrintOverallBeginTime		VARCHAR(30), 
		@lv__mtx__PrintOverallEndTime		VARCHAR(30)
		;

	SET @lv__mtx__SQLStartTimeResult = 0;
	SET @lv__mtx__SQLAgentTimeResult = 0;

	--Config Option variables
	DECLARE 
		@lv__cfg__MaxHistoryRows			INT,
		@lv__cfg__MaxHistoryRowsPerJob		INT,
		@lv__cfg__tmpregstr					NVARCHAR(200),
		@lv__cfg__ServiceStartupSetting		INT,
		@lv__cfg__ShouldAgentRestartSQL		INT,
		@lv__cfg__errorlog_file				NVARCHAR(255),
		@lv__cfg__errorlogging_level		INT,			-- 1 = error, 2 = warning, 4 = information
		@lv__cfg__error_recipient			NVARCHAR(30),	-- Network address of error popup recipient
		@lv__cfg__monitor_autostart			INT,
		@lv__cfg__local_host_server			SYSNAME,		-- Alias of local host server
		@lv__cfg__job_shutdown_timeout		INT,
		@lv__cfg__login_timeout				INT,
		@lv__cfg__idle_cpu_percent			INT,
		@lv__cfg__idle_cpu_duration			INT,
		@lv__cfg__oem_errorlog				INT,
		@lv__cfg__alert_replace_runtime_tokens INT,
		@lv__cfg__cpu_poller_enabled		INT,
		@lv__cfg__use_databasemail			INT,
		@lv__cfg__databasemail_profile		SYSNAME
	;

	--SQL Agent Log variables
	DECLARE 
		@lv__log__maxTabID					INT,
		@lv__log__log1processing			SMALLINT,		--not started; 1 load completed; -1 load failed; 2 processing completed; -2 processing failed; -3 cancelled due to previous failure
		@lv__log__log2processing			SMALLINT,
		@lv__log__log3processing			SMALLINT,
		@lv__log__AgentLogString			VARCHAR(MAX);

	SET @lv__log__log1processing = 0;
	SET @lv__log__log2processing = 0;
	SET @lv__log__log3processing = 0;

	--Parameter validation 
	SET @PointInTime =		ISNULL(@PointInTime, GETDATE());
	SET @HoursBack =		ISNULL(@HoursBack,12);
	SET @ToConsole =		UPPER(ISNULL(@ToConsole, N'N'));
	SET @FitOnScreen =		UPPER(ISNULL(@FitOnScreen, N'Y'));
	SET @DisplayConfigOptions = ISNULL(@DisplayConfigOptions,1);
	SET @DisplayAgentLog = ISNULL(@DisplayAgentLog,1);
	SET @Queries =			UPPER(ISNULL(@Queries,N'N'));
	SET @Help =				UPPER(ISNULL(@Help, N'N'));
	SET @Debug =			ISNULL(@Debug,0);

	IF @PointInTime < CONVERT(DATETIME, '2010-01-01') OR @PointInTime > GETDATE()
	BEGIN
		RAISERROR('The @PointInTime value is restricted to values between 2010-01-01 and the present.',15,1);
		RETURN -1;
	END

	IF ISNULL(@HoursBack,-1) < 0 or ISNULL(@HoursBack,-1) > 48
	BEGIN
		RAISERROR('The @HoursBack parameter must be a non-null value between 0 and 48 inclusive.', 15, 1);
		RETURN -1;
	END

	IF @ToConsole NOT IN (N'N', N'Y')
	BEGIN
		RAISERROR('The @ToConsole parameter must be either Y or N',15,1);
		RETURN -1;
	END

	IF @FitOnScreen NOT IN (N'N', N'Y')
	BEGIN
		RAISERROR('The @FitOnScreen parameter must be either Y or N',15,1);
		RETURN -1;
	END

	IF @DisplayAgentLog NOT IN (0, 1, 2, 3)
	BEGIN
		RAISERROR('The @DisplayAgentLog parameter must be one of the following: 0 = No; 1 = Currently log only, and only when Sev 1 records exist; 2 = Always display current log; 3 = Always display last 3 log files', 15, 1);
		RETURN -1;
	END

	IF @DisplayConfigOptions NOT IN (0, 1, 2)
	BEGIN
		RAISERROR('The @DisplayConfigOptions parameter must be either 0 = No, 1 = only different from default, or 2 = Always display.', 15, 1);
		RETURN -1;
	END

	--If the user attempts to type anything for this variable, set to N'Y'
	IF ISNULL(@Queries, N'Y') <> N'N'
	BEGIN
		SET @Queries = N'Y'
	END

	--Final Display control bits
	DECLARE 
		@output__DisplayMatrix				BIT,
		@output__DisplayAgentLog			BIT,
		@output__DisplayConfig				BIT,
		@output__DisplayQueries				BIT,
		@outputType__Matrix					NVARCHAR(10);

	SET @output__DisplayAgentLog = CASE WHEN @DisplayAgentLog = 0 THEN 0 ELSE 1 END; 
	SET @output__DisplayConfig = CASE WHEN @DisplayConfigOptions = 0 THEN 0 ELSE 1 END;
	SET @output__DisplayQueries = CASE WHEN @Queries = N'N' THEN 0 ELSE 1 END;		--if user types anything but 'N', we assume they want to see the queries

	IF @HoursBack > 0 
	BEGIN
		SET @output__DisplayMatrix = 1;
	END
	ELSE
	BEGIN
		SET @output__DisplayMatrix = 0;
	END

	IF @ToConsole = N'N'
	BEGIN
		SET @outputType__Matrix = N'XML'
	END
	ELSE
	BEGIN
		SET @outputType__Matrix = N'CONSOLE'
	END

	--Temp table definitions
	--Holds the "header" info for the matrix, and also holds the start and end times of each of our time windows.

	CREATE TABLE #TimeWindows_Hist (
		WindowID			INT NOT NULL PRIMARY KEY CLUSTERED,
		WindowBegin			DATETIME NOT NULL,
		WindowEnd			DATETIME NOT NULL,
		TimeHeaderChar		NCHAR(1) NOT NULL,
		LineHeaderChar		NCHAR(1) NOT NULL
	);

	--A list of SQL Agent jobs, the # of runs and failures, which sub-matrix the job falls into, and the
	-- display order within the sub-matrix
	CREATE TABLE #Jobs (
		JobID				INT NOT NULL IDENTITY PRIMARY KEY CLUSTERED,
		JobName				NVARCHAR(256) NOT NULL,
		IsEnabled			TINYINT NOT NULL,
		Notifies			TINYINT NOT NULL,
		CreateDate			DATETIME NOT NULL, 
		LastModifiedDate	DATETIME NOT NULL,
		OwnerPrincipalName	NVARCHAR(256),
		native_job_id		UNIQUEIDENTIFIER NOT NULL,
		JobRuns				INT NOT NULL,
		JobFailures			INT NOT NULL,
		CompletionsAllTime	INT NULL,
		AvgJobDur_seconds	BIGINT NULL,		--average duration, including failures.
		AvgSuccessDur_seconds BIGINT NULL,	--average duration, only including successes. Either measure can be a faulty predictor
												-- of future duration. (e.g. a failure occurring almost right away, leading to a very short duration)
		MatrixNumber		INT NOT NULL,
		DisplayOrder		INT NOT NULL, 
		StepTypes			NVARCHAR(100)			--comma-delimited list of the different TYPES of steps for the job
	);

	--TODO: some query plans might benefit from an index here. Investigate the best
	-- field for the clustered index key
	CREATE TABLE #JobInstances (
		native_job_id		UNIQUEIDENTIFIER NOT NULL, 
		job_run_status		INT,				--0=failed; 1=succeeded; 2=retry; 3=cancelled
		JobStartTime		DATETIME, 
		JobEndTime			DATETIME, 
		JobDisplayEndTime	DATETIME,		--helps us do certain display logic for jobs that are "still running" (i.e. don't have an end time)
		JobExpectedEndTime	DATETIME
	);

	--Holds the contents of master.dbo.xp_sqlagent_enum_jobs so that we can determine which jobs are 
	-- running (and thus don't have a completion record in the sysjobhistory table)
	CREATE TABLE #CurrentlyRunningJobs1 ( 
		Job_ID				UNIQUEIDENTIFIER,
		Last_Run_Date		INT,
		Last_Run_Time		INT,
		Next_Run_Date		INT,
		Next_Run_Time		INT,
		Next_Run_Schedule_ID INT,
		Requested_To_Run	INT,
		Request_Source		INT,
		Request_Source_ID	NVARCHAR(100),
		Running				INT,
		Current_Step		INT,
		Current_Retry_Attempt INT, 
		aState				INT
	);

	CREATE TABLE #CurrentlyRunningJobs2 (
		native_job_id		UNIQUEIDENTIFIER NOT NULL, 
		JobStartTime		DATETIME, 
		JobEndTime			DATETIME, 
		JobDisplayEndTime	DATETIME,		--helps us do certain display logic for jobs that are "still running" (i.e. don't have an end time)
		JobExpectedEndTime	DATETIME
	);

	--Populated with a cross join between the #TimeWindows_Hist table and the #Jobs table, which logically gives us
	-- each matrix "line" (a series of cells/time windows for each job)
	CREATE TABLE #JobArrays (
		JobID				INT NOT NULL, 
		WindowID			INT NOT NULL, 
		WindowBegin			DATETIME NOT NULL, 
		WindowEnd			DATETIME NOT NULL, 
		CellText			NCHAR(1) NOT NULL
	);

	--We place various substrings here before assembling them into the XML value
	CREATE TABLE #OutputStringLineItems (
		RowType				TINYINT, 
		JobID				INT, 
		MatrixNumber		INT, 
		DisplayOrder		INT, 
		CellString			NVARCHAR(MAX)
	);

	--Where we place the SQL Agent log messages before we assemble them into the XML value
	CREATE TABLE #SQLAgentLog (
		idcol				INT IDENTITY PRIMARY KEY CLUSTERED, 
		FileNumber			INT, 
		isLastRecord		INT, 
		LogDate				DATETIME, 
		ErrorLevel			INT, 
		aText				NVARCHAR(MAX)
	);

	--Config option list
	CREATE TABLE #OptionsToDisplay (
		idcol				INT IDENTITY PRIMARY KEY, 
		OptionTag			NVARCHAR(100), 
		OptionValue			NVARCHAR(100), 
		OptionNormalValue	NVARCHAR(100)
	);

	CREATE TABLE #PreXML (
		OrderingNumber		INT NOT NULL,
		ReturnType			NVARCHAR(10) NOT NULL,
		LongString			NVARCHAR(MAX)
	);

	SET @lv__afterdt = GETDATE();

	--If the proc runs longer than expected, scattering these duration tests throughout the proc, then sending the
	-- results to the console, will help the user understand where the proc is taking its time.
	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: Proc setup and Temp Table creation took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END
	/* 

														Part 1: Job History Matrix

	*/
	SET @lv__beforedt = GETDATE();

	--If we are skipping the matrix
	IF @output__DisplayMatrix = 0
	BEGIN
		GOTO configstart
	END

	-- A cell time window begins at the zero second of a (e.g. 10)-minute time boundary, and ends immediately before
	-- a new (e.g. 10)-minute time boundary starts. Lets find out how wide our window lengths are, and derive the
	-- @lv__mtx__MatrixWidth from that.

	/* The calculation for @lv__mtx__WindowLength_minutes (the time window represented by a single cell) and @
		lv__mtx__MatrixWidth (the complete time window and size of the matrix) deserves a full explanation:

		Several design goals heavily influence the characteristics of the job history matrix:
			- The user can control whether everything fits on one screen or not (@FitOnScreen); we default to fit
			- We want the top of the hour to always align with the start time of a time window of a matrix cell,
				(i.e. you would never have an individual cell with its time window being something like '10:55:00 - 11:04:59')
				which means the possible values for @lv__mtx__WindowLength_minutes must always be a root of 60.
				This limits us to 1, 2, 3, 4, 5, 6, 10, 15, 20, 30, and 60

			- The fact that we want to print numeric labels for the top-of-the-hour effectively rules out
				60 minutes per cell (because the labels for adjacent cells would overlap) and 30 minutes per cell
				(because they would be immediately adjacent)

			- It is also nice for the time windows to align with intuitive sub-divisions of the 60-minutes in
				an hour, especially the half-hour. Thus, a time window of 10 minutes is great because you have 
				6 intuitive markers and can place a special tick mark/label identifying the 30-minutes.
				
				Conversely, a time window length of 4 minutes is not ideal, since while it is a root of 60, it is
				not a root of 30.
				
				(Note that having a time window length of 20 minutes is also somewhat intuitive, and is handy
				when @HoursBack is very large).

		The net effect of all this is that the time windows (minutes per cell) allowed for our matrix are:
				1, 2, 3, 5, 6, 10, 15, and 20


		The time window length also depends on whether the user wants everything in 1 screen, or is ok with scrolling.
		If @FitsOnScreen='Y', the matrix is kept in between 100 and 145 characters (with a couple exceptions on the lower side)
		and if ='N', then the matrix is kept to 360 maximum.

		Here's the complete chart for the historical matrix:

	If @FitOnScreen = 'Y'
		@HoursBack = 1 --> cell width = 1		MatrixWidth = 60		(60-wide doesn't look as good, so we actually bump it up to 1.5 hours)
		@HoursBack = 2 --> cell width = 1		MatrixWidth = 120
		@HoursBack = 3 --> cell width = 2		MatrixWidth = 90
		@HoursBack = 4 --> cell width = 2		MatrixWidth = 120
		@HoursBack = 5 --> cell width = 3/2		MatrixWidth = 100/150	(100 width for XML, 150 width for console)
		@HoursBack = 6 --> cell width = 3		MatrixWidth = 120
		@HoursBack = 7 --> cell width = 3		MatrixWidth = 140
		@HoursBack = 8 --> cell width = 5		MatrixWidth = 96	
		@HoursBack = 9 --> cell width = 5		MatrixWidth = 108	
		@HoursBack =10 --> cell width = 5		MatrixWidth = 120
		@HoursBack =11 --> cell width = 5		MatrixWidth = 132
		@HoursBack =12 --> cell width = 5		MatrixWidth = 144
		@HoursBack =13 --> cell width = 6		MatrixWidth = 130
		@HoursBack =14 --> cell width = 6		MatrixWidth = 140
		@HoursBack =15 --> cell width = 10		MatrixWidth = 90	
		@HoursBack =16 --> cell width = 10		MatrixWidth = 96	
		@HoursBack =17 --> cell width = 10		MatrixWidth = 102	
		@HoursBack =18 --> cell width = 10		MatrixWidth = 108	
		@HoursBack =19 --> cell width = 10		MatrixWidth = 114	
		@HoursBack =20 --> cell width = 10		MatrixWidth = 120
		@HoursBack =21 --> cell width = 10		MatrixWidth = 126
		@HoursBack =22 --> cell width = 10		MatrixWidth = 132
		@HoursBack =23 --> cell width = 10		MatrixWidth = 138
		@HoursBack =24 --> cell width = 15		MatrixWidth = 96	
		@HoursBack =25 --> cell width = 15		MatrixWidth = 100
		@HoursBack =26 --> cell width = 15		MatrixWidth = 104
		@HoursBack =27 --> cell width = 15		MatrixWidth = 108
		@HoursBack =28 --> cell width = 15		MatrixWidth = 112
		@HoursBack =29 --> cell width = 15		MatrixWidth = 116
		@HoursBack =30 --> cell width = 15		MatrixWidth = 120
		@HoursBack =31 --> cell width = 15		MatrixWidth = 124
		@HoursBack =32 --> cell width = 15		MatrixWidth = 128
		@HoursBack =33 --> cell width = 15		MatrixWidth = 132
		@HoursBack =34 --> cell width = 15		MatrixWidth = 136
		@HoursBack =35 --> cell width = 15		MatrixWidth = 140
		@HoursBack =36 --> cell width = 20		MatrixWidth = 108
		@HoursBack =37 --> cell width = 20		MatrixWidth = 111
		@HoursBack =38 --> cell width = 20		MatrixWidth = 114
		@HoursBack =39 --> cell width = 20		MatrixWidth = 117
		@HoursBack =40 --> cell width = 20		MatrixWidth = 120
		@HoursBack =41 --> cell width = 20		MatrixWidth = 123
		@HoursBack =42 --> cell width = 20		MatrixWidth = 126
		@HoursBack =43 --> cell width = 20		MatrixWidth = 129
		@HoursBack =44 --> cell width = 20		MatrixWidth = 132
		@HoursBack =45 --> cell width = 20		MatrixWidth = 135
		@HoursBack =46 --> cell width = 20		MatrixWidth = 138
		@HoursBack =47 --> cell width = 20		MatrixWidth = 141
		@HoursBack =48 --> cell width = 20		MatrixWidth = 144


	If @FitOnScreen = 'N'

		@HoursBack = 1 --> cell width = 1		MatrixWidth = 60	
		@HoursBack = 2 --> cell width = 1		MatrixWidth = 120
		@HoursBack = 3 --> cell width = 1		MatrixWidth = 180
		@HoursBack = 4 --> cell width = 1		MatrixWidth = 240
		@HoursBack = 5 --> cell width = 1		MatrixWidth = 300
		@HoursBack = 6 --> cell width = 1		MatrixWidth = 360

		@HoursBack = 7 --> cell width = 2		MatrixWidth = 210
		@HoursBack = 8 --> cell width = 2		MatrixWidth = 240
		@HoursBack = 9 --> cell width = 2		MatrixWidth = 270
		@HoursBack =10 --> cell width = 2		MatrixWidth = 300
		@HoursBack =11 --> cell width = 2		MatrixWidth = 330
		@HoursBack =12 --> cell width = 2		MatrixWidth = 360

		--Let's skip cell widths = 3 and 4 because they don't line up with tick marks as well

		@HoursBack =13 --> cell width = 5		MatrixWidth = 156
		@HoursBack =14 --> cell width = 5		MatrixWidth = 168
		@HoursBack =15 --> cell width = 5		MatrixWidth = 180
		@HoursBack =16 --> cell width = 5		MatrixWidth = 192
		@HoursBack =17 --> cell width = 5		MatrixWidth = 204
		@HoursBack =18 --> cell width = 5		MatrixWidth = 216

		@HoursBack =25 --> cell width = 5		MatrixWidth = 300	
		@HoursBack =26 --> cell width = 5		MatrixWidth = 312
		@HoursBack =27 --> cell width = 5		MatrixWidth = 324
		@HoursBack =28 --> cell width = 5		MatrixWidth = 336
		@HoursBack =29 --> cell width = 5		MatrixWidth = 348
		@HoursBack =30 --> cell width = 5		MatrixWidth = 360

		@HoursBack =31 --> cell width = 10		MatrixWidth = 186
		@HoursBack =32 --> cell width = 10		MatrixWidth = 192
		@HoursBack =33 --> cell width = 10		MatrixWidth = 198
		@HoursBack =34 --> cell width = 10		MatrixWidth = 204
		@HoursBack =35 --> cell width = 10		MatrixWidth = 210
		@HoursBack =36 --> cell width = 10		MatrixWidth = 216

		@HoursBack =37 --> cell width = 10		MatrixWidth = 222
		@HoursBack =38 --> cell width = 10		MatrixWidth = 228
		@HoursBack =39 --> cell width = 10		MatrixWidth = 234
		@HoursBack =40 --> cell width = 10		MatrixWidth = 240
		@HoursBack =41 --> cell width = 10		MatrixWidth = 246
		@HoursBack =42 --> cell width = 10		MatrixWidth = 252

		@HoursBack =43 --> cell width = 10		MatrixWidth = 258
		@HoursBack =44 --> cell width = 10		MatrixWidth = 264
		@HoursBack =45 --> cell width = 10		MatrixWidth = 270
		@HoursBack =46 --> cell width = 10		MatrixWidth = 276
		@HoursBack =47 --> cell width = 10		MatrixWidth = 282
		@HoursBack =48 --> cell width = 10		MatrixWidth = 288
	*/

	IF @FitOnScreen = N'Y'
	BEGIN
		SELECT @lv__mtx__WindowLength_minutes = CASE 
				WHEN @HoursBack BETWEEN 1 AND 2 THEN 1
				WHEN @HoursBack BETWEEN 3 AND 4 THEN 2
				WHEN @HoursBack = 5
					THEN (
						CASE WHEN @outputType__Matrix = N'XML' THEN 3
							ELSE 2
						END
					)
				WHEN @HoursBack BETWEEN 6 AND 7 THEN 3
				WHEN @HoursBack BETWEEN 8 AND 12 THEN 5
				WHEN @HoursBack BETWEEN 13 AND 14 THEN 6
				WHEN @HoursBack BETWEEN 15 AND 23 THEN 10
				WHEN @HoursBack BETWEEN 24 AND 35 THEN 15
				WHEN @HoursBack BETWEEN 36 AND 48 THEN 20
			ELSE 1	--shouldn't hit this
			END;
	END
	ELSE
	BEGIN
		SELECT @lv__mtx__WindowLength_minutes = CASE 
				WHEN @HoursBack BETWEEN 1 AND 6 THEN 1
				WHEN @HoursBack BETWEEN 7 AND 12 THEN 2
				WHEN @HoursBack BETWEEN 13 AND 30 THEN 5
				WHEN @HoursBack BETWEEN 31 AND 48 THEN 10
			ELSE 1 --shouldn't hit this
			END;
	END

	--For @HoursBack=1, since our minimum cell width is 1 minute, we only end up with a 60-char wide matrix, and only 1
	-- hour-marker in the header. That doesn't look as good, so let's bump up the size of the matrix (and the time window)
	-- by 30
	IF @HoursBack = 1
	BEGIN
		SET @lv__mtx__MatrixWidth = 90;
	END
	ELSE
	BEGIN
		--Matrix width is easy to calculate once we have window length
		SET @lv__mtx__MatrixWidth = @HoursBack*60 / @lv__mtx__WindowLength_minutes;
	END
	
	--For the "Time Header" line, we want to mark inter-hour "landmarks" to make rough time identification easier.
	--We also want to do something similar for the "Line Header" line
	IF @lv__mtx__WindowLength_minutes IN (1,2)
	BEGIN
		SET @lv__mtx__LineHeaderMod = 10;		--print ticks every 10 minutes
		SET @lv__mtx__TimeHeaderMod = 20;		--print '+' chars every 20 min, but not on the hour
	END
	ELSE IF @lv__mtx__WindowLength_minutes IN (3,5)
	BEGIN
		SET @lv__mtx__LineHeaderMod = 15;
		SET @lv__mtx__TimeHeaderMod = 30;
	END
	ELSE IF @lv__mtx__WindowLength_minutes IN (6,10,15)
	BEGIN
		SET @lv__mtx__LineHeaderMod = 30;
		SET @lv__mtx__TimeHeaderMod = 30;
	END
	ELSE 
		--IF @lv__mtx__WindowLength_minutes = 20		the only other option at this time is 20
	BEGIN
		SET @lv__mtx__LineHeaderMod = -1;
		SET @lv__mtx__TimeHeaderMod = -1;
	END

	--Because (n)varchar strings are trimmed, we use an underscore for most of the string manipulation and then 
	--do a REPLACE(<expr>, @lv__mtx__EmptyChar, N' ') at the end.
	SET @lv__mtx__EmptyChar = N'_';

	--***Location 3: Determine last window of matrix
	--The @PointInTime is very likely NOT the exact endpoint for an x-minute time window. Let's find the endpoint for the
	-- time window that we are in currently.
	BEGIN TRY
		SELECT 
				@lv__mtx__CurrentTime_WindowBegin = ss3.CurrentTime_WindowBegin,
				--Aaron: changing the end time to be equal to the start time of the next window, rather than a few milliseconds before, 
				-- to avoid the off-chance that a job completion slips through the cracks
				--@lv__mtx__CurrentTime_WindowEnd = DATEADD(MILLISECOND, -10, DATEADD(MINUTE, @lv__mtx__WindowLength_minutes, CurrentTime_WindowBegin))
				@lv__mtx__CurrentTime_WindowEnd = DATEADD(MINUTE, @lv__mtx__WindowLength_minutes, CurrentTime_WindowBegin)
			FROM (
				SELECT [CurrentTime_WindowBegin] = DATEADD(MINUTE, NthWindowFromTopOfHour*@lv__mtx__WindowLength_minutes, CurrentTime_HourBase), 
					CurrentTime, 
					CurrentTime_HourBase, 
					CurrentMinute, 
					CurrentHour, 
					NthWindowFromTopOfHour
				FROM (
					SELECT [NthWindowFromTopOfHour] = CurrentMinute / @lv__mtx__WindowLength_minutes,		--zero-based, of course
						[CurrentTime_HourBase] = DATEADD(HOUR, CurrentHour, 
																CONVERT(DATETIME,
																		CONVERT(NVARCHAR(20), CurrentTime, 101)
																		)
														),
						CurrentTime, 
						CurrentMinute, 
						CurrentHour 
					FROM (
						SELECT [CurrentMinute] = DATEPART(MINUTE, CurrentTime), 
							[CurrentHour] = DATEPART(HOUR, CurrentTime),
							CurrentTime
						FROM 
							(SELECT [CurrentTime] = @PointInTime) ss0
						) ss1
					) ss2
			) ss3
			;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Unable to construct the final time window. The job history matrix will not be displayed.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);

		GOTO configstart
	END CATCH

	--Now build our array of time windows for the whole matrix
	BEGIN TRY
		;WITH t0 AS (
			SELECT 0 as col1 UNION ALL
			SELECT 0 UNION ALL
			SELECT 0 UNION ALL
			SELECT 0
		),
		t1 AS (
			SELECT ref1.col1 FROM t0 as ref1
				CROSS JOIN t0 as ref2
				CROSS JOIN t0 as ref3
				CROSS JOIN t0 as ref4
		),
		nums AS (
			SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as rn
			FROM t1
		)
		INSERT INTO #TimeWindows_Hist (WindowID, WindowBegin, WindowEnd, TimeHeaderChar, LineHeaderChar)
		SELECT 
			CellReverseOrder, 
			WindowBegin,
			WindowEnd,
			TimeHeaderChar = (
				CASE 
					--When we are on the top of the hour, we usually print hour information (first digit of a 2-digit hour)
					WHEN NthWindowFromTopOfHour = 0
						THEN (CASE 
								--For @HoursBack>24, print even hours. Otherwise, always print the hour
								WHEN @HoursBack > 24 
									THEN (
										CASE WHEN DATEPART(HOUR, WindowBegin) % 2 = 0 THEN SUBSTRING(CONVERT(NVARCHAR(20),DATEPART(HOUR, WindowBegin)),1,1)
											ELSE N'.'
										END 
									)
								ELSE SUBSTRING(CONVERT(NVARCHAR(20),DATEPART(HOUR, WindowBegin)),1,1)
								END
								)
					--When it is the second window of the hour, we check to see if we have a double-digit hour # and print the second digit
					WHEN NthWindowFromTopOfHour = 1
						THEN (
							CASE WHEN DATEPART(HOUR, WindowBegin) < 10 THEN N'.'
								ELSE SUBSTRING(REVERSE(CONVERT(NVARCHAR(20),DATEPART(HOUR, WindowBegin))),1,1)
							END
						)
					--should we print the Time Header intra-hour marker?
					WHEN @lv__mtx__TimeHeaderMod <> -1 AND DATEPART(MINUTE, WindowBegin) % @lv__mtx__TimeHeaderMod = 0
						THEN (CASE 
								WHEN @HoursBack > 24 THEN '.'		--too high-level for intra-hour markers
								ELSE '+'
							END
						)
					ELSE '.'	--should never hit this case
				END 
				),
			LineHeaderChar = (
				CASE 
					WHEN DATEPART(MINUTE, WindowBegin) % @lv__mtx__LineHeaderMod = 0 THEN '|' 
					ELSE '-'
				END 
				)
		FROM (
			SELECT 
				CellReverseOrder, 
				CurrentTime_WindowBegin, 
				CurrentTime_WindowEnd, 
				WindowBegin, 
				WindowEnd,
				[NthWindowFromTopOfHour] = DATEPART(MINUTE, WindowBegin)  / @lv__mtx__WindowLength_minutes
			FROM (
				SELECT TOP (@lv__mtx__MatrixWidth) 
					rn as CellReverseOrder,
					@lv__mtx__CurrentTime_WindowBegin as CurrentTime_WindowBegin, 
					@lv__mtx__CurrentTime_WindowEnd as CurrentTime_WindowEnd,
					DATEADD(MINUTE, 0-@lv__mtx__WindowLength_minutes*(rn-1), @lv__mtx__CurrentTime_WindowBegin) as WindowBegin,
					DATEADD(MINUTE, 0-@lv__mtx__WindowLength_minutes*(rn-1), @lv__mtx__CurrentTime_WindowEnd) as WindowEnd
				FROM nums 
				ORDER BY rn ASC
			) ss0
		) ss1
		OPTION(MAXDOP 1);
	END TRY
	BEGIN CATCH
		RAISERROR(N'Unable to define the complete list of time window boundaries. The job history matrix will not be displayed.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);

		GOTO configstart
	END CATCH

	IF @Debug = 1
	BEGIN
		SELECT 'Contents of #TimeWindows_Hist' as DebugLocation, tw.WindowID, tw.WindowBegin, tw.WindowEnd, tw.TimeHeaderChar, tw.LineHeaderChar
		FROM #TimeWindows_Hist tw
		ORDER BY tw.WindowID;
	END

	--Get overall min/max times, as we'll use these later in the proc
	SELECT 
		@lv__mtx__OverallWindowBeginTime = MIN(tw.WindowBegin), 
		@lv__mtx__OverallWindowEndTime = MAX(tw.WindowEnd)
	FROM #TimeWindows_Hist tw;

	IF @Debug = 1
	BEGIN
		SELECT [curTime] = GETDATE(),
			curBegin = @lv__mtx__CurrentTime_WindowBegin, 
			[curEnd] = @lv__mtx__CurrentTime_WindowEnd,
			[overallBegin] = @lv__mtx__OverallWindowBeginTime, 
			[overallEnd] = @lv__mtx__OverallWindowEndTime,
			[MatrixWidth] = @lv__mtx__MatrixWidth, 
			[WinLength_min] = @lv__mtx__WindowLength_minutes

		SELECT * 
		FROM #TimeWindows_Hist tw 
		ORDER BY tw.WindowID DESC;
	END

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: constructing Historical Matrix time windows took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END
	
	--Obtain SQL Server and SQL Agent start times
	SET @lv__beforedt = GETDATE();

	SELECT @lv__mtx__SQLServerStartTime = d.create_date 
	FROM sys.databases d 
	WHERE d.database_id = 2;

	SELECT @lv__mtx__SQLAgentStartTime = ss.agent_start_date
	FROM (
		SELECT TOP 1 s.agent_start_date
		FROM msdb.dbo.syssessions s
		WHERE s.agent_start_date < @lv__mtx__OverallWindowEndTime
		ORDER BY s.agent_start_date DESC
	) ss;

	--Our @PointInTime could be older than the most recent SQL Server restart time. Since SQL Server log files can be quite large, we are not going
	-- to go digging in them for the previous restart time.
	IF @lv__mtx__SQLServerStartTime IS NOT NULL
	BEGIN
		IF @lv__mtx__SQLServerStartTime > @lv__mtx__OverallWindowEndTime
		BEGIN
			SET @lv__mtx__SQLStartTimeResult = 2;
		END
		ELSE 
		BEGIN
			SET @lv__mtx__SQLStartTimeResult = 1;
		END
	END

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: obtaining SQL Server and Agent start times took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	--Get da jobs
	BEGIN TRY
		INSERT INTO #Jobs (
			JobName, 
			IsEnabled, 
			Notifies, 
			CreateDate, 
			LastModifiedDate,  
			OwnerPrincipalName,
			native_job_id, 
			JobRuns, 
			JobFailures, 
			MatrixNumber, 
			DisplayOrder)
		SELECT 
			j.name, 
			j.enabled, 
			CASE WHEN j.notify_level_email > 0 OR j.notify_level_netsend > 0 OR j.notify_level_page > 0 THEN 1 ELSE 0 END,
			j.date_created, 
			j.date_modified,
			p.name,
			j.job_id, 
			0, 
			0, 
			5,	--start off assuming that each job lacks a successful completion. We'll change this field after examining job history
			ROW_NUMBER() OVER (ORDER BY j.name ASC)
		FROM msdb.dbo.sysjobs j 
			INNER JOIN sys.server_principals p
				ON j.owner_sid = p.sid 
		WHERE 1=1
		/*
		j.date_created < @lv__mtx__OverallWindowEndTime		--Don't show a job if it didn't exist before the end time of our matrix
															NOTE: changed for now... putting job names in parentheses
		*/
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Unable to obtain a list of jobs from msdb.dbo.sysjobs. The job matrix will not be displayed.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);

		GOTO configstart
	END CATCH

	
	IF NOT EXISTS (SELECT 1 FROM #Jobs)
	BEGIN
		PRINT ('No SQL Agent jobs found on this instance. The job matrix will be not printed')
		SET @output__DisplayMatrix = 0;

		GOTO configstart
	END

	SET @lv__afterdt = GETDATE();

	IF @Debug = 1
	BEGIN
		SELECT j.JobID, j.JobName, j.native_job_id, j.IsEnabled, j.JobRuns, j.JobFailures, j.MatrixNumber, j.DisplayOrder
		FROM #Jobs j
		ORDER BY j.JobName ASC
	END

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: obtaining list of jobs took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END


	SET @lv__beforedt = GETDATE();

	--Get job completion information
	--The msdb.dbo.sysjobhistory table stores the relevant info in a format that isn't easy to use naturally. Convert the relevant data first.
	BEGIN TRY
		;WITH Job_Completions AS (
			SELECT job_id, run_status, run_date, run_time, run_duration,
				JobStartTime,  	
				[JobEndTime] = (
					DATEADD(HOUR, 
						CONVERT(INT,REVERSE(SUBSTRING(DurationReversed, 5,6))), 
						DATEADD(MINUTE, 
							CONVERT(INT,REVERSE(SUBSTRING(DurationReversed, 3,2))),
							DATEADD(SECOND,
								CONVERT(INT,REVERSE(SUBSTRING(DurationReversed, 1,2))),
								JobStartTime
								)
							)
						)
					)
			FROM (
				SELECT h.job_id
					,h.run_status
					,h.run_date, h.run_time, h.run_duration
					,[JobStartTime] = (
						CASE WHEN (h.run_date IS NULL OR h.run_Time IS NULL 
								OR h.run_date < 19000101 OR h.run_time < 0
								OR h.run_time > 235959)
								THEN NULL 
							ELSE CAST(STR(h.run_date, 8, 0) AS DATETIME) + 
								CAST(STUFF(STUFF(REPLACE(STR(h.run_time, 6), ' ', '0'), 3, 0, ':'), 6, 0, ':') AS DATETIME)
							END)
					,[DurationReversed] = CASE
						WHEN h.run_duration IS NULL THEN NULL 
						WHEN h.run_duration < 0 THEN NULL
						ELSE REVERSE(REPLACE(STR(h.run_duration, 10),' ', '0'))
						END 
				FROM msdb.dbo.sysjobhistory h WITH (NOLOCK)
				WHERE h.step_id = 0		--only look at completion states
			) ss
		) 
		INSERT INTO #JobInstances (native_job_id, job_run_status, JobStartTime, JobEndTime, JobDisplayEndTime)
		SELECT 
			jc.job_id 
			
			--We need to handle when @PointInTime is in the past; jobs that have finished now may have been running
			-- at the "end time" the user has requested.
			,CASE WHEN @lv__mtx__OverallWindowEndTime BETWEEN jc.JobStartTime AND jc.JobEndTime
				THEN 25  --special code for "Running"
				ELSE jc.run_status 
			 END

			,jc.JobStartTime
			,jc.JobEndTime
			,jc.JobEndTime			--since all of these jobs have already finished, the display time = the actual endtime
		FROM Job_Completions jc
		OPTION(MAXDOP 1);
	END TRY
	BEGIN CATCH
		RAISERROR(N'Unable to obtain job completion information. The job matrix will not be displayed.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);

		GOTO configstart
	END CATCH


	--Get currently-running jobs
	--Now, we want to check for jobs that are currently running. (A job could have been running for the last 2 hours
	-- and it won't be in the #JobInstances table yet because the h.step_id=0 record doesn't exist until the job completes)
	
	--Note that we still need to do this even when @PointInTime is for many hours back, since a job could have been running VERY
	-- long amounts of time. 
	BEGIN TRY
		INSERT INTO #CurrentlyRunningJobs1 
			EXECUTE master.dbo.xp_sqlagent_enum_jobs 1, 'derp de derp';

		INSERT INTO #CurrentlyRunningJobs2
			(native_job_id, JobStartTime, JobEndTime, JobDisplayEndTime)
		SELECT 
			ss.native_job_id, ss.JobStartTime, NULL, ss.JobDisplayEndTime
		FROM (
			SELECT
				[native_job_id] = ja.job_id, 
				[JobStartTime] = ja.start_execution_date, 
				[JobDisplayEndTime] = DATEADD(MINUTE, 1, @lv__mtx__OverallWindowEndTime),		--since a running job will, by definition, always have a '~' or '!' character in 
																	--the last matrix cell, we just push its end-time out just beyond the last time window
																	--note that this doesn't mess up our "historical average" calculation since we only look at
																	-- completed job instances for that calc
				rn = ROW_NUMBER() OVER (PARTITION BY ja.job_id ORDER BY ja.start_execution_date DESC)
			FROM msdb.dbo.sysjobactivity ja
			WHERE ja.start_execution_date IS NOT NULL
			AND ja.start_execution_date <= @lv__mtx__OverallWindowEndTime	--When @PointInTime is in the past, this may avoid inserting rows that aren't relevant: 
																			--jobs that started after our overall window end time
			AND ja.stop_execution_date IS NULL
		) ss
		WHERE ss.rn = 1			--if sysjobactivity has 2 or more NULL-stop records for the same job, we want the most recent one.

		--Since the sysjobactivity view can have records that actually refer to job instances that never finished (e.g. when SQL Agent was
		-- stopped suddenly), we need to cross-check the data with the results from xp_sqlagent_enum_jobs. Thus, sysjobactivity gets
		-- us the start time for a running job, and xp_sqlagent_enum_jobs gets us assurance that a job really is currently running.
		AND EXISTS (
			SELECT * 
			FROM #CurrentlyRunningJobs1 t
			WHERE t.Job_ID = ss.native_job_id
			AND t.Running = 1
		)
		;

		INSERT INTO #JobInstances
		(native_job_id, job_run_status, JobStartTime, JobEndTime, JobDisplayEndTime)
		SELECT native_job_id, 25, --special code that means "running"
			JobStartTime, JobEndTime, JobDisplayEndTime
		FROM #CurrentlyRunningJobs2;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while obtaining information about currently-running jobs. The job history matrix may be incomplete.', 11, 1);
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
		--in this case, we do NOT skip the rest of the historical matrix logic.
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: obtaining job completions and currently-running jobs took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END
	SET @lv__beforedt = GETDATE();

	--Average job duration
	--Calculate the average duration for each job success (in seconds), and then apply that to the #JobInstances table so that
	-- down below we can determine whether a job instance has run longer than its average
	BEGIN TRY
		--Note that for @PointInTime values in the past, our average runtime calculation may be affected by jobs that succeeded
		-- AFTER @PointInTime. I have debated whether this is appropriate or not.
		-- TODO: reconsider using a rolling average in the future.
		UPDATE targ
		SET targ.JobRuns = ss1.JobRuns,
			targ.JobFailures = ss1.JobFailures,
			targ.MatrixNumber = CASE WHEN ss1.JobFailures > 0 OR ss1.IsCurrentlyRunning > 0 THEN 1 
									WHEN ss1.JobFailures = 0 AND ss1.JobRuns >= 1 THEN 3
									ELSE 5
								END,
			targ.CompletionsAllTime = ss1.CompletionsAllTime,
			targ.AvgJobDur_seconds = CASE WHEN ss1.CompletionsAllTime = 0 THEN 0 
										ELSE ss1.AllDuration / ss1.CompletionsAllTime END,
			targ.AvgSuccessDur_seconds = CASE WHEN ss1.CompletionsAllTime = 0 THEN 0 
										ELSE ss1.SuccessDuration / ss1.CompletionsAllTime END
		FROM #Jobs targ
			INNER JOIN (
			SELECT native_job_id,
				[CompletionsAllTime] = SUM(CompletionsAllTime),
				[SuccessDuration] = SUM(SuccessDuration),
				[AllDuration] = SUM(AllDuration),
				[JobFailures] = SUM(JobFailures),
				[IsCurrentlyRunning] = SUM(IsCurrentlyRunning), 
				[JobRuns] = SUM(JobRuns)
			FROM (
				SELECT 
					ji1.native_job_id,
					--the Count metrics are only supposed to reflect the time within our historical matrix window, and thus may
					-- include our currently-running jobs, while the average duration metrics are supposed to reflect all of our history, 
					-- but not our currently-running jobs (since they haven't finished yet)

					--Avgdur (all history)
					[CompletionsAllTime] = CASE WHEN ji1.JobEndTime IS NULL THEN 0 ELSE 1 END,

					[SuccessDuration] = CASE WHEN ji1.JobEndTime IS NULL OR ji1.job_run_status <> 1 
											THEN 0 ELSE DATEDIFF(SECOND, JobStartTime, JobEndTime) END,

					[AllDuration] = CASE WHEN ji1.JobEndTime IS NULL THEN 0 ELSE DATEDIFF(SECOND, JobStartTime, JobEndTime) END,

					-- count (just this window)
					[JobFailures] = CASE WHEN ji1.job_run_status NOT IN (1,25) 
											AND JobStartTime <= @lv__mtx__OverallWindowEndTime
											AND ISNULL(JobEndTime,@lv__mtx__OverallWindowBeginTime) >= @lv__mtx__OverallWindowBeginTime 
										THEN 1 ELSE 0 END,

					[IsCurrentlyRunning] = CASE WHEN ji1.job_run_status = 25 
											AND JobStartTime <= @lv__mtx__OverallWindowEndTime
										THEN 1 ELSE 0 END,

					[JobRuns] = CASE WHEN JobStartTime <= @lv__mtx__OverallWindowEndTime
										AND ISNULL(JobEndTime,@lv__mtx__OverallWindowBeginTime) >= @lv__mtx__OverallWindowBeginTime
									THEN 1 ELSE 0 END

				FROM #JobInstances ji1
			) ss0
			GROUP BY native_job_id
		) ss1
			ON targ.native_job_id = ss1.native_job_id
		;


		UPDATE ji1 
		--TODO: might want to make this configurable, where the user can choose whether to include failures in the 
		-- average duration info.
		SET JobExpectedEndTime = DATEADD(SECOND, j.AvgSuccessDur_seconds, ji1.JobStartTime) 
		FROM #JobInstances ji1
			INNER JOIN #Jobs j
				ON ji1.native_job_id = j.native_job_id
		;

		--Now that we have average duration, delete the job instances that we know don't matter anymore
		DELETE FROM #JobInstances 
		WHERE 
			--Any job that completed before our overall Window start time is irrelevant
			--Likewise, any job that started after our overall Window start time is also irrelevant
			--Note, however, that jobs that started before our Window can still be relevant if they ended
			-- AFTER our window started. 
			JobEndTime < @lv__mtx__OverallWindowBeginTime
			OR 
			JobStartTime > @lv__mtx__OverallWindowEndTime
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while calculating average job runtime information and doing JI cleanup.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);

		GOTO configstart
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: calculating average durations and JI cleanup took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	BEGIN TRY
		INSERT INTO #JobArrays (JobID, WindowID, WindowBegin, WindowEnd, CellText)
		SELECT ss.JobID, tw.WindowID, tw.WindowBegin, tw.WindowEnd, @lv__mtx__EmptyChar
		FROM (
			SELECT j.JobID
			FROM #Jobs j
			) ss
			CROSS JOIN #TimeWindows_Hist tw
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while creating the historical job array. The job history matrix will not be displayed.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: constructing the Job Arrays took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	--Cell population for failures
	--Ok, first, update the arrays with any job failures. If a failure has occurred in a Time Window, then we mark that 
	-- time window with an 'X'
	BEGIN TRY 
		UPDATE targ
		SET targ.CellText = CASE WHEN xapp1.job_run_status = 0 THEN 'F'
								WHEN xapp1.job_run_status = 2 THEN 'R'
								WHEN xapp1.job_run_status = 3 THEN 'C'
							ELSE 'X'
							END
		FROM #JobArrays targ
			INNER JOIN #Jobs j
				ON targ.JobID = j.JobID
			CROSS APPLY (		--the use of CROSS rather than OUTER apply is important here. 
					SELECT TOP 1 jc.job_run_status 
					FROM #JobInstances jc
					WHERE j.native_job_id = jc.native_job_id
					AND jc.job_run_status <> 1
					AND jc.JobDisplayEndTime >= targ.WindowBegin
					AND jc.JobDisplayEndTime < targ.WindowEnd	--remember, endpoint of our window is NOT inclusive (because it is the same as the start of the subsequent window)
					ORDER BY jc.job_run_status ASC		--0 (failure) will sort first, 2 (retry) will sort second, and 3 (cancelled) will sort third
						--note that even if there are multiple jobs with the same run_status value, we don't really care, since we just pull the status
				) xapp1
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while populating Matrix with job failures. The job history matrix will not be displayed.', 11, 1);
		SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: populating Matrix with job failures took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END 

	SET @lv__beforedt = GETDATE();

	--Cell population for successes
	--Now, update the array with info on the # of SUCCESSFUL job completions in a given time block. 
	-- Note that we NEVER overwrite a cell that has already been written to.
	BEGIN TRY
		;WITH JobWindowsWithSuccesses AS (
			SELECT ja.JobID, ja.WindowID, 
				COUNT(*) AS NumSuccessfulCompletions
			FROM #JobArrays ja
				INNER JOIN #Jobs j
					ON ja.JobID = j.JobID
				INNER JOIN #JobInstances jc
					ON j.native_job_id = jc.native_job_id
			WHERE ja.CellText = @lv__mtx__EmptyChar
			AND jc.job_run_status = 1
			AND jc.JobDisplayEndTime >= ja.WindowBegin
			AND jc.JobDisplayEndTime < ja.WindowEnd	--remember, endpoint of our window is NOT inclusive (because it is the same as the start of the subsequent window)
			GROUP BY ja.JobID, ja.WindowID, ja.WindowBegin, ja.WindowEnd
		)
		UPDATE targ
		SET targ.CellText = CASE WHEN jw.NumSuccessfulCompletions >= 9 THEN '9'
								WHEN jw.NumSuccessfulCompletions = 1 THEN '/'
								ELSE CONVERT(CHAR(1), jw.NumSuccessfulCompletions)
								END
		FROM #JobArrays targ
			INNER JOIN JobWindowsWithSuccesses jw
				ON targ.JobID = jw.JobID
				AND targ.WindowID = jw.WindowID
		WHERE jw.NumSuccessfulCompletions > 0
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while populating Matrix with job successes. The job history matrix will not be displayed.', 11, 1);
		--SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: populating Matrix with job successes took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END 

	SET @lv__beforedt = GETDATE();

	--Cell population for starts
	BEGIN TRY
		;WITH JobStarts AS (
			SELECT ja.JobID, ja.WindowID
			FROM #JobArrays ja
				INNER JOIN #Jobs j
					ON ja.JobID = j.JobID
			WHERE ja.CellText = @lv__mtx__EmptyChar
			AND EXISTS (SELECT * FROM #JobInstances jc
					WHERE j.native_job_id = jc.native_job_id
					AND jc.JobStartTime >= ja.WindowBegin
					AND jc.JobStartTime < ja.WindowEnd	--remember, endpoint of our window is NOT inclusive (because it is the same as the start of the subsequent window)
					)
		)
		UPDATE targ 
		SET targ.CellText = '^'
		FROM #JobArrays targ
			INNER JOIN JobStarts js
				ON targ.JobID = js.JobID
				AND targ.WindowID = js.WindowID
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while populating the Matrix with job starts. The job history matrix will not be displayed.', 11, 1);
		--SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: populating Matrix with job starts took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	--Cell population for "running"
	--Ok, our final update to the array is to mark all cells with a '~' or '!' where a job was running during that window, but its start was before
	-- the time window started and its end is after the time window started.
	BEGIN TRY
		UPDATE ja
		SET CellText = CASE WHEN xapp1.JobExpectedEndTime < ja.WindowBegin THEN '!'
						ELSE '~'
						END
		FROM #JobArrays ja
			INNER JOIN #Jobs j
				ON ja.JobID = j.JobID
			CROSS APPLY (
					SELECT TOP 1	--there should only be 1 row anyway...
						ji.JobExpectedEndTime
					FROM #JobInstances ji
					WHERE ji.native_job_id = j.native_job_id
					AND ji.JobStartTime < ja.WindowBegin
					AND ji.JobDisplayEndTime >= ja.WindowEnd		--remember, WindowEnd is actually NOT inclusive
					) xapp1
		WHERE ja.CellText = @lv__mtx__EmptyChar
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while populating the Matrix with "job running" info. The job history matrix will not be displayed.', 11, 1);
		--SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 1
	BEGIN
		SELECT ja.JobID, ja.WindowID, ja.WindowBegin, ja.WindowEnd, ja.CellText
		FROM #JobArrays ja
		ORDER BY ja.JobID, ja.WindowID
	END

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: populating Matrix with "running" tokens took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	--Determine how many characters of the job name we'll be printing (potentially all)
	SELECT @lv__mtx__MaxJobNameLength = MAX(LEN(col1))
	FROM (
		SELECT col1 = (
			CASE WHEN j.IsEnabled = 0 THEN N'*' ELSE N'$' END +
				CONVERT(NVARCHAR(20),j.JobRuns) + N'/' + CONVERT(NVARCHAR(20),j.JobFailures) + N'  ' + 
				CASE WHEN j.CreateDate > @lv__mtx__OverallWindowEndTime
							THEN N'(' + j.JobName + N')'
						ELSE j.JobName
					END
			)
		FROM #Jobs j
	) ss0;

	--TODO: consider some way of customizing the max length under different circumstances (@ToConsole values, @FitOnScreen values, a user-specified param, etc)
	SET @lv__mtx__MaxJobNameLength = (
			CASE WHEN @lv__mtx__MaxJobNameLength IS NULL THEN 1		--no SQL Agent jobs exist! we shouldn't reach this point
				WHEN @lv__mtx__MaxJobNameLength <= 55 THEN @lv__mtx__MaxJobNameLength	--50 chars is fine whatever the output
				ELSE 55
			END 
			);

	--Construct the header lines
	SET @lv__mtx__HeaderHours = N'';
	SET @lv__mtx__HeaderLine = N'';

	SELECT @lv__mtx__HeaderHours = @lv__mtx__HeaderHours + tw.TimeHeaderChar
	FROM #TimeWindows_Hist tw
	ORDER BY tw.WindowID DESC;

	SELECT @lv__mtx__HeaderLine = @lv__mtx__HeaderLine + tw.LineHeaderChar
	FROM #TimeWindows_Hist tw
	ORDER BY tw.WindowID DESC;

	--Creation of the output strings (before final concatenation, in sub-matrices)

	/* Our matrix is really several sub-matrices. Each matrix holds certain "categories" of jobs, based on those jobs' runs/failures/enabled/disabled status:

		For now, here's how we'll organize them:
		Historical matrix:
				Matrix 1
					Jobs that have had a failure or are currently running  (whether disabled or not)
																						(use MatrixNumber=2 for a spacer line)
				Matrix 3
					Jobs not in Matrix 1 that have had at least 1 run
																						(use MatrixNumber=4 for a spacer line)
				Matrix 5
					All other jobs (jobs that haven't run at all, whether disabled or not)

		Predictive matrix:
				Matrix 1
					Jobs that had at least 1 "run" during the window
																						(use MatrixNumber=2 for a spacer line)
				Matrix 3
					Jobs that didn't "run" during the window
							
	*/

	INSERT INTO #OutputStringLineItems
		(RowType, JobID, MatrixNumber, DisplayOrder, CellString)
	SELECT 0,		-1,			-1,			1,			CASE WHEN @FitOnScreen = 'Y' THEN '' 
															ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
															END + N'$' + @lv__mtx__HeaderHours
	UNION ALL 
	SELECT 1,		-1,			-1,			1,			CASE WHEN @FitOnScreen = 'Y' THEN '' 
															ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
															END + N'$' + @lv__mtx__HeaderLine
	;

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: obtaining max job name length and header output lines took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	BEGIN TRY 
		INSERT INTO #OutputStringLineItems
		(RowType, JobID, CellString)
		SELECT 2,
			ja1.JobID, 
			CellString = (
						SELECT [*] = ja2.CellText
						FROM #JobArrays as ja2
						WHERE ja2.JobID = ja1.JobID
						ORDER BY ja2.WindowID DESC
						FOR XML PATH(N'')
					)
		FROM #JobArrays AS ja1
		GROUP BY ja1.JobID
		ORDER BY JobID;

		UPDATE targ 
		SET MatrixNumber = j.MatrixNumber, 
			DisplayOrder = j.DisplayOrder
		FROM #OutputStringLineItems targ
			INNER JOIN #Jobs j
				ON targ.JobID = j.JobID
		;

		UPDATE targ  
		SET targ.CellString = (
				CASE 
					WHEN @FitOnScreen = 'Y' 
						THEN N'|' + targ.CellString + N'|' + ss.JobName
					ELSE SUBSTRING(ss.JobName,1,@lv__mtx__MaxJobNameLength) + N'|' + targ.CellString + N'|'
					END
			)
		FROM #OutputStringLineItems targ
			INNER JOIN (
					SELECT j.JobID, 
						[JobName] = CASE WHEN j.IsEnabled = 0 THEN N'*' ELSE N' ' END +
						CONVERT(NVARCHAR(20),j.JobRuns) + N'/' + CONVERT(NVARCHAR(20),j.JobFailures) + N'  ' + 
						CASE WHEN j.CreateDate > @lv__mtx__OverallWindowEndTime
								THEN N'(' + j.JobName + N')'
							ELSE j.JobName
						END + REPLICATE('$', 50)
					FROM #Jobs j
					) ss
				ON targ.JobID = ss.JobID
		;
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while constructing output strings from job array table. The job history matrix will not be displayed.', 11, 1);
		--SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: constructing output strings from job arrays took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END


	SET @lv__beforedt = GETDATE();

	--Matrices 1,3,5 hold actual rows, while 2,4,6 are labels indicating which matrix it is.
	-- The below labels are all intentionally the same length (39 chars)
	BEGIN TRY
		SET @lv__mtx__Replicate1 = (@lv__mtx__MatrixWidth - 39) / 2 + 1
		SET @lv__mtx__Replicate2 = @lv__mtx__MatrixWidth - 39 - @lv__mtx__Replicate1

		INSERT INTO #OutputStringLineItems
			(RowType, JobID, MatrixNumber, DisplayOrder, CellString)
		SELECT 2,		-1,		2,			1, 
			CASE WHEN @FitOnScreen = 'Y' THEN '' 
			ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
			END + N'|' + REPLICATE(N'*', @lv__mtx__Replicate1) + N'Currently-running or at least 1 failure' + REPLICATE(N'*', @lv__mtx__Replicate2) + N'|' + NCHAR(10) + NCHAR(13) + NCHAR(10) + NCHAR(13)+ NCHAR(10) + NCHAR(13)
		UNION ALL
		SELECT 2,		-1,		4,			1, 
			CASE WHEN @FitOnScreen = 'Y' THEN '' 
			ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
			END + N'|' + REPLICATE(N'*', @lv__mtx__Replicate1) + N'Executed >= 1 time and always succeeded' + REPLICATE(N'*', @lv__mtx__Replicate2) + N'|' + NCHAR(10) + NCHAR(13) + NCHAR(10) + NCHAR(13)+ NCHAR(10) + NCHAR(13)
		UNION ALL 
		SELECT 2,		-1,		6,			1,
			CASE WHEN @FitOnScreen = 'Y' THEN '' 
			ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
			END + N'|' + REPLICATE(N'*', @lv__mtx__Replicate1) + N'Did not execute during this time window' + REPLICATE(N'*', @lv__mtx__Replicate2) + N'|' + NCHAR(10) + NCHAR(13) + NCHAR(10) + NCHAR(13)+ NCHAR(10) + NCHAR(13)
		;

		--Decide whether to re-print the header for second and third sub-matrices
		--If there are a lot of job rows in matrix #1 (Currently-running or at least 1 failure), then the user will have to scroll down to see the jobs in 
		-- matrix #3 (Executed >= 1 time, always succeeded). Similarly, if there are a lot of rows in matrix #3, then when the user scrolls down to see them, 
		-- the header rows will not be visible and the user will have to keep scrolling up and down to match times to matrix info. To avoid this, we 
		-- check the # of lines in matrices #1 and #3 combined, and if the result is > a threshold, we add header rows in to matrix 3 as well.
		SELECT 
			@lv__mtx__CountMatrixRows_1 = SUM(CASE WHEN o.MatrixNumber = 1 THEN 1 ELSE 0 END),
			@lv__mtx__CountMatrixRows_3 = SUM(CASE WHEN o.MatrixNumber = 3 THEN 1 ELSE 0 END),
			@lv__mtx__CountMatrixRows_5 = SUM(CASE WHEN o.MatrixNumber = 5 THEN 1 ELSE 0 END)
		FROM #OutputStringLineItems o;

		SET @lv__mtx__Matrix3HasHeader = 0;
		IF (@lv__mtx__CountMatrixRows_1 + @lv__mtx__CountMatrixRows_3) >= 35
		BEGIN
			INSERT INTO #OutputStringLineItems
				(RowType, JobID, MatrixNumber, DisplayOrder, CellString)
			SELECT 0,		-1,			3,			1,			CASE WHEN @FitOnScreen = 'Y' THEN '' 
																ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
																END + N'$' + @lv__mtx__HeaderHours
			UNION ALL 
			SELECT 1,		-1,			3,			1,			CASE WHEN @FitOnScreen = 'Y' THEN '' 
																ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
																END + N'$' + @lv__mtx__HeaderLine
			;

			SET @lv__mtx__Matrix3HasHeader = 1;
		END

		--We need similar logic for Matrix 5
		IF (@lv__mtx__Matrix3HasHeader = 0 AND (@lv__mtx__CountMatrixRows_1 + @lv__mtx__CountMatrixRows_3 + @lv__mtx__CountMatrixRows_5) >= 30)
			OR (@lv__mtx__Matrix3HasHeader = 1 AND (@lv__mtx__CountMatrixRows_3 + @lv__mtx__CountMatrixRows_5) >= 35 )
		BEGIN
			INSERT INTO #OutputStringLineItems
				(RowType, JobID, MatrixNumber, DisplayOrder, CellString)
			SELECT 0,		-1,			5,			1,			CASE WHEN @FitOnScreen = 'Y' THEN '' 
																ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
																END + N'$' + @lv__mtx__HeaderHours
			UNION ALL 
			SELECT 1,		-1,			5,			1,			CASE WHEN @FitOnScreen = 'Y' THEN '' 
																ELSE REPLICATE('$', @lv__mtx__MaxJobNameLength)
																END + N'$' + @lv__mtx__HeaderLine
		END
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while constructing sub-matrix headers. The job history matrix will not be displayed.', 11, 1);
		--SET @output__DisplayMatrix = 0;
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: Sub-matrix headers took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	SET @lv__beforedt = GETDATE();

	--Ok, assemble final output
	SET @lv__OutputVar = N'';

	BEGIN TRY
		SELECT @lv__OutputVar = @lv__OutputVar + 
			REPLACE(REPLACE(CellString,N'_', N' '),N'$', N' ') + NCHAR(10) + 
			CASE WHEN RowType < 2 OR MatrixNumber IN (2,4,6)
				THEN N'' 
				ELSE (	N'' --Printing underscores as spacer lines proved to be uglier than just having each line follow consecutively
					/*
						CASE WHEN @Matrix_PrintUnderscores = N'Y' 
							THEN N'|' + REPLICATE(N'_', 156) + N'|' + NCHAR(10)
							ELSE N'' 
						END 
					*/
					)
			END 
		FROM #OutputStringLineItems
		ORDER BY MatrixNumber, RowType, DisplayOrder
		;

		SET @lv__mtx__PrintOverallBeginTime = CONVERT(VARCHAR(20),@lv__mtx__OverallWindowBeginTime,107) + N' ' + CONVERT(VARCHAR(20),@lv__mtx__OverallWindowBeginTime,108) + N'.' + CONVERT(VARCHAR(20),DATEPART(MILLISECOND, @lv__mtx__OverallWindowBeginTime))
		SET @lv__mtx__PrintOverallEndTime = CONVERT(VARCHAR(20),@lv__mtx__OverallWindowEndTime,107) + N' ' + CONVERT(VARCHAR(20),@lv__mtx__OverallWindowEndTime,108) + N'.' + CONVERT(VARCHAR(20),DATEPART(MILLISECOND, @lv__mtx__OverallWindowEndTime))

		SET @lv__mtx__Replicate1 = @lv__mtx__MatrixWidth - LEN(@lv__mtx__PrintOverallBeginTime) - LEN(@lv__mtx__PrintOverallEndTime);

		SET @lv__OutputVar = 
				CASE WHEN @outputType__Matrix = N'XML' THEN N'<?JobHistory -- ' + NCHAR(10)
					ELSE N'' END + 
				--HoursBack and cell minute width labels
				N'@HoursBack parameter value: ' + CONVERT(NVARCHAR(20),@HoursBack) + N'   Each matrix cell = ' + CONVERT(NVARCHAR(20),@lv__mtx__WindowLength_minutes) + N' minute(s)' + 

				--SQL/Agent Starttime labels
				CASE WHEN @lv__mtx__SQLServerStartTime IS NULL THEN N'***** WARNING: could not determine last SQL Server DB engine start time *****'
						WHEN @lv__mtx__SQLServerStartTime = 2 THEN N'***** NOTE: SQL Server has started up at least once since the end time of this matrix *****'
					WHEN @lv__mtx__SQLServerStartTime BETWEEN @lv__mtx__OverallWindowBeginTime AND @lv__mtx__OverallWindowEndTime 
						THEN NCHAR(10) + N'***** SQL Server DB engine started at ' + CONVERT(VARCHAR(20),@lv__mtx__SQLServerStartTime,107) + N' ' + 
								CONVERT(VARCHAR(20),@lv__mtx__SQLServerStartTime,108) + N'.' + CONVERT(VARCHAR(20),DATEPART(MILLISECOND, @lv__mtx__SQLServerStartTime)) + N' *****'
					ELSE N''
				END +

				CASE WHEN @lv__mtx__SQLAgentStartTime IS NULL THEN N'***** WARNING: could not determine last SQL Agent start time *****'
					WHEN @lv__mtx__SQLAgentStartTime = 2 THEN N'***** NOTE: Could not find the Agent start time immediately preceding this matrix *****'
					WHEN @lv__mtx__SQLAgentStartTime BETWEEN @lv__mtx__OverallWindowBeginTime AND @lv__mtx__OverallWindowEndTime 
						AND ABS(DATEDIFF(MINUTE, @lv__mtx__SQLServerStartTime, @lv__mtx__SQLAgentStartTime)) > 1
						THEN NCHAR(10) + N'***** SQL Agent started at ' + CONVERT(VARCHAR(20),@lv__mtx__SQLAgentStartTime,107) + N' ' + 
								CONVERT(VARCHAR(20),@lv__mtx__SQLAgentStartTime,108) + N'.' + CONVERT(VARCHAR(20),DATEPART(MILLISECOND, @lv__mtx__SQLAgentStartTime)) + N' *****'
					ELSE N''
				END + NCHAR(10) + NCHAR(13) +

				--Begin/End timestamp labels
				N' ' + CASE WHEN @FitOnScreen = 'N' THEN REPLICATE(' ', @lv__mtx__MaxJobNameLength) ELSE '' END + @lv__mtx__PrintOverallBeginTime + REPLICATE(N' ', @lv__mtx__Replicate1) + @lv__mtx__PrintOverallEndTime + N' ' + NCHAR(10) + 
			@lv__OutputVar + 
			CASE WHEN @outputType__Matrix = N'XML' THEN NCHAR(10) + NCHAR(13) + N'-- ?>'
				ELSE N'' END
			;

			INSERT INTO #PreXML
			(OrderingNumber, ReturnType, LongString)
			SELECT 1, N'matrix', @lv__OutputVar 
	END TRY
	BEGIN CATCH
		RAISERROR(N'Error occurred while constructing the final Matrix output string. The job history matrix will not be displayed.', 11, 1);
		SELECT @lv__ErrorText = ERROR_MESSAGE(), 
				@lv__ErrorSeverity	= ERROR_SEVERITY(), 
				@lv__ErrorState = ERROR_STATE();
		SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

		RAISERROR( @lv__ErrorText, 11, 1);
	END CATCH

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: constructing final Matrix output took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	/* 

														Part 2: SQL Agent Configuration Options
	*/
configstart: 

	IF @DisplayConfigOptions > 0
	BEGIN
		SET @lv__beforedt = GETDATE();
		--Obtain info from the registry
		BEGIN TRY
			--Reminder: xp_instance_regread will convert the value to the proper instance location if it isn't a default instance
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'JobHistoryMaxRows',@lv__cfg__MaxHistoryRows OUTPUT,N'no_output';
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'JobHistoryMaxRowsPerJob',@lv__cfg__MaxHistoryRowsPerJob OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'RestartSQLServer',@lv__cfg__ShouldAgentRestartSQL OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'ErrorLogFile',@lv__cfg__errorlog_file OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'ErrorLoggingLevel',@lv__cfg__errorlogging_level OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'ErrorMonitor',@lv__cfg__error_recipient OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'MonitorAutoStart',@lv__cfg__monitor_autostart OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'ServerHost',@lv__cfg__local_host_server OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'JobShutdownTimeout',@lv__cfg__job_shutdown_timeout OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'LoginTimeout',@lv__cfg__login_timeout OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'IdleCPUPercent',@lv__cfg__idle_cpu_percent OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'IdleCPUDuration',@lv__cfg__idle_cpu_duration OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'OemErrorLog',@lv__cfg__oem_errorlog OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'AlertReplaceRuntimeTokens',@lv__cfg__alert_replace_runtime_tokens OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'CoreEngineMask',@lv__cfg__cpu_poller_enabled OUTPUT
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'UseDatabaseMail',@lv__cfg__use_databasemail OUTPUT;
			EXECUTE master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',N'DatabaseMailProfile',@lv__cfg__databasemail_profile OUTPUT;

			SELECT @lv__cfg__tmpregstr = (N'SYSTEM\CurrentControlSet\Services\' + 
						CASE WHEN SERVERPROPERTY('INSTANCENAME') IS NOT NULL
							THEN N'SQLAgent$' + CONVERT (sysname, SERVERPROPERTY('INSTANCENAME'))
							ELSE N'SQLServerAgent'
							END);
			EXECUTE master.dbo.xp_regread N'HKEY_LOCAL_MACHINE',@lv__cfg__tmpregstr,N'Start',@lv__cfg__ServiceStartupSetting OUTPUT;
		END TRY
		BEGIN CATCH
			RAISERROR(N'Error occurred while obtaining Agent config values. Comparison of config option values with defaults will not occur.', 11, 1);
			SET @output__DisplayConfig = 0;
			SELECT @lv__ErrorText = ERROR_MESSAGE(), 
					@lv__ErrorSeverity	= ERROR_SEVERITY(), 
					@lv__ErrorState = ERROR_STATE();
			SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

			RAISERROR( @lv__ErrorText, 11, 1);

			GOTO afterconfig
		END CATCH

		SET @lv__afterdt = GETDATE();

		IF @Debug = 2
		BEGIN
			IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
			BEGIN
				SET @lv__ErrorText = N'   ***dbg: obtaining SQL Agent config from registry took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
				RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
			END
		END

		SET @lv__beforedt = GETDATE();

		BEGIN TRY
			--Determine which config options we need to return to the user
			IF ISNULL(@lv__cfg__MaxHistoryRows,-1) <> 1000
				OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Max History Rows', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__MaxHistoryRows),N'<null>'), N'1000';
			END

			IF ISNULL(@lv__cfg__MaxHistoryRowsPerJob,-1) <> 100
				OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Max History Rows Per Job', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__MaxHistoryRowsPerJob),N'<null>'), N'100';
			END

			--2 = automatic, 3 = manual, 4 = disabled
			IF ISNULL(@lv__cfg__ServiceStartupSetting,-1) <> 2 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Agent Service Startup', 
					CASE WHEN @lv__cfg__ServiceStartupSetting IS NULL THEN N'<null>' 
						WHEN @lv__cfg__ServiceStartupSetting = 2 THEN N'Automatic'
						WHEN @lv__cfg__ServiceStartupSetting = 3 THEN N'Manual' 
						WHEN @lv__cfg__ServiceStartupSetting = 4 THEN N'Disabled'
						ELSE CONVERT(VARCHAR(20), @lv__cfg__ServiceStartupSetting) + N' - Unknown'
						END, 
					N'Automatic';
			END

			IF ISNULL(@lv__cfg__ShouldAgentRestartSQL,-5) <> 1 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Should Agent Restart SQL Engine?', 
						CASE WHEN @lv__cfg__ShouldAgentRestartSQL IS NULL THEN N'<null>'
							WHEN @lv__cfg__ShouldAgentRestartSQL = 1 THEN N'Yes'
							WHEN @lv__cfg__ShouldAgentRestartSQL = 0 THEN N'No'
							ELSE CONVERT(VARCHAR(20), @lv__cfg__ShouldAgentRestartSQL) + N' - Unknown'
							END , 
						N'Yes';
			END

			IF ISNULL(@lv__cfg__monitor_autostart,-5) <> 1 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Should Agent Restart itself?', 
						CASE WHEN @lv__cfg__monitor_autostart IS NULL THEN N'<null>'
							WHEN @lv__cfg__monitor_autostart = 1 THEN N'Yes'
							WHEN @lv__cfg__monitor_autostart = 0 THEN N'No'
							ELSE CONVERT(VARCHAR(20), @lv__cfg__monitor_autostart) + N' - Unknown'
							END, 
					N'Yes';
			END

			IF ISNULL(@lv__cfg__errorlogging_level,-1) <> 3 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay
					(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Error Log Level', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__errorlogging_level),N'<null>'), N'3';
			END

			--we only display the location of the error log file if the user has asked to look at all config options
			IF @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Error Log Location', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__errorlog_file),N'<null>'), N'n/a';
			END

			IF ISNULL(@lv__cfg__cpu_poller_enabled,-5) <> 32 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Define Idle CPU Threshold', 
						CASE WHEN @lv__cfg__cpu_poller_enabled IS NULL THEN N'<null>'
							WHEN @lv__cfg__cpu_poller_enabled = 32 THEN N'No'
							WHEN @lv__cfg__cpu_poller_enabled = 1 THEN N'Yes'
							ELSE CONVERT(VARCHAR(20), @lv__cfg__cpu_poller_enabled) + N' - Unknown'
							END, 
						N'No';

				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Idle CPU % Threshold', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__idle_cpu_percent),N'<null>'), N'10';

				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Idle CPU % Duration', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__idle_cpu_duration),N'<null>'), N'600';
			END


			IF ISNULL(@lv__cfg__login_timeout,-5) <> 30 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Login Timeout (sec)', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__login_timeout),N'<null>'), N'30';
			END

			IF ISNULL(@lv__cfg__job_shutdown_timeout,-5) <> 15 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Job Shutdown Timeout (sec)', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__job_shutdown_timeout),N'<null>'), N'15';
			END

			IF ISNULL(@lv__cfg__use_databasemail,-1) <> 0 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Use Database Mail?', 
						CASE WHEN @lv__cfg__use_databasemail IS NULL THEN N'<null>'
							WHEN @lv__cfg__use_databasemail = 0 THEN N'No'
							WHEN @lv__cfg__use_databasemail = 1 THEN N'Yes'
							ELSE CONVERT(VARCHAR(20), @lv__cfg__use_databasemail) + N' - Unknown'
						END , 
						N'No';

				IF ISNULL(@lv__cfg__use_databasemail,-1) <> 1 OR @DisplayConfigOptions = 2
				BEGIN
					INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
					SELECT N'Database Mail Profile', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__databasemail_profile),N'<null>'), N'<null>';
				END
			END

			IF @lv__cfg__error_recipient IS NOT NULL OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Net Send Error Recipient', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__error_recipient),N'<null>'), N'<null>';
			END

			IF @lv__cfg__local_host_server IS NOT NULL OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Local Host Server', ISNULL(CONVERT(VARCHAR(100),@lv__cfg__local_host_server),N'<null>'), N'<null>';
			END

			IF ISNULL(@lv__cfg__oem_errorlog,-1) <> 0 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'OEM Error Log', 
						CASE WHEN @lv__cfg__oem_errorlog IS NULL THEN N'<null>'
							WHEN @lv__cfg__oem_errorlog = 0 THEN N'No'
							WHEN @lv__cfg__oem_errorlog = 1 THEN N'Yes'
							ELSE CONVERT(VARCHAR(20), @lv__cfg__oem_errorlog) + N' - Unknown'
						END , 
						N'No';
			END

			IF ISNULL(@lv__cfg__alert_replace_runtime_tokens,-5) <> 0 OR @DisplayConfigOptions = 2
			BEGIN
				INSERT INTO #OptionsToDisplay(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'Alert Token Replacement', 
					CASE WHEN @lv__cfg__alert_replace_runtime_tokens IS NULL THEN N'<null>'
						WHEN @lv__cfg__alert_replace_runtime_tokens = 0 THEN N'No'
						WHEN @lv__cfg__alert_replace_runtime_tokens = 1 THEN N'Yes'
						ELSE CONVERT(VARCHAR(20), @lv__cfg__alert_replace_runtime_tokens) + N' - Unknown'
					END , 
					N'No';
			END

			--If we have no entries, mark the appropriate display variable
			IF NOT EXISTS (SELECT * FROM #OptionsToDisplay)
			BEGIN
				INSERT INTO #OptionsToDisplay 
				(OptionTag, OptionValue, OptionNormalValue)
				SELECT N'No Agent Differences', N'', N'';
			END
		END TRY
		BEGIN CATCH
			RAISERROR(N'Error occurred while comparing Agent config values with default. Agent config option comparison results will not be displayed.', 11, 1);
			SET @output__DisplayConfig = 0;
			SELECT @lv__ErrorText = ERROR_MESSAGE(), 
					@lv__ErrorSeverity	= ERROR_SEVERITY(), 
					@lv__ErrorState = ERROR_STATE();
			SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

			RAISERROR( @lv__ErrorText, 11, 1);

			GOTO afterconfig
		END CATCH

		SET @lv__afterdt = GETDATE();

		IF @Debug = 2
		BEGIN
			IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
			BEGIN
				SET @lv__ErrorText = N'   ***dbg: checking SQL Agent config values took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
				RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
			END
		END
	END		--IF @DisplayConfigOptions > 0


afterconfig: 

	/* 

														Part 3: SQL Agent Log Files
	*/
	IF @DisplayAgentLog > 0
	BEGIN
		--Read the SQL Agent logs. 

		/* If xp_readerrorlog is passed a log file # that doesn't exist, we get this error
			Msg 22004, Level 16, State 1, Line 0
			xp_readerrorlog() returned error 2, 'The system cannot find the file specified.'

			I tried writing a loop with a TRY/CATCH block to make sure I get all log files, but 
			I got "a severe error has occurred on this command" when trying to insert data into a 
			temp table.
		*/ 
		--Note that this statement still works even when SQL Agent is off
		--Also note that xp_readerrorlog can throw errors that are not catch-able, apparently when it is used to insert into a temp table.
		-- So the TRY/CATCH here is not guaranteed to be effective
		BEGIN TRY
			INSERT INTO #SQLAgentLog (LogDate, ErrorLevel, aText)
			EXEC xp_readerrorlog 0,	--log file # (0 is current)
				2,	--SQL Agent log
				null,	--search string 1
				null,	--search string 2
				null,	--search start time
				null,	--search end time
				'Desc'	--order results 
				;

			SET @lv__log__log1processing = 1
		END TRY
		BEGIN CATCH
			SET @output__DisplayAgentLog = 0;
			RAISERROR(N'Error occurred when obtaining the current SQL Agent error log. Some loss in functionality may occur.', 11, 1);
			SELECT @lv__ErrorText = ERROR_MESSAGE(), 
					@lv__ErrorSeverity	= ERROR_SEVERITY(), 
					@lv__ErrorState = ERROR_STATE();
			SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

			RAISERROR( @lv__ErrorText, 11, 1);
		END CATCH

		IF @lv__log__log1processing = 1		--log has been read, but not processed
		BEGIN
			SET @lv__beforedt = GETDATE();

			--misc handling for current log file
			--There are some SQL Agent log messages that are very common, and are not what we'd typically be looking for. 
			-- make sure these are omitted.
			BEGIN TRY
				DELETE 
				FROM #SQLAgentLog 
				WHERE (
					atext LIKE '%Job completion for % is being logged to sysjobhistory%'
					OR atext LIKE '%Job % has been requested to run by Schedule%'
					OR atext LIKE '%Saving % for all updated job schedules...'
					OR atext LIKE '% job schedule(s) saved%'
					OR (@DisplayAgentLog = 1 AND atext LIKE '%The Messenger service has not been started - NetSend notifications will not be sent%')
				);

				SELECT @lv__log__maxTabID = MAX(idcol) FROM #SQLAgentLog;
 
				UPDATE targ 
				SET FileNumber = 0,
					isLastRecord = CASE WHEN idcol <> @lv__log__maxTabID THEN 0 ELSE 1 END
				FROM #SQLAgentLog targ 
				WHERE FileNumber IS NULL 
				;

				SET @lv__log__log1processing = 2
			END TRY
			BEGIN CATCH
				RAISERROR(N'Error occurred while post-processing the current SQL Agent log file. The SQL Agent log will not be displayed.', 11, 1);
				SET @output__DisplayAgentLog = 0;
				SET @lv__log__log1processing = -2;
				SET @lv__log__log2processing = -3;
				SET @lv__log__log3processing = -3;
				SELECT @lv__ErrorText = ERROR_MESSAGE(), 
						@lv__ErrorSeverity	= ERROR_SEVERITY(), 
						@lv__ErrorState = ERROR_STATE();
				SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

				RAISERROR( @lv__ErrorText, 11, 1);

				GOTO afteragentlog
			END CATCH

			SET @lv__afterdt = GETDATE();

			IF @Debug = 2
			BEGIN
				IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
				BEGIN
					SET @lv__ErrorText = N'   ***dbg: post-processing on current SQL Agent log file took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
					RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
				END
			END
		END			--IF @lv__log__log1processing = 1		--log has been read, but not processed

		--only get additional files if @DisplayAgentLog = 3
		IF @DisplayAgentLog = 3
		BEGIN
			SET @lv__beforedt = GETDATE();

			--Get the most recent non-active log file and process
			BEGIN TRY
				INSERT INTO #SQLAgentLog (LogDate, ErrorLevel, aText)
					EXEC xp_readerrorlog 1,	--log file # (0 is current)
						2,	--SQL Agent log
						null,	--search string 1
						null,	--search string 2
						null,	--search start time
						null,	--search end time
						'Desc'	--order results 
						;
				SET @lv__log__log2processing = 1;
			END TRY
			BEGIN CATCH
				RAISERROR(N'Error occurred while obtaining the most-recent non-active SQL Agent log file. The SQL Agent log will not be displayed.', 11, 1);
				SET @output__DisplayAgentLog = 0;
				SET @lv__log__log2processing = -1;
				SELECT @lv__ErrorText = ERROR_MESSAGE(), 
						@lv__ErrorSeverity	= ERROR_SEVERITY(), 
						@lv__ErrorState = ERROR_STATE();
				SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

				RAISERROR( @lv__ErrorText, 11, 1);

				GOTO afteragentlog
			END CATCH

			SET @lv__afterdt = GETDATE();

			IF @Debug = 2
			BEGIN
				IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
				BEGIN
					SET @lv__ErrorText = N'   ***dbg: obtaining most-recent non-active SQL Agent log file took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
					RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
				END
			END

			IF @lv__log__log2processing = 1
			BEGIN 
				SET @lv__beforedt = GETDATE();

				--There are some SQL Agent log messages that are very common, and are not what we'd typically be looking for. 
				-- make sure these are omitted
				BEGIN TRY
					DELETE 
					FROM #SQLAgentLog 
					WHERE (
						atext LIKE '%Job completion for % is being logged to sysjobhistory%'
						OR atext LIKE '%Job % has been requested to run by Schedule%'
						OR atext LIKE '%Saving % for all updated job schedules...'
						OR atext LIKE '% job schedule(s) saved%'
						OR (@DisplayAgentLog = 1 AND atext LIKE '%The Messenger service has not been started - NetSend notifications will not be sent%')
					);

					SELECT @lv__log__maxTabID = MAX(idcol) FROM #SQLAgentLog;

					UPDATE targ 
					SET FileNumber = 1,
						isLastRecord = CASE WHEN idcol <> @lv__log__maxTabID THEN 0 ELSE 1 END
					FROM #SQLAgentLog targ 
					WHERE FileNumber IS NULL 
					;

					SET @lv__log__log2processing = 2;
				END TRY
				BEGIN CATCH
					RAISERROR(N'Error occurred while post-processing the most-recent non-active SQL Agent log file. The SQL Agent log will not be displayed.', 11, 1);
					SET @output__DisplayAgentLog = 0;
					SET @lv__log__log2processing = -2;
					SELECT @lv__ErrorText = ERROR_MESSAGE(), 
							@lv__ErrorSeverity	= ERROR_SEVERITY(), 
							@lv__ErrorState = ERROR_STATE();
					SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

					RAISERROR( @lv__ErrorText, 11, 1);

					GOTO afteragentlog
				END CATCH

				SET @lv__afterdt = GETDATE();

				IF @Debug = 2
				BEGIN
					IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
					BEGIN
						SET @lv__ErrorText = N'   ***dbg: post-processing on most-recent non-active SQL Agent log file took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
						RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
					END
				END
			END 

			SET @lv__beforedt = GETDATE();

			--Get second-most-recent non-active log file and process
			BEGIN TRY
				INSERT INTO #SQLAgentLog (LogDate, ErrorLevel, aText)
					EXEC xp_readerrorlog 2,	--log file # (0 is current)
						2,	--SQL Agent log
						null,	--search string 1
						null,	--search string 2
						null,	--search start time
						null,	--search end time
						'Desc'		--order results 
						;
				SET @lv__log__log3processing = 1;
			END TRY
			BEGIN CATCH
				RAISERROR(N'Error occurred while obtaining the second-most-recent non-active SQL Agent log file. The SQL Agent log will not be displayed.', 11, 1);
				SET @output__DisplayAgentLog = 0;
				SET @lv__log__log3processing = -1;
				SELECT @lv__ErrorText = ERROR_MESSAGE(), 
						@lv__ErrorSeverity	= ERROR_SEVERITY(), 
						@lv__ErrorState = ERROR_STATE();
				SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

				RAISERROR( @lv__ErrorText, 11, 1);

				GOTO afteragentlog
			END CATCH

			SET @lv__afterdt = GETDATE();

			IF @Debug = 2
			BEGIN
				IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
				BEGIN
					SET @lv__ErrorText = N'   ***dbg: obtaining second-most-recent non-active SQL Agent log file took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
					RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
				END
			END
			
			IF @lv__log__log3processing = 1
			BEGIN
				SET @lv__beforedt = GETDATE();

				--There are some SQL Agent log messages that are very common, and are not what we'd typically be looking for. 
				-- make sure these are omitted
				BEGIN TRY
					DELETE 
					FROM #SQLAgentLog 
					WHERE (
						atext LIKE '%Job completion for % is being logged to sysjobhistory%'
						OR atext LIKE '%is being queued for the PowerShell subsystem%'
						OR atext LIKE '%Job % has been requested to run by Schedule%'
						OR atext LIKE '%Saving % for all updated job schedules...'
						OR atext LIKE '% job schedule(s) saved%'
						OR (@DisplayAgentLog = 1 AND atext LIKE '%The Messenger service has not been started - NetSend notifications will not be sent%')
					);

					SELECT @lv__log__maxTabID = MAX(idcol) FROM #SQLAgentLog;

					UPDATE targ 
					SET FileNumber = 2,
						isLastRecord = CASE WHEN idcol <> @lv__log__maxTabID THEN 0 ELSE 1 END
					FROM #SQLAgentLog targ 
					WHERE FileNumber IS NULL 
					;
					SET @lv__log__log3processing = 2;
				END TRY
				BEGIN CATCH
					RAISERROR(N'Error occurred while post-processing the second-most-recent non-active SQL Agent log file. The SQL Agent log will not be displayed.', 11, 1);
					SET @output__DisplayAgentLog = 0;
					SET @lv__log__log3processing = -2;
					SELECT @lv__ErrorText = ERROR_MESSAGE(), 
							@lv__ErrorSeverity	= ERROR_SEVERITY(), 
							@lv__ErrorState = ERROR_STATE();
					SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

					RAISERROR( @lv__ErrorText, 11, 1);

					GOTO afteragentlog
				END CATCH

				SET @lv__afterdt = GETDATE();

				IF @Debug = 2
				BEGIN
					IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
					BEGIN
						SET @lv__ErrorText = N'   ***dbg: post-processing on second-most-recent non-active SQL Agent log file took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
						RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
					END
				END
			END 
		END		--IF @DisplayAgentLog = 3

		SET @lv__beforedt = GETDATE();
		--Construct output string
		SET @lv__log__AgentLogString = '';

		BEGIN TRY
			IF @DisplayAgentLog >= 2 OR EXISTS (SELECT * FROM #SQLAgentLog l WHERE l.ErrorLevel = 1)
			BEGIN
				SET @lv__log__AgentLogString = N'';

				SELECT 
					@lv__log__AgentLogString = @lv__log__AgentLogString + 
						REPLACE(CONVERT(NVARCHAR(40),l.LogDate,102),'.','-') + ' ' +
							CONVERT(NVARCHAR(40),l.LogDate,108) + '.' + 
							CONVERT(NVARCHAR(40),DATEPART(millisecond, l.LogDate)) +
						'   ' + 
						CONVERT(NVARCHAR(40),l.ErrorLevel) + 
						'              ' + 
						REPLACE(REPLACE(l.aText,NCHAR(10),N' '),NCHAR(13), N' ') + NCHAR(10) + 
						CASE WHEN isLastRecord = 1 THEN NCHAR(10) ELSE N'' END
				FROM #SQLAgentLog l 
				WHERE l.FileNumber = 0
				--This seems like it could cause confusion: 
				-- WHERE l.LogDate <= @lv__mtx__OverallWindowEndTime		--helps implement a "historical" look at the log file for @PointInTime values other than NULL
				ORDER BY idcol ASC; 

				SET @lv__log__AgentLogString = N'<?AgentLog1 -- ' + NCHAR(10) + 
					N'LogDate                 ErrorLevel     Text' + NCHAR(10) +
					N'-------------------------------------------------------------------------------------' + NCHAR(10) + 
					@lv__log__AgentLogString + NCHAR(10) + N' -- ?>';

				INSERT INTO #PreXML 
				(OrderingNumber, ReturnType, LongString)
				SELECT 1, N'agentlog', @lv__log__AgentLogString;

				IF @DisplayAgentLog = 3
				BEGIN
					SET @lv__log__AgentLogString = N'';

					SELECT 
						@lv__log__AgentLogString = @lv__log__AgentLogString + 
							REPLACE(CONVERT(NVARCHAR(40),l.LogDate,102),'.','-') + ' ' +
								CONVERT(NVARCHAR(40),l.LogDate,108) + '.' + 
								CONVERT(NVARCHAR(40),DATEPART(millisecond, l.LogDate)) +
							'   ' + 
							CONVERT(NVARCHAR(40),l.ErrorLevel) + 
							'              ' + 
							REPLACE(REPLACE(l.aText,NCHAR(10),N' '),NCHAR(13), N' ') + NCHAR(10) + 
							CASE WHEN isLastRecord = 1 THEN NCHAR(10) ELSE N'' END
					FROM #SQLAgentLog l 
					WHERE l.FileNumber = 1
					--This seems like it could cause confusion: 
					-- WHERE l.LogDate <= @lv__mtx__OverallWindowEndTime		--helps implement a "historical" look at the log file for @PointInTime values other than NULL
					ORDER BY idcol ASC; 

					SET @lv__log__AgentLogString = N'<?AgentLog2 -- ' + NCHAR(10) + 
						N'LogDate                 ErrorLevel     Text' + NCHAR(10) +
						N'-------------------------------------------------------------------------------------' + NCHAR(10) + 
						@lv__log__AgentLogString + NCHAR(10) + N' -- ?>';

					INSERT INTO #PreXML 
					(OrderingNumber, ReturnType, LongString)
					SELECT 2, N'agentlog', @lv__log__AgentLogString;

					SET @lv__log__AgentLogString = N'';

					SELECT 
						@lv__log__AgentLogString = @lv__log__AgentLogString + 
							REPLACE(CONVERT(NVARCHAR(40),l.LogDate,102),'.','-') + ' ' +
								CONVERT(NVARCHAR(40),l.LogDate,108) + '.' + 
								CONVERT(NVARCHAR(40),DATEPART(millisecond, l.LogDate)) +
							'   ' + 
							CONVERT(NVARCHAR(40),l.ErrorLevel) + 
							'              ' + 
							REPLACE(REPLACE(l.aText,NCHAR(10),N' '),NCHAR(13), N' ') + NCHAR(10) + 
							CASE WHEN isLastRecord = 1 THEN NCHAR(10) ELSE N'' END
					FROM #SQLAgentLog l 
					WHERE l.FileNumber = 2
					--This seems like it could cause confusion: 
					-- WHERE l.LogDate <= @lv__mtx__OverallWindowEndTime		--helps implement a "historical" look at the log file for @PointInTime values other than NULL
					ORDER BY idcol ASC; 

					SET @lv__log__AgentLogString = N'<?AgentLog3 -- ' + NCHAR(10) + 
						N'LogDate                 ErrorLevel     Text' + NCHAR(10) +
						N'-------------------------------------------------------------------------------------' + NCHAR(10) + 
						@lv__log__AgentLogString + NCHAR(10) + N' -- ?>';

					INSERT INTO #PreXML 
					(OrderingNumber, ReturnType, LongString)
					SELECT 3, N'agentlog', @lv__log__AgentLogString;
				END
			END 
			ELSE 
			BEGIN
				SET @output__DisplayAgentLog = 0;
			END
		END TRY
		BEGIN CATCH
			RAISERROR(N'Error occurred while constructing the SQL Agent log output string. The SQL Agent log will not be displayed.', 11, 1);
			SET @output__DisplayAgentLog = 0;
			SELECT @lv__ErrorText = ERROR_MESSAGE(), 
					@lv__ErrorSeverity	= ERROR_SEVERITY(), 
					@lv__ErrorState = ERROR_STATE();
			SET @lv__ErrorText = @lv__ErrorText + ' (Severity: ' + CONVERT(VARCHAR(20),@lv__ErrorSeverity) + ') (State: ' + CONVERT(VARCHAR(20),@lv__ErrorState) + ')'

			RAISERROR( @lv__ErrorText, 11, 1);

			GOTO afteragentlog
		END CATCH

		SET @lv__afterdt = GETDATE();

		IF @Debug = 2
		BEGIN
			IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
			BEGIN
				SET @lv__ErrorText = N'   ***dbg: constructing SQL Agent log output string took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
				RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
			END
		END
	END --IF @DisplayAgentLog > 0

afteragentlog: 


	/*
														Part 4: Assemble queries
	*/
	IF @Queries = N'Y'
	BEGIN
		--most common queries relate to jobs, jobsteps, and schedules
		SET @lv__OutputVar = N'
--********** JOBS **********
SELECT 
	[JobName] = j.name, 
	[Enabled] = CASE WHEN j.enabled = 1 THEN N''Yes'' ELSE N''No'' END, 
	[JobDescription] = j.description, 
	[JobOwner] = suser_sname(j.owner_sid),
	[JobCategory] = ct.name,
	[JobCreated] = j.date_created, 
	[CrDaysAgo] = DATEDIFF(day, j.date_created, getdate()),
	[JobLastModified] = j.date_modified,
	[ModDaysAgo] = DATEDIFF(day, j.date_modified, getdate()),
	[WhenDelete] = (CASE [delete_level]
        WHEN 0 THEN N''Never''
        WHEN 1 THEN N''On Success''
        WHEN 2 THEN N''On Failure''
        WHEN 3 THEN N''On Completion''
		ELSE N''?''
		END),
	[NotifyTypes] = (
		CASE WHEN j.notify_level_eventlog > 0 THEN N''EventLog,'' ELSE N'''' END +
		CASE WHEN j.notify_level_email > 0 THEN N''Email,'' ELSE N'''' END +
		CASE WHEN j.notify_level_netsend > 0 THEN N''NetSend,'' ELSE N'''' END +
		CASE WHEN j.notify_level_page > 0 THEN N''Pager,'' ELSE N'''' END
	)
FROM msdb.dbo.sysjobs j
	INNER JOIN msdb.dbo.syscategories ct
		ON j.category_id = ct.category_id;

--********** STEPS **********
SELECT 
	[JobName] = j.name,
	[StepName] = js.step_name,
	[StepID] = js.step_id, 
	[SubSys] = js.subsystem,
	[DBName] = js.database_name,
	[AsUser] = js.database_user_name,
	[ProxyId] = js.proxy_id,
	[OnSuccess] = CASE js.on_success_action
		WHEN 1 THEN N''Quit W/success''
		WHEN 2 THEN N''Quit W/fail''
		WHEN 3 THEN N''Next Step''
		WHEN 4 THEN N''Go to step ID: '' + CONVERT(varchar(20),js.on_success_step_id)
		ELSE N''?''
		END,
	[OnFail] = CASE js.on_fail_action
		WHEN 1 THEN N''Quit W/success''
		WHEN 2 THEN N''Quit W/fail''
		WHEN 3 THEN N''Next Step''
		WHEN 4 THEN N''Go to step ID: '' + CONVERT(varchar(20),js.on_fail_step_id)
		ELSE N''?''
		END,
	[#Retries] = js.retry_attempts,
	[RetryInterval] = js.retry_interval,
	[Cmd] = js.command,
	[Flags] = js.flags,
	[Server] = js.[server], 
	[OSRunPriority] = js.os_run_priority,
	[OutputFile] = js.output_file_name,
	[AdditlParms] = js.additional_parameters,
	[CmdExec_SuccessCode] = js.cmdexec_success_code,
	[ProxyName] = p.name, 
	[ProxyEnabled] = p.enabled, 
	[ProxyDescription] = p.description, 
	[CredentialName] = c.name, 
	[CredIdentity] = c.credential_identity, 
	[CredCrDate] = c.create_date,
	[CredModDate] = c.modify_date
	--TODO: add an XML column containing rows from msdb.dbo.sysjobstepslogs
FROM msdb.dbo.sysjobsteps js
	INNER JOIN msdb.dbo.sysjobs j
		ON j.job_id = js.job_id
	LEFT OUTER JOIN msdb.dbo.sysproxies p
		ON js.proxy_id = p.proxy_id
	LEFT OUTER JOIN sys.credentials c
		on p.credential_id = c.credential_id
ORDER BY JobName, StepID;
		';

		SET @lv__OutputVar = @lv__OutputVar + N'
--********** SCHEDULES **********
SELECT 
	ss0.JobName, 
	ss0.#SchedulesForThisJob,
	[SchedID] = ss1.ScheduleID,
	ss1.ScheduleName,
	ss1.#JobsTiedToThisSchedule,
	[SchedEnabled] = CASE WHEN sch1.enabled = 1 THEN N''Y'' ELSE N''N'' END,
	sch1.date_created as ScheduleCreated,
	sch1.date_modified as ScheduleModified,
	Scheduling = (
			CASE WHEN sch1.freq_type = 1 THEN N''OneTime''
				WHEN sch1.freq_type = 4 THEN N''Every ''+CONVERT(varchar(20),sch1.freq_interval) + N'' days''
				WHEN sch1.freq_type = 8 THEN N''Days of Week: '' + 
					(CASE WHEN sch1.freq_interval & 1 > 0 THEN N''Sunday,'' ELSE N'''' END +
					CASE WHEN sch1.freq_interval & 2 > 0 THEN N''Monday,'' ELSE N'''' END +
					CASE WHEN sch1.freq_interval & 4 > 0 THEN N''Tuesday,'' ELSE N'''' END +
					CASE WHEN sch1.freq_interval & 8 > 0 THEN N''Wednesday,'' ELSE N'''' END +
					CASE WHEN sch1.freq_interval & 16 > 0 THEN N''Thursday,'' ELSE N'''' END +
					CASE WHEN sch1.freq_interval & 32 > 0 THEN N''Friday,'' ELSE N'''' END +
					CASE WHEN sch1.freq_interval & 64 > 0 THEN N''Saturday,'' ELSE N'''' END
					)
				WHEN sch1.freq_type = 16 THEN N''On '' + CONVERT(varchar(20),sch1.freq_interval) + N'' day of month''
				WHEN sch1.freq_type = 32 THEN N''Monthly, every '' + (
					CASE WHEN sch1.freq_interval = 1 THEN N''Sunday''
						WHEN sch1.freq_interval = 2 THEN N''Monday''
						WHEN sch1.freq_interval = 3 THEN N''Tuesday''
						WHEN sch1.freq_interval = 4 THEN N''Wednesday''
						WHEN sch1.freq_interval = 5 THEN N''Thursday''
						WHEN sch1.freq_interval = 6 THEN N''Friday''
						WHEN sch1.freq_interval = 7 THEN N''Saturday''
						WHEN sch1.freq_interval = 8 THEN N''day''
						WHEN sch1.freq_interval = 9 THEN N''weekday''
						WHEN sch1.freq_interval = 10 THEN N''weekend day''
					ELSE N''? day''
					END
					)
				WHEN sch1.freq_type = 64 THEN N''SQL Agent Startup''
				WHEN sch1.freq_type = 128 THEN N''Machine idle''
			END
		),

	[SchedStartDate] = ISNULL(CONVERT(NVARCHAR(20),active_start_date),N''Today''),		--int		Date on which execution of a job can begin. The date is formatted as YYYYMMDD. NULL indicates today''s date.
	[SchedEndDate] = CONVERT(NVARCHAR(20),active_end_date),		--int		Date on which execution of a job can stop. The date is formatted YYYYMMDD.
	[ActiveStartTime] = active_start_time,
	[ActiveEndTime] = active_end_time
FROM (
	SELECT j.job_id, j.name as JobName,
		[#SchedulesForThisJob] = SUM(CASE WHEN js.schedule_id IS NULL THEN 0 ELSE 1 END)
	FROM msdb.dbo.sysjobs j
		LEFT OUTER JOIN msdb.dbo.sysjobschedules js
			ON js.job_id = j.job_id
	GROUP BY j.job_id, j.name 
	) ss0
	LEFT OUTER JOIN msdb.dbo.sysjobschedules js
		ON ss0.job_id = js.job_id
	RIGHT OUTER JOIN (
		SELECT sch.schedule_id as ScheduleID, 
			sch.name as ScheduleName,
			[#JobsTiedToThisSchedule] = SUM(CASE WHEN js.schedule_id IS NULL THEN 0 ELSE 1 END)
		FROM msdb.dbo.sysschedules sch
			LEFT OUTER JOIN msdb.dbo.sysjobschedules js
				ON sch.schedule_id = js.schedule_id
		GROUP BY sch.schedule_id, sch.name, sch.enabled, sch.date_created
		) ss1
		ON js.schedule_id = ss1.ScheduleID
	LEFT OUTER JOIN msdb.dbo.sysschedules sch1
		ON ss1.ScheduleID = sch1.schedule_id
ORDER BY ScheduleID, JobName;
--ORDER BY JobName, ScheduleID;

		';

		SET @lv__OutputVar = N'<?Qry_JobStepSched -- ' + NCHAR(10) + 
			@lv__OutputVar + NCHAR(10) + N' -- ?>';

		INSERT INTO #PreXML
		(OrderingNumber, ReturnType, LongString)
		SELECT 1, N'queries', @lv__OutputVar;

		SET @lv__OutputVar = N'
--********** AGENT STARTS **********
SELECT session_id, agent_start_date 
FROM msdb.dbo.syssessions 
ORDER BY agent_start_date DESC;

--********** ALERTS SENT **********
SELECT n.alert_id, n.notification_method,
	n.operator_id, o.name AS operator_name, 
	o.email_address AS operator_email_address,
	a.*
FROM msdb.dbo.sysnotifications n
	LEFT OUTER JOIN msdb.dbo.sysalerts a
		ON n.alert_id = a.id
	LEFT OUTER JOIN msdb.dbo.sysoperators o
		ON n.operator_id = o.id;

--********** JOBS w PROXIES **********
SELECT j.name as JobName, js.step_id, js.step_name, js.subsystem, js.database_name, js.database_user_name, 
	js.last_run_outcome, js.last_run_duration, js.last_run_retries, js.last_run_date, js.last_run_time, 
	p.proxy_id, p.name as ProxyName, p.enabled as Proxy_Enabled, p.description as Proxy_Description, 
	c.name as CredentialName, c.credential_identity, c.create_date as Credential_create_date,
	c.modify_date as Credential_modify_date
FROM msdb.dbo.sysjobs j
	INNER JOIN msdb.dbo.sysjobsteps js
		ON j.job_id = js.job_id
	INNER JOIN msdb.dbo.sysproxies p
		ON js.proxy_id = p.proxy_id
	INNER JOIN sys.credentials c
		on p.credential_id = c.credential_id
ORDER BY j.name, js.step_id;

--********** JOB SERVERS **********
SELECT 
	s.name as ServerName, 
	j.name as JobName, 
	js.last_run_outcome,
	js.last_outcome_message, 
	js.last_run_date, 
	js.last_run_time, 
	js.last_run_duration
FROM msdb.dbo.sysjobservers js
	INNER JOIN msdb.dbo.sysjobs j
		ON js.job_id = j.job_id 
	LEFT OUTER JOIN sys.servers s
		ON js.server_id = s.server_id
ORDER BY s.name, js.last_run_outcome desc, j.name;
		';

		SET @lv__OutputVar = N'<?Qry_Operational -- ' + NCHAR(10) + 
			@lv__OutputVar + NCHAR(10) + N' -- ?>';

		INSERT INTO #PreXML
		(OrderingNumber, ReturnType, LongString)
		SELECT 2, N'queries', @lv__OutputVar;

		SET @lv__OutputVar = N'
--********** SSIS Pkgs **********
SELECT pkg.name, pkg.id, pkg.description, pkg.createdate, 
		p.name as PkgCreator, pkg.packageformat,
	PkgType = (CASE pkg.packagetype 
				WHEN 6 THEN N''6 - Maint Plan''
				WHEN 5 THEN N''5 - SSIS Designer''
				WHEN 3 THEN N''3 - Replication''
				WHEN 1 THEN N''1 - Import/Export Wizard''
				ELSE CONVERT(varchar(20),pkg.packagetype) + N'' - Unknown''
				END
	),
	pkg.vercomments,
	pkg.isencrypted
FROM msdb.dbo.sysssispackages pkg
	LEFT OUTER JOIN sys.server_principals p
		ON pkg.ownersid = p.sid;

--********** SSIS Pkg Hist **********
SELECT pkg.name, lstart.operator, lstart.executionid, 
	lstart.id as StartLogID, xapp1.StopLogID,
	lstart.starttime as PackageStartTime, xapp1.endtime as PackageEndTime, 
	datediff(second, lstart.starttime, xapp1.endtime) as dur_seconds,
	lstart.datacode as StartDatacode, xapp1.Datacode as EndDatacode
FROM msdb.dbo.sysssispackages pkg
	LEFT OUTER JOIN msdb.dbo.sysssislog lstart	--replace "msdb" here with your DB name
		ON lstart.sourceid = pkg.id
	OUTER APPLY (
		SELECT TOP 1 lstop.ID as StopLogID, lstop.endtime, lstop.datacode
		FROM msdb.dbo.sysssislog lstop	--replace "msdb" here with your DB name
		WHERE lstop.executionid = lstart.executionid
		AND lstop.event = N''PackageEnd''
	) xapp1
WHERE 1=1
AND lstart.event = N''PackageStart''
ORDER BY lstart.id asc;

--********** MaintPlans and SubMaintPlans **********
SELECT 
	j.name as JobName,
	j.enabled as JobEnabled,
	suser_sname(j.owner_sid) as JobOwner,
	p.name as MaintPlanName,
	p.description as MPDescription,
	p.create_date as MPCreateDate, 
	p.owner as MPOwner,
	p.version_comments as MPVersionComments,
	p.has_targets as MPHasTargets,
	sp.subplan_name as SubplanName, 
	sp.subplan_description as SubplanDescription
FROM msdb.dbo.sysmaintplan_plans p
	LEFT OUTER JOIN msdb.dbo.sysmaintplan_subplans sp
		ON sp.plan_id = p.id
	LEFT OUTER JOIN msdb.dbo.sysjobs j
		ON sp.job_id = j.job_id
	LEFT OUTER JOIN sys.server_principals pr
		ON j.owner_sid = pr.sid
ORDER BY j.name, p.name, sp.subplan_name 
';

		SET @lv__OutputVar = N'<?Qry_SSIS -- ' + NCHAR(10) + 
			@lv__OutputVar + NCHAR(10) + N' -- ?>';

		INSERT INTO #PreXML
		(OrderingNumber, ReturnType, LongString)
		SELECT 3, N'queries', @lv__OutputVar;

	END		--IF @Queries = N'Y'


	/*

														Part 5: Display the data!
	*/

	--If returning the historical matrix to the console, print it and set the logic so it isn't returned by the SELECT
	IF @outputType__Matrix = N'CONSOLE' AND @output__DisplayMatrix = 1
	BEGIN
		SET @lv__beforedt = GETDATE();
		SET @lv__OutputLength = LEN(@lv__OutputVar);
		SET @lv__CurrentPrintLocation = 1;

		WHILE @lv__CurrentPrintLocation <= @lv__OutputLength
		BEGIN
			PRINT SUBSTRING(@lv__OutputVar, @lv__CurrentPrintLocation, 8000);
			SET @lv__CurrentPrintLocation = @lv__CurrentPrintLocation + 8000;
		END

		SET @output__DisplayMatrix = 0;	--just printed it, don't return it as XML

		SET @lv__afterdt = GETDATE();

		IF @Debug = 2
		BEGIN
			IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
			BEGIN
				SET @lv__ErrorText = N'   ***dbg: printing job history matrix to console took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
				RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
			END
		END
	END

	SET @lv__beforedt = GETDATE();

	--matrix, agentlog
	IF @Queries = N'Y'
	BEGIN
		SELECT 
			[Job History Matrix] = CONVERT(XML,HistoryMatrix), 
			[SQL Agent Option] = OptionTag, 
			[Current Value] = OptionNormalValue,
			[Default/Expected Value] = OptionValue,
			[SQL Agent Logs] = CONVERT(XML,AgentLog),
			[Queries] = CONVERT(XML,Queries)
		FROM (
			SELECT 
				OrderingNumber = COALESCE(m.OrderingNumber, l.OrderingNumber, q.OrderingNumber, o.idCol),
				HistoryMatrix = ISNULL(m.HistoryMatrix,N''),
				OptionTag = ISNULL(o.OptionTag,N''),
				OptionNormalValue = ISNULL(o.OptionNormalValue,N''),
				OptionValue = ISNULL(o.OptionValue,N''),
				AgentLog = ISNULL(l.AgentLog,N''),
				Queries = ISNULL(q.QueryText,N'')
			FROM 
				(
				SELECT m.OrderingNumber, m.LongString as HistoryMatrix
				FROM #PreXML m 
				WHERE m.ReturnType = N'matrix'
				) m
				FULL OUTER JOIN (
					SELECT l.OrderingNumber, l.LongString as AgentLog
					FROM #PreXML l
					WHERE l.ReturnType = N'agentlog'
					) l
					ON m.OrderingNumber = l.OrderingNumber
				FULL OUTER JOIN (
					SELECT o.idcol, o.OptionTag, 
						o.OptionNormalValue, o.OptionValue
					FROM #OptionsToDisplay o
					) o
						ON l.OrderingNumber = o.idcol
				FULL OUTER JOIN (
					SELECT q.OrderingNumber, q.LongString as QueryText
					FROM #PreXML q
					WHERE q.ReturnType = N'queries'
					) q
						ON l.OrderingNumber = q.OrderingNumber
			) ss
		ORDER BY OrderingNumber
		;
	END
	ELSE
	BEGIN
		SELECT 
			[Job History Matrix] = CONVERT(XML,HistoryMatrix), 
			[SQL Agent Option] = OptionTag, 
			[Current Value] = OptionNormalValue,
			[Default/Expected Value] = OptionValue,
			[SQL Agent Logs] = CONVERT(XML,AgentLog)
		FROM (
			SELECT 
				OrderingNumber = COALESCE(m.OrderingNumber, l.OrderingNumber, o.idCol),
				HistoryMatrix = ISNULL(m.HistoryMatrix,N''),
				OptionTag = ISNULL(o.OptionTag,N''),
				OptionNormalValue = ISNULL(o.OptionNormalValue,N''),
				OptionValue = ISNULL(o.OptionValue,N''),
				AgentLog = ISNULL(l.AgentLog,N'')
			FROM 
				(
				SELECT m.OrderingNumber, m.LongString as HistoryMatrix
				FROM #PreXML m 
				WHERE m.ReturnType = N'matrix'
				) m
				FULL OUTER JOIN (
					SELECT l.OrderingNumber, l.LongString as AgentLog
					FROM #PreXML l
					WHERE l.ReturnType = N'agentlog'
					) l
					ON m.OrderingNumber = l.OrderingNumber
				FULL OUTER JOIN (
					SELECT o.idcol, o.OptionTag, 
						o.OptionNormalValue, o.OptionValue
					FROM #OptionsToDisplay o
					) o
						ON l.OrderingNumber = o.idcol
			) ss
		ORDER BY OrderingNumber
		;
	END

	SET @lv__afterdt = GETDATE();

	IF @Debug = 2
	BEGIN
		IF DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt) > @lv__slownessthreshold
		BEGIN
			SET @lv__ErrorText = N'   ***dbg: returning final results took ' + CONVERT(NVARCHAR(40),DATEDIFF(MILLISECOND, @lv__beforedt, @lv__afterdt)) + N' milliseconds';
			RAISERROR(@lv__ErrorText, 10, 1) WITH NOWAIT;
		END
	END

	--we always print out at least the EXEC command
	GOTO helpbasic

	/*
														Part 6: Print help
	*/
helpbasic:
	--If the user DID enter @PointInTime info, then we use those values to replace the <datetime> tag
	-- in the @helpexec string.
	IF @PointInTime IS NOT NULL
	BEGIN
		SET @helpexec = REPLACE(@helpexec,'<past datetime>', REPLACE(CONVERT(NVARCHAR(20), @PointInTime, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @PointInTime, 108) + '.' + 
															RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @PointInTime)),3)
							);
	END 

	SET @helpstr = @helpexec;
	RAISERROR(@helpstr,10,1) WITH NOWAIT;

	IF @Help=N'N'
	BEGIN
		RETURN 0;
	END

	IF @Help <> N'N'
	BEGIN
		IF @Help LIKE N'PA%'
		BEGIN
			SET @Help = N'PARAMS';
		END
		ELSE IF @Help LIKE N'CO%'
		BEGIN
			SET @Help = N'COLUMNS';
		END
		ELSE IF @Help LIKE N'MA%'
		BEGIN
			SET @Help = N'MATRIX';
		END
		ELSE
		BEGIN
			--user may have typed gibberish... which is ok, give him/her all the help
			SET @Help = N'ALL';
		END
	END


	IF @Help = N'PARAMS'
	BEGIN
		GOTO helpparams
	END
	ELSE IF @Help = N'COLUMNS'
	BEGIN
		GOTO helpcolumns
	END
	ELSE IF @Help = N'MATRIX'
	BEGIN
		GOTO helpmatrix
	END

helpparams:

	SET @helpstr = N'
Parameters
---------------------------------------------------------------------------------------------------------------------------------------------------------------
@PointInTime		Valid Values: any datetime value <= the current time (NULL, the default is current time), and >= 2010-01-01

					IF NULL, the job history matrix is constructed with the current time as the endpoint of the matrix, otherwise the datetime 
					in @PointInTime is the endpoint of the matrix. Note that the actual endpoint will usually be a bit more recent than @PointInTime, 
					aligned with the width of an individual cell in the matrix. For example, if @PointInTime is specified as "2016-10-12 08:00", and 
					the cell width is 3 minutes (e.g. for @HoursBack=5), then the end time represented by the right-hand side of the matrix will 
					be 2016-10-12 08:03.

@HoursBack			Valid Values: Any integer from 1 to 48, defaults to 12

					The number of hours that the matrix will represent. For example, if @PointInTime is "2016-10-12 08:00" and @HoursBack is
					set to 10, the start of the matrix will be "2016-10-11 22:00". Because it is necessary for the individual cells in the 
					matrix to be a certain number of minutes wide (so that the tick marks at the top will align neatly), the actual cell width 
					of the matrix will vary based on the value selected for @HoursBack.';

	RAISERROR(@helpstr,10,1);
	SET @helpstr = N'
@ToConsole			Valid Values: N (default), or Y

					If "N", the default, the job history matrix is printed to a click-able XML variable. If "Y", the matrix is printed to the
					SSMS "messages" tab. Because the font is typically smaller on the SSMS messages tab, @ToConsole defaults to a larger
					cell width when it is "N" than "Y".

@FitOnScreen		Valid Values: Y (default), or N

					If "Y", a combination of cell widths (in minutes) and # of cells is chosen so that the output is likely to fit on one screen 
					without horizontal scrolling. (The actual width depends on both the @HoursBack value and whether output is going to a 
					clickable-XML field or to the console.) Job names are placed on the right-hand side. This behavior increases the likelihood 
					that all of the matrix data will fit on one screen if the SSMS Object Explorer and Object Properies windows are collapsed.

					If @FitOnScreen=N is specified, the maximum matrix width is 360 characters. Specifying "N" generally gives a more detailed view 
					of the data, as the minute-length of an individual matrix cell is smaller and thus more granular. "Y" as the default allows for 
					initial, quick review of job outcomes, and then "N" can be specified along with a desired @PointInTime value to closely examine 
					a narrower time window.';
	RAISERROR(@helpstr,10,1);
	SET @helpstr = N'
@DisplayConfigOptions	Valid Values: 0, 1 (default), 2

					Whether to compare the current SQL Agent config settings with the install defaults and display the results. 0 does not do the
					comparison nor display anything, 1 does the compare but only displays the differences, and 2 does the compare and displays
					all of the (important) config options.
					
					If 1 is chosen, most of the SQL Agent config options are examined and any variance from Microsoft installation defaults are 
					presented to the user. If 2 is chosen, all SQL Agent config options that are examined by this procedure are returned, regardless 
					of whether they vary from the defaults. If 0 is chosen, no examination is done and no config information is returned.';

	RAISERROR(@helpstr,10,1);
	SET @helpstr = N'
@DisplayAgentLog	Valid Values: 0, 1 (default), 2, or 3

					If 1 (the default) is chosen, the most recent SQL Agent error log is examined for Severity 1 errors. If any of these errors 
					exist, the full error log (except for some very common and benign messages) is returned as a clickable XML value. 
					Other possible values: 
								0		the SQL Agent log is not examined and nothing is returned. 
								2		always displays the current log
								3		always displays the 3 most recent SQL Agent logs

					(The decision to only return the 3 most recent logs is due to the fact that there is currently no way within T-SQL to determine 
					the number of SQL Agent log files retained. And because xp_readerrorlog throws an error that is uncatchable by TRY...CATCH, 
					walking log file numbers backwards until error is not an attractive option. It would be very surprising to encounter a SQL instance 
					that has had the number of SQL Agent log files retained to less than 3).

@Queries			Valid Values: N (default) or Y

					If Y, clickable-XML fields are returned that contains a number of helpful queries relating to SQL Agent jobs, steps, 
					schedules, etc. These queries essentially "extend" the functionality of this tool in a simple way.

@Debug				Valid Values: 0 (default), 1, or 2

					If 1, a number of result sets are displayed to assist in checking important steps along the way to constructing the history matrix. 
					If 2, displays messages for any section of the code that runs > 250 ms.';

	RAISERROR(@helpstr,10,1);

	IF @Help = N'PARAMS'
	BEGIN
		GOTO exitloc
	END
	ELSE
	BEGIN
		SET @helpstr = N'
		';
		RAISERROR(@helpstr,10,1);
	END


helpcolumns:
	SET @helpstr = N'
Columns
---------------------------------------------------------------------------------------------------------------------------------------------------------------
Job History Matrix			A large text string converted to XML (to make it "click-able") of historical job outcomes. This matrix allows the user to 
							quickly view job start and completion times, outcomes, durations, job enable/disable status, and concurrent execution. 
							The intended use case is for the user to evaluate a given window of time in order to quickly find potential problems in 
							job scheduling and execution. This column is empty when @ToConsole="Y" (i.e. when the matrix is directed to the Messages
							tab), or when there are no SQL Agent jobs present on the system.

							The matrix is always broken up into evenly-sized time blocks (e.g. 5 minutes long). The time blocks are defined
							such that the boundaries are always on the top of the minute, and the block length must be a root of 60 so that
							the top of the hour is also the start of a time block. This means that the @PointInTime value is usually not exactly
							the end of the matrix, but it is guaranteed to fall into the final time block.

							For example, if NULL is passed and GETDATE() returns 12:53, and @HoursBack=24 (resulting in time blocks of 15 minutes),
							then the final time block will be 12:45 to 1:00.

							For a complete legend to the symbols and other content present in this matrix, see the MATRIX LEGEND section below
';

	RAISERROR(@helpstr,10,1);
	SET @helpstr = N'
SQL Agent Option			These 3 columns return a set of SQL Agent configuration options (or rather, descriptive labels that identify SQL Agent 
Current Value				config options). These fields contain data when @DisplayConfigOptions=2, or when @DisplayConfigOptions=1 and 
Default/Expected Value		there are config options which have been changed from Microsoft installation defaults
							than the installation defaults. (If @DisplayConfigOptions=2, all options are displayed regardless of comparison).

SQL Agent Logs				A clickable XML result column that contains relevant records from the SQL Server error log. This output can alert 
							the user to warning or error messages in the SQL Agent subsystem that might otherwise go overlooked. This column contains
							data when @DisplayAgentLog = 2 or = 3, or when @DisplayAgentLog=1 and Severity 1 error records exist in the most 
							current log file.
							
Queries						A clickable XML result column that contains various T-SQL queries against the msdb SQL agent catalog objects. These
							queries are divided into 3 groups: Jobs/Steps/Schedules, Operational stuff (alerts, proxies, job servers, etc), 
							and SSIS and Maint stuff. These queries can be copy-pasted into a new window for quick access to frequently-requested
							information.
							';

	RAISERROR(@helpstr,10,1);

	IF @Help = N'COLUMNS'
	BEGIN
		GOTO exitloc
	END
	ELSE
	BEGIN
		SET @helpstr = N'
		';
		RAISERROR(@helpstr,10,1);
	END

helpmatrix:
	SET @helpstr = N'
Matrix Legend
---------------------------------------------------------------------------------------------------------------------------------------------------------------
The job history matrix employs a number of symbols and formatting choices to communicate a large quantity of information in a concise, quickly-viewable way. 

1) The job history matrix is really 3 sub-matrices. The top matrix is for jobs that have had at least 1 unsuccessful outcome during
	the matrix time window, or are currently running. This draws the users attention to failing or long-running/hung jobs quickly.
	The middle matrix holds jobs that have run at least 1 time in the time window and have always had successful outcomes.
	The bottom matrix lists jobs that have had no runs during the time window, and is primarily useful to look for jobs that
	should have run but did not (e.g. a DB stats update that may have been disabled, leading to system performance problems).
	This final matrix is redundant, as it will always be empty; a future version of this proc may change the formatting.

	The overall time window covered by all 3 sub-matrices is exactly the same.

2) Job Names are printed on the right-hand side of their sub-matrix when @FitOnScreen="Y", so that the matrix is more likely to 
	remain on the screen. This also allows long Job names to be printed without truncation.
				
3) The @HoursBack parameter is repeated for the benefit of the user, along with its resulting cell-minute-length. 

4) If the last start time for the SQL Server DB engine falls within the time window, a message appears in the header. If 
	SQL Agent last started within the time window, and its start time was not within 1 minute of the DB engine start time,
	a separate message appears in the header. ';

	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
5) The top sub-matrix always starts with 2 header rows: one that lists the hour markers (in military time) and the other that
	lists tick marks and hyphens. The point of both is to aid the user in quickly identifying the timeframe for a given job
	outcome. Above the 2 header rows are the begin and end timestamps of the time window, with precision down to the millisecond.

6) Each sub-matrix is made up of "cells", and each cell represents a time window for a given job. A time window always begins on
	the "00" second and ends on the "59.990" second. If a job has an outcome (success, failure, cancellation, or retry), that
	outcome will be entered into the cell. If a job was executing for the full duration of that cell, an appropriate symbol
	will be entered. 

7) Matrix Cell Hierarchy
	Because a job may start and stop multiple times within a time window (even a small 1 minute time window), the following
	symbols are presented in precedence order. Since a matrix cell is always only 1 character wide, items higher in the list 
	take precedence over lower items. Thus, a job may have succeeded 10 times and retried once in the time window represented 
	by a given cell, but if it also failed at least once in that time window, an "F" will be printed, giving no indication of 
	the # of successes or retries.

		"F"		The job has failed at least once in the time window represented by this cell.

		"R"		The job has retried at least once in this time window.

		"C"		The job has cancelled at least once in this time window.

		"X"		The job has encountered an unexpected msdb.dbo.sysjobhistory.job_run_status value. Research is needed

		"9"		The job has had 9 or more successful completions during the time window.';

	RAISERROR(@helpstr,10,1);
	
	SET @helpstr = N'
		"<number between 2 and 9>"		The job has had this many successful completions during the time window. Since 
				"9" is the largest single-digit number possible, higher numbers of job completions (e.g. 15) are still
				represented as "9"

		"/"		The job has had 1 successful completion in this time window.

		"^"		The job has started once during this time window, but did not complete in the same time window.

		"~" and "!"		If a job is running for a whole time window (i.e. its start occurred in an earlier time window
				and its completion is in a later time window or it has not completed), then one of 2 "running" symbols
				are used. The "~" symbol is the standard; however, if a job exceeds its average duration (obtained by
				inspecting SUCCESSFUL job outcomes in msdb.dbo.sysjobhistory), then time windows beyond the average 
				duration will receive a "!" symbol.

				To be clear, a given job execution may involve both "~" and "!" symbols. For example, a job 
				may have the following characters on its matrix:
						^~~~!!!!!!!/
				This indicates that the job started in one time window, kept executing for 10 more time windows, and
				finally stopped in its 12th time window. If each time window represents 1 minute, then we know that
				its average duration (for successes) is about 4 minutes (give or take a minute), and this run exceeded
				that average starting in its 5th minute.
	'
	RAISERROR(@helpstr,10,1);

	IF @Help = N'MATRIX'
	BEGIN
		GOTO exitloc
	END
	ELSE
	BEGIN
		SET @helpstr = N'
		';
		RAISERROR(@helpstr,10,1);
	END

exitloc:

	RETURN 0;
END
GO
