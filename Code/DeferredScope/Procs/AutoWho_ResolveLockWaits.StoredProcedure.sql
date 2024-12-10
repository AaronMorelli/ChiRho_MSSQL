SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_ResolveLockWaits
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

	FILE NAME: AutoWho_ResolveLockWaits.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ResolveLockWaits

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Takes the raw data from TAW for lock waits and attempts to parse out the various identifiers
		to get more human-readable information about the resources involved.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_ResolveLockWaits @CollectionInitiatorID = 255, @FirstCaptureTimeUTC='2017-07-24 04:00', @LastCaptureTimeUTC='2017-07-24 06:00'
*/
(
	@CollectionInitiatorID	TINYINT,
	@FirstCaptureTimeUTC	DATETIME,	--This proc ASSUMES that these are valid capture times in @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes
	@LastCaptureTimeUTC		DATETIME	--Bad things may occur if the values passed in are not specific UTCCaptureTime entries
)
AS
BEGIN
	SET NOCOUNT ON;

	/*
		The initiator could be the background one (255) or any of the user-initiated collections (1,2)
		The First/Last times could be the same time (i.e. a single capture) or could be a range.
		
		The below logic should work correctly for any of these combinations of values.

		The First/Last params should be valid capture times (the PostProcessor will have verified that for us). 
		It's also likely that some of the capture times in that range will have already been processed before,
		since that range will probably be 45 minutes, at least for the background. So we need to evaluate 
		the capture times in this window and just do the post-processing on those that we haven't actually 
		done before.
	*/
	DECLARE
		@EffectiveFirstCaptureTimeUTC		DATETIME,
		@EffectiveLastCaptureTimeUTC		DATETIME;

	DECLARE 
		@errorloc				NVARCHAR(50),
		@errormsg				NVARCHAR(4000),
		@errorsev				INT,
		@errorstate				INT,
		@rc						INT,
		@lv__DurationStart		DATETIME2(7),
		@lv__DurationEnd		DATETIME2(7),
		@lv__SmallDynSQL		NVARCHAR(4000),
		@lv__curDBName			NVARCHAR(256),
		@lv__curcontextdbid		SMALLINT,
		@lv__curloopdbid		SMALLINT,
		@lv__curobjid			BIGINT,
		@lv__ObtainedObjID		INT,
		@lv__ObtainedObjName	NVARCHAR(128),
		@lv__ObtainedSchemaName	 NVARCHAR(128),
		@lv__ResolutionName		NVARCHAR(256);

	DECLARE @InData_NumRows INT,
			@InData_NumLocks INT,
			@InData_NumKey INT,
			@InData_NumRid INT,
			@InData_NumPage INT,
			@InData_NumObj INT,
			@InData_NumApp INT,
			@InData_NumHobt INT,
			@InData_NumAlloc INT,
			@InData_NumDB INT,
			@InData_NumFile INT,
			@InData_NumExtent INT,
			@InData_NumMeta INT;

	DECLARE  --the action we take on the wait_type & resource_description fields varies by the type of wait.
		-- we assign numeric "categories" as soon as we capture the data from sys.dm_os_waiting_tasks and use the
		-- numeric category in various logic. 
		@enum__waitspecial__none			TINYINT,
		@enum__waitspecial__lck				TINYINT,
		@enum__waitspecial__pgblocked		TINYINT,
		@enum__waitspecial__pgio			TINYINT,
		@enum__waitspecial__pg				TINYINT,
		@enum__waitspecial__latchblocked	TINYINT,
		@enum__waitspecial__latch			TINYINT,
		@enum__waitspecial__cxp				TINYINT,
		@enum__waitspecial__other			TINYINT
	;

	SET @lv__DurationStart = SYSUTCDATETIME();

	--For the "waitspecial" enumeration, the numeric values don't necessarily have any comparison/ordering meaning among each other.
	-- Thus, the fact that @enum__waitspecial__pgblocked = 7 and this is larger than 5 (@enum__waitspecial__lck) isn't significant.
	SET @enum__waitspecial__none =			CONVERT(TINYINT, 0);
	SET @enum__waitspecial__lck =			CONVERT(TINYINT, 5);
	SET @enum__waitspecial__pgblocked =		CONVERT(TINYINT, 7);
	SET @enum__waitspecial__pgio =			CONVERT(TINYINT, 10);
	SET @enum__waitspecial__pg =			CONVERT(TINYINT, 15);
	SET @enum__waitspecial__latchblocked =	CONVERT(TINYINT, 17);
	SET @enum__waitspecial__latch =			CONVERT(TINYINT, 20);
	SET @enum__waitspecial__cxp =			CONVERT(TINYINT, 30);
	SET @enum__waitspecial__other =			CONVERT(TINYINT, 25);

	
BEGIN TRY

	IF OBJECT_ID('tempdb..#LockWaitProcessCaptureTimes') IS NOT NULL DROP TABLE #LockWaitProcessCaptureTimes;
	CREATE TABLE #LockWaitProcessCaptureTimes (
		UTCCaptureTime DATETIME NOT NULL
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #LockWaitProcessCaptureTimes(UTCCaptureTime);

	INSERT INTO #LockWaitProcessCaptureTimes (
		UTCCaptureTime
	)
	SELECT 
		ct.UTCCaptureTime
	FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
	WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
	AND ct.UTCCaptureTime >= @FirstCaptureTimeUTC
	AND ct.UTCCaptureTime <= @LastCaptureTimeUTC
	AND ct.PostProcessed_Lock = 0;

	SET @rc = ROWCOUNT_BIG();

	IF @rc = 0
	BEGIN
		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'No Unprocessed LockWaits', @Message='No unprocessed LockWait rows to process';
		RETURN 0;
	END

	SELECT 
		@EffectiveFirstCaptureTimeUTC = ss.UTCCaptureTime
	FROM (
		SELECT TOP 1 
			t.UTCCaptureTime
		FROM #LockWaitProcessCaptureTimes t
		ORDER BY t.UTCCaptureTime ASC
	) ss;

	SELECT 
		@EffectiveLastCaptureTimeUTC = ss.UTCCaptureTime
	FROM (
		SELECT TOP 1 
			t.UTCCaptureTime
		FROM #LockWaitProcessCaptureTimes t
		ORDER BY t.UTCCaptureTime DESC
	) ss;


	SET @errorloc = N'GatherProfile';
	SET @InData_NumRows = NULL; 
	SELECT 
		@InData_NumRows = NumRows, 
		@InData_NumLocks = NumLock,
		@InData_NumKey = NumKeyLock,
		@InData_NumRid = NumRidLock,
		@InData_NumPage = NumPageLock,
		@InData_NumObj = NumObjectLock,
		@InData_NumApp = NumAppLock,
		@InData_NumHobt = NumHobtLock,
		@InData_NumAlloc = NumAllocLock,
		@InData_NumDB = NumDBLock,
		@InData_NumFile = NumFileLock,
		@InData_NumExtent = NumExtentLock,
		@InData_NumMeta = NumMetaLock
	FROM (
		SELECT 
			NumRows = SUM(1), 
			NumLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck
								THEN 1 ELSE 0 END),
			NumKeyLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 1
								THEN 1 ELSE 0 END),
			NumRidLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 2
								THEN 1 ELSE 0 END),
			NumPageLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 3
								THEN 1 ELSE 0 END),
			NumObjectLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 4
								THEN 1 ELSE 0 END),
			NumAppLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 5
								THEN 1 ELSE 0 END),
			NumHobtLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 6
								THEN 1 ELSE 0 END),
			NumAllocLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 7
								THEN 1 ELSE 0 END),
			NumDBLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 8
								THEN 1 ELSE 0 END),
			NumFileLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 9
								THEN 1 ELSE 0 END),
			NumExtentLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 10
								THEN 1 ELSE 0 END),
			NumMetaLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 11
								THEN 1 ELSE 0 END)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC

		--We do NOT include this clause b/c we want to have a sense of how many TAW records are in the time range, and also because
		-- the node/status resolution always reviews all TAW records in the time range.
		--AND taw.resolution_successful = CONVERT(bit,0)
	) ss;

	IF ISNULL(@InData_NumLocks,0) = 0
	BEGIN
		--No lock waits in this period (hopefully this is the common case!)
		--Mark the capture times as processed and exit
		UPDATE targ 
		SET PostProcessed_Lock = 255
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
			INNER JOIN #LockWaitProcessCaptureTimes t
				ON targ.UTCCaptureTime = t.UTCCaptureTime
		WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
		AND targ.UTCCaptureTime >= @EffectiveFirstCaptureTimeUTC
		AND targ.UTCCaptureTime <= @EffectiveLastCaptureTimeUTC;

		IF @CollectionInitiatorID = 255
		BEGIN
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'No LockWaits found', @Message='No lock waits found in this period. Exiting...';
		END
		RETURN 0;
	END

	/*  We are going to pull data from @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits for both page latch and locks, so we can tie them to object names
	
		For latches, we need the resource_dbid (dbid), wait_special_number (file id), and resource_associatedobjid (page #)

		For locks, we need the resource_dbid (dbid), and the resource_associatedobjid (object id)

		And of course we need the key fields from TAW so we can do our final update
	*/
	CREATE TABLE #tasks_and_waits (
		UTCCaptureTime				[datetime]			NOT NULL,
		[task_address]				[varbinary](8)		NOT NULL,
		[session_id]				[smallint]			NOT NULL,	--  Instead of using @lv__nullsmallint, we use -998 bc it has a special value "tasks not tied to spids",
																	--		and our display logic will take certain action if a spid is = -998
		[request_id]				[smallint]			NOT NULL,	--  can hold @lv__nullsmallint
		[exec_context_id]			[smallint]			NOT NULL,	--	ditto
		[blocking_session_id]		[smallint]			NOT NULL,	
		[blocking_exec_context_id]	[smallint]			NOT NULL,

		[wait_special_tag]			[nvarchar](100)		NOT NULL,

		[resource_dbid]				[int]				NULL,		--dbid; populated for lock and latch waits
		[context_database_id]		[smallint]			NULL,		--sess__database_id from SAR. Used to compare to resource_dbid; comparison affects resolution name
		[resource_associatedobjid]	[bigint]			NULL,		--the page # for latch waits, the "associatedobjid=" value for lock waits

		[wait_special_number]		[int]				NULL,		-- node id for CXP, lock type for lock waits, file id for page latches
																	-- left NULL for the temp table, but not-null for the perm table
		[resource_description]		NVARCHAR(3072)		NULL,
		[resolution_successful]		BIT					NOT NULL,
		[resolved_dbname]			NVARCHAR(256)		NULL,
		[resolved_name]				NVARCHAR(256)		NULL
	);

	CREATE TABLE #UniqueHobtDBs (
		resolved_dbname				NVARCHAR(256) NOT NULL,
		resource_dbid				SMALLINT NOT NULL,
		resource_associatedobjid	BIGINT NOT NULL,
		context_database_id			SMALLINT NULL
	);
	
	SET @lv__DurationStart = SYSUTCDATETIME(); 

	/* Here's the mapping for wait number to lock type: 

	WHEN resource_description LIKE N'%keylock%' THEN		CONVERT(INT,1)		-- N'KEY'
	WHEN resource_description LIKE N'%ridlock%' THEN		CONVERT(INT,2)		-- N'RID'
	WHEN resource_description LIKE N'%pagelock%' THEN		CONVERT(INT,3)		-- N'PAGE'
	WHEN resource_description LIKE N'%objectlock%' THEN		CONVERT(INT,4)		-- N'OBJECT'
	WHEN resource_description LIKE N'%applicationlock%' THEN CONVERT(INT,5)		-- N'APP'
	WHEN resource_description LIKE N'%hobtlock%' THEN		CONVERT(INT,6)		-- N'HOBT'
	WHEN resource_description LIKE N'%allocunitlock%' THEN  CONVERT(INT,7)		-- N'ALLOCUNIT'
	WHEN resource_description LIKE N'%databaselock%' THEN	CONVERT(INT,8)		-- N'DB'				+++
	WHEN resource_description LIKE N'%filelock%' THEN		CONVERT(INT,9)		-- N'FILE'
	WHEN resource_description LIKE N'%extentlock%' THEN		CONVERT(INT,10)		-- N'EXTENT'
	WHEN resource_description LIKE N'%metadatalock%' THEN	CONVERT(INT,11)		-- N'META'
	*/


	/* patterns 0 and 1
	***** PATTERN 0: just need resolved DB name via join
	For DATABASE: databaselock subresource=<databaselock-subresource> dbid=<db-id>
		DATABASE: <dbname>

		--For the 2 below, we need to append a numeric value, but that's pretty easy.
		--For both, fileid is stored in taw.associatedObjectId
	For FILE: filelock fileid=<file-id> subresource=<filelock-subresource> dbid=<db-id>
		filelock fileid=0 subresource=FULL dbid=12 id=lock2b95e01700 mode=X
		FILE: <dbname>:file-id

	For EXTENT: extentlock fileid=<file-id> pageid=<page-id> dbid=<db-id>
		EXTENT:<dbname>:<file-id>


	***** PATTERN 1: need resolved DB name (via join) and need to parse out & append other info ******
	For APPLICATION: applicationlock hash=<hash> databasePrincipalId=<role-id> dbid=<db-id>
		applicationlock hash=Create_ETLSnapshot_Lockbd07b95d databasePrincipalId=0 dbid=12 id=lock5364a15880 mode=X
		associatedObjectId is -929
		APP:<dbname>:hash

	For METADATA: metadatalock subresource=<metadata-subresource> classid=<metadatalock-description> dbid=<db-id>
		metadatalock subresource=STATS classid=object_id = 955150448, stats_id = 44 dbid=8 id=lock15d5b71100 mode=Sch-S
		META:<dbname>:<sub string>
			don't want to try to resolve b/c the classid could be a variety of values
			So just pull out the section starting from subresource and ending right before dbid
	*/
	BEGIN TRANSACTION;

	IF ISNULL(@InData_NumDB,0) > 0 OR ISNULL(@InData_NumFile,0) > 0 OR 
		ISNULL(@InData_NumExtent,0) > 0 OR ISNULL(@InData_NumApp,0) > 0 OR ISNULL(@InData_NumMeta,0) > 0 
	BEGIN
		SET @errorloc = N'Pattern0and1';
		;WITH extractedData AS (
			SELECT 
				taw.resource_dbid,
				taw.resource_associatedobjid,
				taw.resource_description,
				taw.resolution_successful,
				taw.resolved_name,
				taw.wait_special_number,
				ResolvedDBName = CASE WHEN d.name IS NULL THEN ISNULL(CONVERT(NVARCHAR(20), NULLIF(resource_dbid,-929)),N'?') ELSE d.name END,
				hashinfo = CASE WHEN taw.wait_special_number = 5		--applicationlock
								THEN (CASE WHEN CHARINDEX(N'hash=', resource_description) > 0
											THEN SUBSTRING(resource_description, 
													CHARINDEX(N'hash=', resource_description)+5, --starting point

													--ending point is at the next space
													-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
													ISNULL(
														NULLIF(CHARINDEX(N' ', 
																SUBSTRING(resource_description, 
																	CHARINDEX(N'hash=', resource_description)+5, 
																	--There should be a space (or the end of the string) within the next 100 characters :-)
																	100
																	)
																), 
																0
															)
															, 50
														)
													)
											ELSE NULL END )
									ELSE NULL 
									END,
				metainfo = CASE WHEN taw.wait_special_number = 11		--metadatalock
								THEN (CASE WHEN CHARINDEX(N'subresource=', resource_description) > 0
											THEN SUBSTRING(resource_description, 
													CHARINDEX(N'subresource=', resource_description)+12, --starting point
													--Stop right before dbid. If we can't find dbid, just get 20 chars

													ISNULL(NULLIF(CHARINDEX(N'dbid=',resource_description),0),
														(CHARINDEX(N'subresource=', resource_description) + 33))
														- 
														(CHARINDEX(N'subresource=', resource_description) + 13)
													)
											ELSE NULL END )
								ELSE NULL 
								END 
			FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
				LEFT OUTER JOIN sys.databases d
					ON taw.resource_dbid = d.database_id
			WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
			AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
			AND taw.resolution_successful = CONVERT(BIT,0)
			AND taw.wait_special_category = @enum__waitspecial__lck 
			AND taw.wait_special_number IN (
				8		--DB
				,9		--File
				,10		--Extent
				,5		--App
				,11		--Meta
			)
		)
		UPDATE extractedData
		SET resolution_successful = CONVERT(BIT,1),
			resolved_name = CASE WHEN wait_special_number = 8	--db
								THEN ResolvedDBName
								WHEN wait_special_number IN (9,10)	--file, extent
									THEN ResolvedDBName + N':' + ISNULL(CONVERT(NVARCHAR(20),NULLIF(resource_associatedobjid,-929)),N'?')
								WHEN wait_special_number = 5	--app
									THEN ResolvedDBName + N':' + ISNULL(hashinfo,N'?')
								WHEN wait_special_number = 11	--meta
									THEN ResolvedDBName + N':' + ISNULL(metainfo,N'?')
							ELSE N''
							END
		;

		SET @lv__DurationEnd = SYSUTCDATETIME();

		IF @CollectionInitiatorID = 255
		BEGIN
			SET @errormsg = N'Lock resolution (Pattern 0 and 1) processed ' + 
						CONVERT(NVARCHAR(20),
						(ISNULL(@InData_NumDB,0) + ISNULL(@InData_NumFile,0) + ISNULL(@InData_NumExtent,0) + ISNULL(@InData_NumApp,0) + ISNULL(@InData_NumMeta,0))
						) + 
				N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='ResolvePat01', @Message=@errormsg;
		END

		SET @lv__DurationStart = SYSUTCDATETIME();
	END		--Pattern 0 & 1: DB/File/Extent/App/Meta

		
	/*
	***** PATTERN 2: need resolved DB name (via join) and use the value in associatedObjectId to either
					convert+append the associatedObectId in numeric form
					or try to obtain a partition (Objname:ix:pt) from the hobtid by querying sys.partitions ******

	For PAGE: pagelock fileid=<file-id> pageid=<page-id> dbid=<db-id> subresource=<pagelock-subresource>
		pagelock fileid=1 pageid=4399019 dbid=11 id=lock3a5f273300 mode=IX associatedObjectId=72057594310098944

	For Key: keylock hobtid=<hobt-id> dbid=<db-id>
		keylock hobtid=72057595543486464 dbid=12 id=lock11af9a5300 mode=U associatedObjectId=72057595543486464

	For RID: ridlock fileid=<file-id> pageid=<page-id> dbid=<db-id>
		ridlock fileid=1 pageid=10245 dbid=12 id=lock5396a4b180 mode=X associatedObjectId=72057594063552512

	For HOBT: hobtlock hobtid=<hobt-id> subresource=<hobt-subresource> dbid=<db-id>
			--hobt is stored in associatedObjectId

	For ALLOCATION_UNIT: allocunitlock hobtid=<hobt-id> subresource=<alloc-unit-subresource> dbid=<db-id>
			--hobt is stored in associatedObjectId
	*/

	IF ISNULL(@InData_NumPage,0) > 0 OR ISNULL(@InData_NumKey,0) > 0 OR ISNULL(@InData_NumRid,0) > 0 
		OR ISNULL(@InData_NumHobt,0) > 0 OR ISNULL(@InData_NumAlloc,0) > 0
	BEGIN
		TRUNCATE TABLE #tasks_and_waits;

		SET @errorloc = N'Pat2_pull';
		INSERT INTO #tasks_and_waits (
			UTCCaptureTime,
			task_address,
			session_id,
			request_id,
			exec_context_id,
			blocking_session_id,
			blocking_exec_context_id,
			wait_special_tag,
			context_database_id,
			resource_dbid,
			resource_associatedobjid,
			resolved_dbname,
			resolution_successful
		)
		SELECT --key
			taw.UTCCaptureTime,
			task_address,
			taw.session_id,
			taw.request_id,
			taw.exec_context_id,
			taw.blocking_session_id,
			taw.blocking_exec_context_id,
			taw.wait_special_tag,
			context_database_id = ISNULL(sar.sess__database_id,-777),
			taw.resource_dbid, 
			taw.resource_associatedobjid,
			d.name,
			CONVERT(BIT,0)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK)
				ON taw.UTCCaptureTime = sar.UTCCaptureTime
				AND taw.session_id = sar.session_id
				AND taw.request_id = sar.request_id
			INNER JOIN #LockWaitProcessCaptureTimes t		--need this join for the 1am-2am DST problem
				ON sar.SPIDCaptureTime = t.SPIDCaptureTime
			LEFT OUTER JOIN sys.databases d
					ON taw.resource_dbid = d.database_id
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND sar.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND sar.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC

		AND taw.resolution_successful = CONVERT(BIT,0)
		AND taw.resource_dbid > 0
		AND taw.resource_associatedobjid > 0
		AND taw.wait_special_category = @enum__waitspecial__lck 
		AND taw.wait_special_number IN (
				1		--key
				,2		--rid
				,3		--page
				,6		--hobt
				,7		--alloc
			)
		;

		INSERT INTO #UniqueHobtDBs (
			resolved_dbname,
			resource_dbid,
			resource_associatedobjid,
			context_database_id
		)
		SELECT DISTINCT 
			resolved_dbname,
			resource_dbid,
			resource_associatedobjid,
			context_database_id
		FROM #tasks_and_waits
		WHERE resolved_dbname IS NOT NULL		--we only loop over valid DB Names (b/c of our dynamic SQL w/USE below)
		;

		--set the timeout 
		SET @errorloc = N'Set timeout2';
		SET LOCK_TIMEOUT 50;

		SET @errorloc = N'Pat2_curs1';
		DECLARE iterateHobtDBs CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT resolved_dbname, resource_dbid
		FROM #UniqueHobtDBs
		ORDER BY resolved_dbname
		;

		SET @errorloc = N'Pat2_curs2';
		OPEN iterateHobtDBs;
		FETCH iterateHobtDBs INTO @lv__curDBName, @lv__curloopdbid;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @lv__SmallDynSQL = N'USE ' + QUOTENAME(@lv__curDBName) + N';
			UPDATE targ 
			SET resolved_name = ss.resolved_name,
				resolution_successful = CONVERT(BIT,1)
			FROM #tasks_and_waits targ
				INNER JOIN (
				SELECT 
					u.resource_dbid, u.resource_associatedobjid,
					resolved_name = CASE WHEN context_database_id <> resource_dbid THEN u.resolved_dbname + N''.'' ELSE N'''' END + 
							CASE WHEN s.name = N''dbo'' THEN N''.'' ELSE s.name + N''.'' END + o.name + N'':'' + CONVERT(NVARCHAR(20),p.index_id) + 
							CASE WHEN p.partition_number = 1 THEN N'''' ELSE N'':'' + CONVERT(NVARCHAR(20),p.partition_number) END
				FROM sys.partitions p
					INNER JOIN sys.objects o
						ON p.object_id = o.object_id
					INNER JOIN sys.schemas s
						ON o.schema_id = s.schema_id
					INNER JOIN #UniqueHobtDBs u
						ON u.resource_associatedobjid = p.hobt_id
				WHERE u.resource_dbid = @lv__curloopdbid
			) ss
				ON targ.resource_dbid = ss.resource_dbid
				AND targ.resource_associatedobjid = ss.resource_associatedobjid
			;';

			SET @errorloc = N'Pat2_dyn';
			EXEC sp_executesql @lv__SmallDynSQL, N'@lv__curloopdbid SMALLINT', @lv__curloopdbid;

			FETCH iterateHobtDBs INTO @lv__curDBName, @lv__curloopdbid;
		END

		SET @errorloc = N'Pat2_close';
		CLOSE iterateHobtDBs;
		DEALLOCATE iterateHobtDBs;

		SET @errorloc = N'Reset lock_timeout';
		SET LOCK_TIMEOUT -1;

		SET @errorloc = N'Pat2_upd';
		UPDATE taw 
		SET resolution_successful = CONVERT(BIT,1),
			resolved_name = CASE WHEN tawtemp.resolution_successful = CONVERT(BIT,1)
								THEN tawtemp.resolved_name
								ELSE (CASE WHEN tawtemp.resource_dbid <> tawtemp.context_database_id 
										THEN CONVERT(nvarchar(20),tawtemp.resource_dbid) + N':' ELSE N'' END + 
										CONVERT(nvarchar(20),tawtemp.resource_associatedobjid))
								END 
		FROM #tasks_and_waits tawtemp
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
				ON tawtemp.UTCCaptureTime = taw.UTCCaptureTime
				AND tawtemp.task_address = taw.task_address
				AND tawtemp.session_id = taw.session_id
				AND tawtemp.request_id = taw.request_id
				AND tawtemp.exec_context_id = taw.exec_context_id
				AND tawtemp.blocking_session_id = taw.blocking_session_id
				AND tawtemp.blocking_exec_context_id = taw.blocking_exec_context_id
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND taw.wait_special_category = @enum__waitspecial__lck
		AND taw.wait_special_number IN (
				1		--key
				,2		--rid
				,3		--page
				,6		--hobt
				,7		--alloc
		)
		AND (tawtemp.resolution_successful = CONVERT(BIT,1)
			OR (tawtemp.resolution_successful = CONVERT(BIT,0)
				AND tawtemp.resolved_dbname IS NULL 
			)
		);

		SET @lv__DurationEnd = SYSUTCDATETIME();

		IF @CollectionInitiatorID = 255
		BEGIN
			SET @errormsg = N'Lock resolution (Pattern 2) processed ' + 
						CONVERT(NVARCHAR(20),
						(ISNULL(@InData_NumKey,0) + ISNULL(@InData_NumRid,0) + ISNULL(@InData_NumPage,0) + ISNULL(@InData_NumHobt,0) + ISNULL(@InData_NumAlloc,0))
						) + 
				N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='ResolvePat2', @Message=@errormsg;
		END 

		SET @lv__DurationStart = SYSUTCDATETIME();
	END	--Pattern 2: page/key/rid/hobt/alloc


	IF ISNULL(@InData_NumObj,0) > 0
	BEGIN
		TRUNCATE TABLE #tasks_and_waits;
		/*
		Here's what we want our resolved text to look like for each lock type

			****** Pattern 3: we actually need to resolve the object name
			For OBJECT: objectlock lockPartition=<lock-partition-id> objid=<obj-id> subresource=<objectlock-subresource> dbid=<db-id>
				objectlock lockPartition=8 objid=1045578763 subresource=FULL dbid=12 id=lock43e1f8e680 mode=Sch-M associatedObjectId=1045578763
				OBJECT:<dbname>.<objname resolved from associatedObjectId>
		*/

		SET @errorloc = N'Lock #taw';
		INSERT INTO #tasks_and_waits (
			UTCCaptureTime,
			task_address,
			session_id,
			request_id,
			exec_context_id,
			blocking_session_id,
			blocking_exec_context_id,
			wait_special_tag,
			resource_dbid,
			context_database_id,
			resource_associatedobjid,
			resolved_dbname,
			resolution_successful
		)
		SELECT 
			taw.UTCCaptureTime, 
			taw.task_address,
			taw.session_id,
			taw.request_id,
			taw.exec_context_id,
			taw.blocking_session_id,
			taw.blocking_exec_context_id,
			taw.wait_special_tag,
			taw.resource_dbid,
			context_database_id = ISNULL(sar.sess__database_id,-777),
			taw.resource_associatedobjid,
			d.name,
			CONVERT(BIT,0)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw WITH (NOLOCK)
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK)
				ON taw.UTCCaptureTime = sar.UTCCaptureTime
				AND taw.session_id = sar.session_id
				AND taw.request_id = sar.request_id
			LEFT OUTER JOIN sys.databases d
				ON taw.resource_dbid = d.database_id
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID 
		AND sar.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND sar.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND taw.wait_special_category = @enum__waitspecial__lck
		AND taw.wait_special_number = 4		--obj lock
		AND taw.resource_dbid > 0
		AND taw.resource_associatedobjid > 0
		;

		SET @errorloc = N'CLIDX';
		CREATE CLUSTERED INDEX CL1 ON #tasks_and_waits (resource_dbid, resource_associatedobjid);

		--set the timeout 
		SET @errorloc = N'Set timeout3';
		SET LOCK_TIMEOUT 50;

		--Now resolve locks
		SET @errorloc = N'Pat3 curs';
		DECLARE resolvelockdata CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT 
			resource_dbid, context_database_id,
			resource_associatedobjid,
			resolved_dbname
		FROM #tasks_and_waits taw
		ORDER BY resource_dbid, resource_associatedobjid
		;

		SET @errorloc = N'Open Pat3';
		OPEN resolvelockdata
		FETCH resolvelockdata INTO @lv__curloopdbid, @lv__curcontextdbid, @lv__curobjid, @lv__curDBName;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @lv__ResolutionName = NULL;
			SET @lv__ObtainedObjName = NULL;
			SET @lv__ObtainedSchemaName = NULL;


			--Note that we separate the effort to get Object Name from Schema Name, so that if Object Name works but
			-- then Schema Name gets a timeout, we don't set both to NULL.
			BEGIN TRY
				SET @lv__ObtainedObjName = OBJECT_NAME(@lv__curobjid, @lv__curloopdbid);
			END TRY
			BEGIN CATCH
				SET @lv__ObtainedObjName = NULL; 
			END CATCH

			BEGIN TRY
				SET @lv__ObtainedSchemaName = OBJECT_SCHEMA_NAME(@lv__curobjid, @lv__curloopdbid);
			END TRY
			BEGIN CATCH
				SET @lv__ObtainedSchemaName = NULL; 
			END CATCH

			SET @lv__ResolutionName = CASE WHEN @lv__curloopdbid <> @lv__curcontextdbid
						THEN ISNULL(@lv__curDBName,ISNULL(CONVERT(NVARCHAR(20), NULLIF(@lv__curloopdbid,-929)),N'?')) + N'.'
						ELSE N'' END + 
						ISNULL(@lv__ObtainedSchemaName,N'') + N'.' + 
						ISNULL(@lv__ObtainedObjName,N'(ObjId:' +  CONVERT(NVARCHAR(20),@lv__ObtainedObjID) + N')');

			SET @errorloc = N'lock cursor update #taw';
			UPDATE taw 
			SET resolved_name = @lv__ResolutionName,
				resolution_successful = CONVERT(BIT,1)
			FROM #tasks_and_waits taw
			WHERE taw.resource_dbid = @lv__curloopdbid
			AND taw.resource_associatedobjid = @lv__curobjid
			;

			FETCH resolvelockdata INTO @lv__curloopdbid, @lv__curcontextdbid, @lv__curobjid, @lv__curDBName;
		END

		SET @errorloc = N'close lock cursor';
		CLOSE resolvelockdata;
		DEALLOCATE resolvelockdata;

		SET @errorloc = N'Reset lock_timeout';
		SET LOCK_TIMEOUT -1;

		UPDATE taw 
		SET resolved_name = tawtemp.resolved_name,
			resolution_successful = CONVERT(BIT,1)
		FROM #tasks_and_waits tawtemp
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
				ON tawtemp.UTCCaptureTime = taw.UTCCaptureTime
				AND tawtemp.task_address = taw.task_address
				AND tawtemp.session_id = taw.session_id
				AND tawtemp.request_id = taw.request_id
				AND tawtemp.exec_context_id = taw.exec_context_id
				AND tawtemp.blocking_session_id = taw.blocking_session_id
				AND tawtemp.blocking_exec_context_id = taw.blocking_exec_context_id
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND tawtemp.resolution_successful = CONVERT(BIT,1)
		AND taw.wait_special_category = @enum__waitspecial__lck;

		SET @lv__DurationEnd = SYSUTCDATETIME();

		IF @CollectionInitiatorID = 255
		BEGIN
			SET @errormsg = N'Lock resolution (Pattern 3) processed ' + 
						CONVERT(NVARCHAR(20),
						ISNULL(@InData_NumObj,0) ) + 
				N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='ResolvePat3', @Message=@errormsg;
		END

		SET @lv__DurationStart = SYSUTCDATETIME();
	END		--IF ISNULL(@InData_NumObj,0) > 0
	

	UPDATE targ 
	SET PostProcessed_Latch = 255
	FROM #LockWaitProcessCaptureTimes t
		INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
			ON t.UTCCaptureTime = targ.UTCCaptureTime
	WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
	AND targ.UTCCaptureTime >= @EffectiveFirstCaptureTimeUTC
	AND targ.UTCCaptureTime <= @EffectiveLastCaptureTimeUTC;


	COMMIT TRANSACTION;

	IF @CollectionInitiatorID = 255		--we only log durations for the background trace
	BEGIN
		SET @errormsg = N'LockWait resolve logic applied lock resource info for ' + CONVERT(nvarchar(20),@rc) + 
			N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'ResolveLWdur', @Message=@errormsg;
	END
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	SET @errorstate = ERROR_STATE();
	SET @errorsev = ERROR_SEVERITY();

	SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
		N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
		N' Message: ' + ERROR_MESSAGE();

	EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@errormsg;
	RAISERROR(@errormsg, @errorsev, @errorstate);
	RETURN -999;

END CATCH

	RETURN 0;
END