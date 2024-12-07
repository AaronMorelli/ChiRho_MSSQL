SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [AutoWho].[ResolveWaitIDs]
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

	FILE NAME: AutoWho_ResolveWaitIDs.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ResolveWaitIDs

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Reviews data in TAW for a specific time range (typically the last 15 minutes) and does some post-processing on the data
		to prep it for more useful consumption by the viewers.

	FUTURE ENHANCEMENTS: 

To Execute
------------------------
EXEC AutoWho.ResolveWaitIDs
*/
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

BEGIN TRY
	DECLARE @lv__SmallDynSQL		NVARCHAR(4000),
			@errorloc				NVARCHAR(50),
			@errormsg				NVARCHAR(4000),
			@errorsev				INT,
			@errorstate				INT,
			@scratch__int			INT,
			@cxpacketwaitid			SMALLINT,
			@lv__curloopdbid		SMALLINT,
			@lv__curcontextdbid		SMALLINT,
			@lv__curfileid			SMALLINT,
			@lv__curpageid			BIGINT,
			@lv__curobjid			BIGINT,
			@lv__curwaitnumber		INT,
			@lv__wait_special_tag	NVARCHAR(100),
			@lv__curResourceDesc	NVARCHAR(3072),
			@lv__curDBName			NVARCHAR(256),
			@lv__CurrentExecTime	DATETIME2(7),
			@lv__FirstTAWTime		DATETIME,
			@lv__ObtainedObjID		INT,
			@lv__ObtainedIdxID		INT,
			@lv__ObtainedObjName	NVARCHAR(128),
			@lv__ObtainedSchemaName		NVARCHAR(128),
			@lv__ResolutionName		NVARCHAR(256),
			@lv__ResolutionsFailed	INT=0,
			@lv__ThisResolveTime	DATETIME2(7),
			@lv__IndexCreated		INT=0,
			@lv__DurationStart		DATETIME2(7),
			@lv__DurationEnd		DATETIME2(7),
			@lv__3604EnableSuccessful NCHAR(1)=N'N'
	;

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

	DECLARE 
		@opt__ResolvePageLatches				NCHAR(1),
		@opt__ResolveLockWaits					NCHAR(1),
		@lv__AutoWhoLastLatchResolve			DATETIME2(7),
		@lv__AutoWhoLastLockResolve				DATETIME2(7),
		@lv__AutoWhoLastNodeStatusResolve		DATETIME2(7),
		@lv__OverallMinLastTime					DATETIME2(7)
		;

	DECLARE @InData_NumRows INT, 
			@InData_NumPageLatch INT,
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

	SET @lv__CurrentExecTime = DATEADD(SECOND, -10, SYSDATETIME());		--10 sec fudge, just to steer clear of any race conditions with TAW inserts
	SET @lv__DurationStart = SYSDATETIME();

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

	SELECT @cxpacketwaitid = dwt.DimWaitTypeID
	FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
	WHERE dwt.wait_type = N'CXPACKET';

	SET @errorloc = N'Obtain options';
	SELECT 
		@opt__ResolvePageLatches				= [ResolvePageLatches],
		@opt__ResolveLockWaits					= [ResolveLockWaits]
	FROM AutoWho.Options o;

	SET @errorloc = N'Obtain Last Resolve';
	SELECT 
		@lv__AutoWhoLastLatchResolve = ss.AutoWhoLastLatchResolve,
		@lv__AutoWhoLastLockResolve = ss.AutoWhoLastLockResolve,
		@lv__AutoWhoLastNodeStatusResolve = ss.AutoWhoLastNodeStatusResolve
	FROM (
		SELECT 
			AutoWhoLastLatchResolve = MAX(CASE WHEN Label = N'AutoWhoLastLatchResolve' THEN LastProcessedTime ELSE NULL END),
			AutoWhoLastLockResolve = MAX(CASE WHEN Label = N'AutoWhoLastLockResolve' THEN LastProcessedTime ELSE NULL END),
			AutoWhoLastNodeStatusResolve = MAX(CASE WHEN Label = N'AutoWhoLastNodeStatusResolve' THEN LastProcessedTime ELSE NULL END)
		FROM CoreXR.ProcessingTimes
	) ss;

	--If any "last resolved" are NULL, we grab our earliest TAW record and use that time as our last-resolve time.
	IF @lv__AutoWhoLastNodeStatusResolve IS NULL
		OR (@lv__AutoWhoLastLatchResolve IS NULL AND @opt__ResolvePageLatches = N'Y')
		OR (@lv__AutoWhoLastLockResolve IS NULL AND @opt__ResolveLockWaits = N'Y')
	BEGIN
		SET @errorloc = N'Obtain first TAW';
		SELECT @lv__FirstTAWTime = SPIDCaptureTime
		FROM (
			SELECT TOP 1 SPIDCaptureTime
			FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
			ORDER BY taw.SPIDCaptureTime ASC
		) ss;

		IF @lv__FirstTAWTime IS NULL
		BEGIN
			--NOTHING in the TAW table. Just return
			RETURN 0;
		END
	END

	--If any are null & enabled, set to the minimum record in tasks & waits
	--If one is NULL but not enabled, we do NOT update it. The effect is that the
	-- LastProcessedTime will stay NULL so that if the admin does enable later,
	-- this proc will catch up on all past records (which can take a while!)

	IF @lv__AutoWhoLastNodeStatusResolve IS NULL	--always enabled
	BEGIN
		SET @lv__AutoWhoLastNodeStatusResolve = @lv__FirstTAWTime;

		UPDATE CoreXR.ProcessingTimes
		SET LastProcessedTime = @lv__FirstTAWTime
		WHERE Label = N'AutoWhoLastNodeStatusResolve'
		;
	END

	IF @lv__AutoWhoLastLatchResolve IS NULL AND @opt__ResolvePageLatches = N'Y'
	BEGIN
		SET @lv__AutoWhoLastLatchResolve = @lv__FirstTAWTime;

		UPDATE CoreXR.ProcessingTimes
		SET LastProcessedTime = @lv__FirstTAWTime
		WHERE Label = N'AutoWhoLastLatchResolve'
		;
	END

	IF @lv__AutoWhoLastLockResolve IS NULL AND @opt__ResolveLockWaits = N'Y'
	BEGIN
		SET @lv__AutoWhoLastLockResolve = @lv__FirstTAWTime;

		UPDATE CoreXR.ProcessingTimes
		SET LastProcessedTime = @lv__FirstTAWTime
		WHERE Label = N'AutoWhoLastLockResolve'
		;
	END

	--Find the overall min time, as we're about to do a pass through for the superset time range
	SET @lv__OverallMinLastTime = @lv__AutoWhoLastNodeStatusResolve	--we know we have this time

	IF @lv__OverallMinLastTime > ISNULL(@lv__AutoWhoLastLatchResolve,'9999-01-01')
	BEGIN
		SET @lv__OverallMinLastTime = @lv__AutoWhoLastLatchResolve;
	END

	IF @lv__OverallMinLastTime > ISNULL(@lv__AutoWhoLastLockResolve,'9999-01-01')
	BEGIN
		SET @lv__OverallMinLastTime = @lv__AutoWhoLastLockResolve
	END

	SET @errorloc = N'GatherProfile';
	SET @InData_NumRows = NULL; 
	SELECT 
		@InData_NumRows = NumRows, 
		@InData_NumPageLatch = NumPageLatch,
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
			NumPageLatch = SUM(CASE WHEN taw.wait_special_category IN (@enum__waitspecial__pgblocked, @enum__waitspecial__pgio, @enum__waitspecial__pg)
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME, @lv__AutoWhoLastLatchResolve)
								THEN 1 ELSE 0 END),
			NumLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumKeyLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 1
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumRidLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 2
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumPageLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 3
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumObjectLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 4
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumAppLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 5
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumHobtLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 6
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumAllocLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 7
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumDBLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 8
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumFileLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 9
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumExtentLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 10
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END),
			NumMetaLock = SUM(CASE WHEN taw.wait_special_category = @enum__waitspecial__lck AND taw.wait_special_number = 11
								AND taw.SPIDCaptureTime >= CONVERT(DATETIME,@lv__AutoWhoLastLockResolve)
								THEN 1 ELSE 0 END)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
		WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__OverallMinLastTime) AND CONVERT(DATETIME,@lv__CurrentExecTime)
		--We do NOT include this clause b/c we want to have a sense of how many TAW records are in the time range, and also because
		-- the node/status resolution always reviews all TAW records in the time range.
		--AND taw.resolution_successful = CONVERT(bit,0)
	) ss;


	IF ISNULL(@InData_NumRows,0) = 0
	BEGIN
		--No rows at all in the range! Update last processed times and exit.
		UPDATE CoreXR.ProcessingTimes
		SET LastProcessedTime = @lv__CurrentExecTime
		WHERE Label = N'AutoWhoLastNodeStatusResolve'
		;

		IF @opt__ResolvePageLatches = N'Y'
		BEGIN
			UPDATE CoreXR.ProcessingTimes
			SET LastProcessedTime = @lv__CurrentExecTime
			WHERE Label = N'AutoWhoLastLatchResolve'
			;
		END

		IF @opt__ResolveLockWaits = N'Y'
		BEGIN
			UPDATE CoreXR.ProcessingTimes
			SET LastProcessedTime = @lv__CurrentExecTime
			WHERE Label = N'AutoWhoLastLockResolve'
			;
		END

		INSERT INTO AutoWho.Log 
		(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), NULL, 0, 'ResolveZero', N'No records in TAW were found to resolve for this time window.';

		RETURN 0;
	END	--no rows at all in TAW for the superset time range!


	SET @errorloc = N'create #TT';
	CREATE TABLE #t__dbccpage (
		[ParentObject]				[varchar](100)		NULL,		--can't guarantee that DBCC PAGE will always return non-null values, so cols allow nulls
		[Objectcol]					[varchar](100)		NULL,
		[Fieldcol]					[varchar](100)		NULL,
		[Valuecol]					[varchar](100)		NULL
	);

/*  We are going to pull data from @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits for both page latch and locks, so we can tie them to object names
	
	For latches, we need the resource_dbid (dbid), wait_special_number (file id), and resource_associatedobjid (page #)

	For locks, we need the resource_dbid (dbid), and the resource_associatedobjid (object id)

	And of course we need the key fields from TAW so we can do our final update
*/
	CREATE TABLE #tasks_and_waits (
		SPIDCaptureTime				[datetime]			NOT NULL,
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

	--This table holds partially-aggregated data for our node/status aggregation logic
	CREATE TABLE #TaskResolve1 (
		SPIDCaptureTime				DATETIME NOT NULL,
		session_id					SMALLINT NOT NULL, 
		request_id					SMALLINT NOT NULL, 
		tstate						NVARCHAR(5) NOT NULL,
		parent_node_id				INT NOT NULL, 
		NumTasks					SMALLINT NOT NULL
	);

	CREATE TABLE #TaskResolve2 (
		Rnk							INT NOT NULL, 
		SPIDCaptureTime				DATETIME NOT NULL,
		session_id					SMALLINT NOT NULL,
		request_id					SMALLINT NOT NULL, 
		NodeData					NVARCHAR(256) NULL,
		StatusData					NVARCHAR(256) NULL
	);

	SET @errorloc = N'Insert into #TR1';
	INSERT INTO #TaskResolve1 (
		SPIDCaptureTime,
		session_id,
		request_id,
		tstate,
		parent_node_id,
		NumTasks
	)
	SELECT 
		SPIDCaptureTime,
		session_id,
		request_id,
		tstate,
		ISNULL(parent_node_id,999),
		NumTasks
	FROM (
		SELECT 
			SPIDCaptureTime, 
			session_id,
			request_id,
			tstate,
			parent_node_id, 
			NumTasks = COUNT(*)
		FROM (
			SELECT 
				SPIDCaptureTime,
				session_id,
				request_id,
				task_address,
				tstate,
				scheduler_id
			FROM (
				SELECT 
					taw.SPIDCaptureTime, 
					taw.session_id, 
					taw.request_id, 
					taw.task_address, 
					tstate = CASE WHEN taw.FKDimWaitType = @cxpacketwaitid AND taw.tstate = N'S' THEN N'S(CX)' 
								ELSE taw.tstate END, 
					taw.scheduler_id,
					--because a spid/request/task_address can have multiple entries in this table, 
					-- we use task_priority (which is a ROW_NUMBER partitioned by just session & request)
					-- to decide which row to take for a particular task_address
					rn = ROW_NUMBER() OVER (PARTITION BY taw.SPIDCaptureTime, taw.session_id, taw.request_id, 
												taw.task_address ORDER BY taw.task_priority ASC )
				FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
				WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastNodeStatusResolve)
											AND CONVERT(DATETIME,@lv__CurrentExecTime)
				AND taw.session_id >= 0
				--we don't include this clause b/c we are aggregating data over a complete spid/request
				-- so we want to avoid a scenario where some tasks in a request have been resolved
				-- but we haven't processed all of the tasks and created the sar node/status info data yet.
				--AND taw.resolution_successful = CONVERT(bit,0)
			) ssbase
			WHERE ssbase.rn = 1
		) ss
			--since scheduler_id is nullable in TAW, we do a LOJ so we avoid
			--eliminating any records that have tstate but not scheduler_id
			LEFT OUTER JOIN sys.dm_os_schedulers s
				ON ss.scheduler_id = s.scheduler_id
		GROUP BY SPIDCaptureTime,
			session_id,
			request_id,
			tstate,
			parent_node_id
	) grpbase
	OPTION(RECOMPILE);

	SET @errorloc = N'INSERT into #TR2';
	INSERT INTO #TaskResolve2 (
		Rnk,
		SPIDCaptureTime,
		session_id,
		request_id
	)
	SELECT 
		--since I'm using the XML method to do group concatenation, and I don't want to mess
		-- with conversions to/from datetime values, we grab a rank # for each distinct
		-- unique request
		Rnk = ROW_NUMBER() OVER (ORDER BY SPIDCaptureTime, session_id, request_id),
		SPIDCaptureTime,
		session_id,
		request_id
	FROM (
		SELECT DISTINCT
			SPIDCaptureTime,
			session_id,
			request_id
		FROM #TaskResolve1
	) ss;

	SET @errorloc = N'Update NodeData';
	UPDATE targ 
	SET NodeData = t0.node_info
	FROM #TaskResolve2 targ
		INNER JOIN (
			SELECT 
				nodez_nodes.nodez_node.value('(Rnk/text())[1]', 'INT') AS Rnk,
				nodez_nodes.nodez_node.value('(nodeformatted/text())[1]', 'NVARCHAR(4000)') AS node_info
			FROM (
				SELECT
					CONVERT(XML,
						REPLACE
						(
							CONVERT(NVARCHAR(MAX), nodez_raw.nodez_xml_raw) COLLATE Latin1_General_Bin2,
							N'</nodeformatted></nodez><nodez><nodeformatted>',
							N', '
							+ 
						--LEFT(CRYPT_GEN_RANDOM(1), 0)
						LEFT(CONVERT(NVARCHAR(40),NEWID()),0)

						--This statement sometimes runs very slow, so we are using a "side effecting function" to avoid the default Expression Service caching behavior,
						-- per the Paul White blog article here: http://sqlblog.com/blogs/paul_white/archive/2012/09/05/compute-scalars-expressions-and-execution-plan-performance.aspx 
						)
					) AS nodez_xml 
				FROM (
					SELECT 
						Rnk = CASE WHEN base0.rn = 1 THEN base0.Rnk ELSE NULL END, 
						nodeformatted = CONVERT(nvarchar(20),NumTasks) + N'['+CONVERT(nvarchar(20),parent_node_id)+N']'
					FROM (
						

						SELECT 
							n2.Rnk,
							n1.parent_node_id,
							n1.NumTasks,
							rn = ROW_NUMBER() OVER (PARTITION BY n2.Rnk ORDER BY n1.parent_node_id)
						FROM (
							SELECT 
								SPIDCaptureTime,
								session_id,
								request_id,
								parent_node_id,
								NumTasks = SUM(NumTasks)
							FROM #TaskResolve1
							GROUP BY SPIDCaptureTime, session_id, request_id, parent_node_id
							) n1
							INNER JOIN #TaskResolve2 n2
								ON n1.SPIDCaptureTime = n2.SPIDCaptureTime
								AND n1.session_id = n2.session_id
								AND n1.request_id = n2.request_id
					) base0
					ORDER BY base0.Rnk, base0.parent_node_id
					FOR XML PATH(N'nodez')
				) AS nodez_raw (nodez_xml_raw)
			) as nodez_final
			CROSS APPLY nodez_final.nodez_xml.nodes(N'/nodez') AS nodez_nodes (nodez_node)		--um... yeah "naming things"
			WHERE nodez_nodes.nodez_node.exist(N'Rnk') = 1
		) t0
			ON t0.Rnk = targ.Rnk
	;


	--now do something similar for our task state data
	SET @errorloc = N'Update StatusData';
	UPDATE targ 
	SET StatusData = t0.state_info
	FROM #TaskResolve2 targ
		INNER JOIN (
			SELECT 
				statez_nodes.statez_node.value('(Rnk/text())[1]', 'INT') AS Rnk,
				statez_nodes.statez_node.value('(stateformatted/text())[1]', 'NVARCHAR(4000)') AS state_info
			FROM (
				SELECT
					CONVERT(XML,
						REPLACE
						(
							CONVERT(NVARCHAR(MAX), statez_raw.statez_xml_raw) COLLATE Latin1_General_Bin2,
							N'</stateformatted></statez><statez><stateformatted>',
							N', '
							+ 
						--LEFT(CRYPT_GEN_RANDOM(1), 0)
						LEFT(CONVERT(NVARCHAR(40),NEWID()),0)

						--This statement sometimes runs very slow, so we are using a "side effecting function" to avoid the default Expression Service caching behavior,
						-- per the Paul White blog article here: http://sqlblog.com/blogs/paul_white/archive/2012/09/05/compute-scalars-expressions-and-execution-plan-performance.aspx 
						)
					) AS statez_xml 
				FROM (
					SELECT 
						Rnk = CASE WHEN base0.rn = 1 THEN base0.Rnk ELSE NULL END, 
						stateformatted = tstate + N':'+CONVERT(nvarchar(20),NumTasks)
					FROM (
						SELECT 
							n2.Rnk,
							n1.tstate,
							n1.NumTasks,
							rn = ROW_NUMBER() OVER (PARTITION BY n2.Rnk ORDER BY n1.tstate)
						FROM (
							SELECT 
								SPIDCaptureTime,
								session_id,
								request_id,
								tstate,
								NumTasks = SUM(NumTasks)
							FROM #TaskResolve1
							GROUP BY SPIDCaptureTime, session_id, request_id, tstate 
							) n1
							INNER JOIN #TaskResolve2 n2
								ON n1.SPIDCaptureTime = n2.SPIDCaptureTime
								AND n1.session_id = n2.session_id
								AND n1.request_id = n2.request_id
					) base0
					ORDER BY base0.Rnk, base0.tstate
					FOR XML PATH(N'statez')
				) AS statez_raw (statez_xml_raw)
			) as statez_final
			CROSS APPLY statez_final.statez_xml.nodes(N'/statez') AS statez_nodes (statez_node)		--um... yeah "naming things"
			WHERE statez_nodes.statez_node.exist(N'Rnk') = 1
		) t0
			ON t0.Rnk = targ.Rnk
	;

	SET @errorloc = N'Apply NodeStatus';
	UPDATE targ 
	SET calc__node_info = n.NodeData,
		calc__status_info = n.StatusData
	FROM #TaskResolve2 n
		INNER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests targ
			ON n.SPIDCaptureTime = targ.SPIDCaptureTime
			AND n.session_id = targ.session_id
			AND n.request_id = targ.request_id
	WHERE targ.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastNodeStatusResolve)
								AND CONVERT(DATETIME,@lv__CurrentExecTime)
	OPTION(RECOMPILE, FORCE ORDER);


	--Ok, we've updated SAR, now move our last-updated counter forward.
	UPDATE targ 
	SET LastProcessedTime = @lv__CurrentExecTime
	FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
	WHERE targ.Label = N'AutoWhoLastNodeStatusResolve'
	;

	SET @lv__DurationEnd = SYSDATETIME(); 

	INSERT INTO AutoWho.Log 
	(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
	SELECT SYSDATETIME(), NULL, 0, 'ResolveNSdur', N'NodeStatus resolve logic processed ' + CONVERT(nvarchar(20),@InData_NumRows) + 
		N' rows in ' + CONVERT(nvarchar(20),DATEDIFF(millisecond, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';


	IF IS_SRVROLEMEMBER ('sysadmin') = 1 AND @opt__ResolvePageLatches = N'Y'
		AND ISNULL(@InData_NumPageLatch,0) > 0
	BEGIN
		BEGIN TRY
			DBCC TRACEON(3604) WITH NO_INFOMSGS;
			SET @lv__3604EnableSuccessful = N'Y';
		END TRY
		BEGIN CATCH
			SET @errormsg = N'PageLatch Resolution was requested but cannot enable TF 3604. Message: ' + ERROR_MESSAGE();
			SET @lv__ResolutionsFailed = @lv__ResolutionsFailed + 1;
	
			INSERT INTO AutoWho.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), -29, N'TF3604Enable', @errormsg;
		END CATCH

		IF @lv__3604EnableSuccessful = N'Y'
		BEGIN
			SET @lv__DurationStart = SYSDATETIME(); 
			SET @lv__SmallDynSQL = N'DBCC PAGE(@dbid, @fileid, @pageid) WITH TABLERESULTS';

			SET @errorloc = N'Pgl #taw';
			INSERT INTO #tasks_and_waits (
				SPIDCaptureTime,
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
				wait_special_number,
				resolved_dbname,
				resolution_successful
			)
			SELECT 
				taw.SPIDCaptureTime, 
				taw.task_address,
				taw.session_id,
				taw.request_id,
				taw.exec_context_id,
				taw.blocking_session_id,
				taw.blocking_exec_context_id,
				taw.wait_special_tag,
				taw.resource_dbid,
				ISNULL(sar.sess__database_id,-777),
				taw.resource_associatedobjid,
				taw.wait_special_number,
				d.name,
				CONVERT(BIT,0)
			FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw WITH (NOLOCK)
				INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK)
					ON taw.SPIDCaptureTime = sar.SPIDCaptureTime
					AND taw.session_id = sar.session_id
					AND taw.request_id = sar.request_id
				LEFT OUTER JOIN sys.databases d
					ON taw.resource_dbid = d.database_id
			WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLatchResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
			AND sar.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLatchResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
			AND taw.wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked)
			AND taw.resolution_successful = CONVERT(BIT,0)
			AND taw.resource_dbid > 0
			AND taw.resource_associatedobjid > 0
			/* the reason we omit the below criteria (thus allowing rows like tempdb and system bitmap pages into the data set)
				is that even though we aren't going to try to fully resolve the IDs, we do want to "resolve" by constructing 
				a short text description
			AND taw.wait_special_number > 0
			--don't resolve tempdb pages
			AND taw.resource_dbid <> 2
			--Note that if the page id is a system bitmap page, decoding is not useful
			AND NOT (taw.resource_associatedobjid % 8088 = 0 OR taw.resource_associatedobjid = 1)	--PFS
			AND NOT ( (taw.resource_associatedobjid-1) % 511232 = 0 OR taw.resource_associatedobjid = 3) --SGAM
			AND NOT (taw.resource_associatedobjid % 511232 = 0 OR taw.resource_associatedobjid = 2) --GAM
			AND NOT ( (taw.resource_associatedobjid-6) % 511232 = 0 OR taw.resource_associatedobjid = 6) --DCM
			AND NOT ( (taw.resource_associatedobjid-7) % 511232 = 0 OR taw.resource_associatedobjid = 7) --ML
			*/
			OPTION(RECOMPILE);

			SET @errorloc = N'CLIDX';
			CREATE CLUSTERED INDEX CL1 ON #tasks_and_waits (resource_dbid, resource_associatedobjid);
			SET @lv__IndexCreated = 1;

			--set the timeout 
			SET @errorloc = N'Set timeout';
			SET LOCK_TIMEOUT 50;

			SET @errorloc = N'Define latch cursor';
			DECLARE resolvelatchtags CURSOR LOCAL FAST_FORWARD FOR 
			SELECT DISTINCT resource_dbid, context_database_id, wait_special_number, 
				resource_associatedobjid, wait_special_tag, resolved_dbname
			FROM #tasks_and_waits taw
			WHERE taw.wait_special_number > 0
			--don't resolve tempdb pages
			AND taw.resource_dbid <> 2
			--Note that if the page id is a system bitmap page, decoding is not useful
			AND NOT (taw.resource_associatedobjid % 8088 = 0 OR taw.resource_associatedobjid = 1)	--PFS
			AND NOT ( (taw.resource_associatedobjid-1) % 511232 = 0 OR taw.resource_associatedobjid = 3) --SGAM
			AND NOT (taw.resource_associatedobjid % 511232 = 0 OR taw.resource_associatedobjid = 2) --GAM
			AND NOT ( (taw.resource_associatedobjid-6) % 511232 = 0 OR taw.resource_associatedobjid = 6) --DCM
			AND NOT ( (taw.resource_associatedobjid-7) % 511232 = 0 OR taw.resource_associatedobjid = 7) --ML
			ORDER BY resource_dbid, wait_special_number, resource_associatedobjid
			;

			SET @errorloc = N'Open latch cursor';
			OPEN resolvelatchtags;
			FETCH resolvelatchtags INTO @lv__curloopdbid, @lv__curcontextdbid, @lv__curfileid, @lv__curpageid, @lv__wait_special_tag, @lv__curDBName;

			SET @errorloc = N'PageLatch loop';
			WHILE @@FETCH_STATUS = 0
			BEGIN
				SET @lv__ResolutionName = NULL; 

				IF @lv__curDBName IS NULL		--I've seen this recently; if DBID doesn't have a match in catalog, we definitely
				BEGIN							-- can't resolve it to an object
					SET @lv__ResolutionName = --we add the DBname only if it is different than the SPID's context DB
							CASE WHEN @lv__curloopdbid <> @lv__curcontextdbid 
								THEN CONVERT(nvarchar(20),@lv__curloopdbid) + N':'
								ELSE N'' END + CONVERT(nvarchar(20),@lv__curfileid)
							;
				END
				ELSE
				BEGIN
					TRUNCATE TABLE #t__dbccpage;
					SET @scratch__int = 0;

					BEGIN TRY
						INSERT INTO #t__dbccpage (ParentObject, Objectcol, Fieldcol, Valuecol)
							EXEC sp_executesql @lv__SmallDynSQL, N'@dbid SMALLINT, @fileid SMALLINT, @pageID BIGINT', 
									@lv__curloopdbid, @lv__curfileid, @lv__curpageid;

						SET @scratch__int = @@ROWCOUNT;
					END TRY
					BEGIN CATCH	
							--no action needed, just leave the taw data alone, as it already has dbid:fileid:pageid info (in both string and atomic form)
							-- we do make a note of the failure, as it may affect how we move the sliding window forward
						SET @scratch__int = 0;
						SET @lv__ResolutionsFailed = @lv__ResolutionsFailed + 1;
					END CATCH

					IF @scratch__int > 0
					BEGIN	--we resolved the page. Now, obtain the IDs and, if possible, resolve to objects.
						SET @lv__ObtainedObjID = NULL; 
						SET @lv__ObtainedIdxID = NULL; 
						SET @lv__ResolutionName = NULL;
						SET @lv__ObtainedObjName = NULL;
						SET @lv__ObtainedSchemaName = NULL;

						SELECT @lv__ObtainedObjID = (
							SELECT TOP 1 t.Valuecol
							FROM #t__dbccpage t
							WHERE t.Fieldcol = 'Metadata: ObjectId'
							AND t.Valuecol IS NOT NULL 
						);

						SELECT @lv__ObtainedIdxID = (
							SELECT TOP 1 t.Valuecol
							FROM #t__dbccpage t
							WHERE t.Fieldcol = 'Metadata: IndexId'
							AND t.Valuecol IS NOT NULL 
						);

						IF @lv__ObtainedObjID IS NOT NULL
						BEGIN
							--As long as we got an object ID, we consider the resolution successful. If our OBJECT_*_NAME calls fail
							-- (e.g. b/c of lock timeouts) then the user will have to rely on the Obj/Idx IDs that were obtained
							--Note that we separate the effort to get Object Name from Schema Name, so that if Object Name works but
							-- then Schema Name gets a timeout, we don't set both to NULL.
							BEGIN TRY
								SET @lv__ObtainedObjName = OBJECT_NAME(@lv__ObtainedObjID, @lv__curloopdbid);
							END TRY
							BEGIN CATCH
								SET @lv__ObtainedObjName = NULL;
							END CATCH

							BEGIN TRY
								SET @lv__ObtainedSchemaName = OBJECT_SCHEMA_NAME(@lv__ObtainedObjID, @lv__curloopdbid);
							END TRY
							BEGIN CATCH
								SET @lv__ObtainedSchemaName = NULL;
							END CATCH

							SET @lv__ResolutionName = --we add the DBname only if it is different than the SPID's context DB
									CASE WHEN @lv__curloopdbid <> @lv__curcontextdbid AND @lv__curDBName IS NOT NULL THEN @lv__curDBName + N'.' ELSE N'' END + 
									ISNULL(@lv__ObtainedSchemaName,N'') + N'.' + 
									ISNULL(@lv__ObtainedObjName, N'(ObjId:' +  CONVERT(nvarchar(20),@lv__ObtainedObjID) + N')') +
									N' (Ix:' + ISNULL(CONVERT(nvarchar(20), @lv__ObtainedIdxID),N'?') + N')'
								;
						END		--IF @lv__ObtainedObjID IS NOT NULL
						ELSE
						BEGIN
							SET @lv__ResolutionsFailed = @lv__ResolutionsFailed + 1;
						END		--IF @lv__ObtainedObjID IS NOT NULL
					END		--IF @scratch__int > 0
				END	--IF @lv__curDBName IS NULL

				--remember that if we have multiple waits on the same DBID/FileID/PageID combo, this UPDATE will update multiple rows for
				-- one iteration of our loop.
				SET @errorloc = N'Latch loop: update #taw';
				UPDATE taw 
				SET --If we DID resolve the name, we want to store the ObjId and IxId (in case we need to troubleshoot later)
					--But the intent is for display code to use resolved_name
					wait_special_tag = CASE WHEN @lv__ObtainedObjID IS NOT NULL 
										THEN 'ObjId:' + ISNULL(CONVERT(nvarchar(20),@lv__ObtainedObjID),N'?') + ', IxId:' + 
												ISNULL(CONVERT(nvarchar(20),@lv__ObtainedIdxID),N'?')
										ELSE taw.wait_special_tag 
										END,
					resolved_name = @lv__ResolutionName,
					resolution_successful = CONVERT(BIT,1)
				FROM #tasks_and_waits taw
				WHERE taw.resource_dbid = @lv__curloopdbid
				AND taw.wait_special_number = @lv__curfileid
				AND taw.resource_associatedobjid = @lv__curpageid
				;

				FETCH resolvelatchtags INTO @lv__curloopdbid, @lv__curcontextdbid, @lv__curfileid, @lv__curpageid, @lv__wait_special_tag, @lv__curDBName;
			END		--WHILE @@FETCH_STATUS = 0

			SET @errorloc = N'Close latch cursor';
			CLOSE resolvelatchtags;
			DEALLOCATE resolvelatchtags;

			SET @errorloc = N'Reset lock_timeout';
			SET LOCK_TIMEOUT -1;

			SET @errorloc = N'Pgl FinUpd';
			UPDATE taw 
			SET resolved_name = tawtemp.resolved_name,
				resolution_successful = CONVERT(BIT,1), 
				wait_special_tag = tawtemp.wait_special_tag
			FROM (
				SELECT 
					SPIDCaptureTime,
					task_address,
					session_id,
					request_id,
					exec_context_id,
					blocking_session_id,
					blocking_exec_context_id,
					wait_special_tag,
					resolution_successful,
					resolved_name =		CASE WHEN resolved_name IS NOT NULL THEN resolved_name
										ELSE (	--haven't resolved it for some reason. If due to tempdb or bitmaps, create a resolution label
											CASE WHEN resource_dbid = 2 THEN N'tempdb' 
												ELSE (CASE WHEN resource_dbid <> context_database_id
															THEN ISNULL(resolved_dbname, CONVERT(nvarchar(20),resource_dbid)) ELSE N'' END)
												END + N':' + ISNULL(CONVERT(NVARCHAR(20),NULLIF(wait_special_number,-929)),N'?') +

											CASE WHEN (resource_associatedobjid % 8088 = 0 OR resource_associatedobjid = 1)		THEN N':PFS'
												WHEN ( (resource_associatedobjid-1) % 511232 = 0 OR resource_associatedobjid = 3) THEN N':SGAM'
												WHEN (resource_associatedobjid % 511232 = 0 OR resource_associatedobjid = 2)	THEN N':GAM'
												WHEN ( (resource_associatedobjid-6) % 511232 = 0 OR resource_associatedobjid = 6) THEN N':DCM'
												WHEN ( (resource_associatedobjid-7) % 511232 = 0 OR resource_associatedobjid = 7) THEN N':ML'
											ELSE N'' END
										)
										END
				FROM #tasks_and_waits tawtemp
				WHERE wait_special_number IS NOT NULL
				AND (resolution_successful = CONVERT(BIT,1) 
						OR resource_dbid = 2
						OR (resource_associatedobjid % 8088 = 0 OR resource_associatedobjid = 1)	--PFS
						OR ( (resource_associatedobjid-1) % 511232 = 0 OR resource_associatedobjid = 3) --SGAM
						OR (resource_associatedobjid % 511232 = 0 OR resource_associatedobjid = 2) --GAM
						OR ( (resource_associatedobjid-6) % 511232 = 0 OR resource_associatedobjid = 6) --DCM
						OR ( (resource_associatedobjid-7) % 511232 = 0 OR resource_associatedobjid = 7) --ML
					)
				) tawtemp
				INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
					ON tawtemp.SPIDCaptureTime = taw.SPIDCaptureTime
					AND tawtemp.task_address = taw.task_address
					AND tawtemp.session_id = taw.session_id
					AND tawtemp.request_id = taw.request_id
					AND tawtemp.exec_context_id = taw.exec_context_id
					AND tawtemp.blocking_session_id = taw.blocking_session_id
					AND tawtemp.blocking_exec_context_id = taw.blocking_exec_context_id
			WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLatchResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
			AND taw.wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked)
			;

			BEGIN TRY
				DBCC TRACEOFF(3604) WITH NO_INFOMSGS;
			END TRY
			BEGIN CATCH
				SET @errormsg = N'PageLatch Resolution was requested but cannot disable TF 3604. Message: ' + ERROR_MESSAGE();
	
				INSERT INTO AutoWho.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
				SELECT SYSDATETIME(), -41, N'TF3604Disable', @errormsg;
			END CATCH

			SET @lv__DurationEnd = SYSDATETIME(); 

			INSERT INTO AutoWho.Log 
			(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), NULL, 0, 'ResolvePgldur', N'PageLatch resolve logic processed ' + CONVERT(nvarchar(20),@InData_NumPageLatch) + 
				N' rows in ' + CONVERT(nvarchar(20),DATEDIFF(millisecond, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';
		END	--IF @lv__3604EnableSuccessful = N'Y'
	END		--IF IS_SRVROLEMEMBER ('sysadmin') = 1 AND @opt__ResolvePageLatches = N'Y' AND ISNULL(@InData_NumPageLatch,0) > 0

	IF @lv__ResolutionsFailed = 0
	BEGIN
		UPDATE targ 
		SET LastProcessedTime = @lv__CurrentExecTime
		FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
		WHERE targ.Label = N'AutoWhoLastLatchResolve'
		;
	END
	ELSE
	BEGIN
		--if we encountered resolution failures, we only move the time forward if it is > 45 min ago.
		-- Since by default the CoreXR master job runs every 15 min, this essentially creates "retry" logic,
		-- allowing things to age to ~1 hour before we stop retrying
		IF @lv__AutoWhoLastLatchResolve < DATEADD(minute, -45, @lv__CurrentExecTime)
		BEGIN
			UPDATE targ 
			SET LastProcessedTime = DATEADD(minute, -45, @lv__CurrentExecTime)
			FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
			WHERE targ.Label = N'AutoWhoLastLatchResolve'
			;
		END
	END

	SET @lv__ResolutionsFailed = 0;

	IF @opt__ResolveLockWaits = N'Y' AND ISNULL(@InData_NumLocks,0) > 0
	BEGIN
		SET @lv__DurationStart = SYSDATETIME(); 

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
					ResolvedDBName = CASE WHEN d.name IS NULL THEN ISNULL(CONVERT(nvarchar(20), NULLIF(resource_dbid,-929)),N'?') ELSE d.name END,
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
				WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
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

			SET @lv__DurationEnd = SYSDATETIME();

			INSERT INTO AutoWho.Log 
			(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), NULL, 0, 'ResolvePat01', N'Lock resolution (Pattern 0 and 1) processed ' + 
						CONVERT(NVARCHAR(20),
						(ISNULL(@InData_NumDB,0) + ISNULL(@InData_NumFile,0) + ISNULL(@InData_NumExtent,0) + ISNULL(@InData_NumApp,0) + ISNULL(@InData_NumMeta,0))
						) + 
				N' rows in ' + CONVERT(nvarchar(20),DATEDIFF(millisecond, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			SET @lv__DurationStart = SYSDATETIME();
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
				SPIDCaptureTime,
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
				taw.SPIDCaptureTime,
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
					ON taw.SPIDCaptureTime = sar.SPIDCaptureTime
					AND taw.session_id = sar.session_id
					AND taw.request_id = sar.request_id
				LEFT OUTER JOIN sys.databases d
						ON taw.resource_dbid = d.database_id
				WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
				AND sar.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
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
					ON tawtemp.SPIDCaptureTime = taw.SPIDCaptureTime
					AND tawtemp.task_address = taw.task_address
					AND tawtemp.session_id = taw.session_id
					AND tawtemp.request_id = taw.request_id
					AND tawtemp.exec_context_id = taw.exec_context_id
					AND tawtemp.blocking_session_id = taw.blocking_session_id
					AND tawtemp.blocking_exec_context_id = taw.blocking_exec_context_id
			WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
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
			)
			;

			SET @lv__DurationEnd = SYSDATETIME();

			INSERT INTO AutoWho.Log 
			(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), NULL, 0, 'ResolvePat2', N'Lock resolution (Pattern 2) processed ' + 
						CONVERT(NVARCHAR(20),
						(ISNULL(@InData_NumKey,0) + ISNULL(@InData_NumRid,0) + ISNULL(@InData_NumPage,0) + ISNULL(@InData_NumHobt,0) + ISNULL(@InData_NumAlloc,0))
						) + 
				N' rows in ' + CONVERT(nvarchar(20),DATEDIFF(millisecond, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			SET @lv__DurationStart = SYSDATETIME();
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
				SPIDCaptureTime,
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
				taw.SPIDCaptureTime, 
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
					ON taw.SPIDCaptureTime = sar.SPIDCaptureTime
					AND taw.session_id = sar.session_id
					AND taw.request_id = sar.request_id
				LEFT OUTER JOIN sys.databases d
					ON taw.resource_dbid = d.database_id
			WHERE taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
			AND sar.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
			AND taw.wait_special_category = @enum__waitspecial__lck
			AND taw.wait_special_number = 4		--obj lock
			AND taw.resource_dbid > 0
			AND taw.resource_associatedobjid > 0
			;

			IF @lv__IndexCreated = 0
			BEGIN
				SET @errorloc = N'CLIDX';
				CREATE CLUSTERED INDEX CL1 ON #tasks_and_waits (resource_dbid, resource_associatedobjid);
				SET @lv__IndexCreated = 1;
			END

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
							THEN ISNULL(@lv__curDBName,ISNULL(CONVERT(nvarchar(20), NULLIF(@lv__curloopdbid,-929)),N'?')) + N'.'
							ELSE N'' END + 
							ISNULL(@lv__ObtainedSchemaName,N'') + N'.' + 
							ISNULL(@lv__ObtainedObjName,N'(ObjId:' +  CONVERT(nvarchar(20),@lv__ObtainedObjID) + N')')
					;

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
					ON tawtemp.SPIDCaptureTime = taw.SPIDCaptureTime
					AND tawtemp.task_address = taw.task_address
					AND tawtemp.session_id = taw.session_id
					AND tawtemp.request_id = taw.request_id
					AND tawtemp.exec_context_id = taw.exec_context_id
					AND tawtemp.blocking_session_id = taw.blocking_session_id
					AND tawtemp.blocking_exec_context_id = taw.blocking_exec_context_id
			WHERE tawtemp.resolution_successful = CONVERT(BIT,1)
			AND taw.SPIDCaptureTime BETWEEN CONVERT(DATETIME,@lv__AutoWhoLastLockResolve) AND CONVERT(DATETIME,@lv__CurrentExecTime)
			AND taw.wait_special_category = @enum__waitspecial__lck;

			SET @lv__DurationEnd = SYSDATETIME();

			INSERT INTO AutoWho.Log 
			(LogDT, TraceID, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), NULL, 0, 'ResolvePat3', N'Lock resolution (Pattern 3) processed ' + 
						CONVERT(NVARCHAR(20),
						ISNULL(@InData_NumObj,0) ) + 
				N' rows in ' + CONVERT(nvarchar(20),DATEDIFF(millisecond, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			SET @lv__DurationStart = SYSDATETIME();
		END		--IF ISNULL(@InData_NumObj,0) > 0
	END		--IF @opt__ResolveLockWaits = N'Y'


	IF @lv__ResolutionsFailed = 0
	BEGIN
		UPDATE targ 
		SET LastProcessedTime = @lv__CurrentExecTime
		FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
		WHERE targ.Label = N'AutoWhoLastLockResolve'
		;
	END
	ELSE
	BEGIN
		--if we encountered resolution failures, we only move the time forward if it is > 45 min ago.
		-- Since by default the CoreXR master job runs every 15 min, this essentially creates "retry" logic,
		-- allowing things to age to 45 min before we stop retrying
		IF @lv__AutoWhoLastLatchResolve < DATEADD(minute, -45, @lv__CurrentExecTime)
		BEGIN
			UPDATE targ 
			SET LastProcessedTime = DATEADD(minute, -45, @lv__CurrentExecTime)
			FROM CoreXR.ProcessingTimes targ WITH (FORCESEEK)
			WHERE targ.Label = N'AutoWhoLastLockResolve'
			;
		END
	END

	RETURN 0;

END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
		N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
		N' Message: ' + ERROR_MESSAGE();
		;
	
	INSERT INTO AutoWho.[Log]
	(LogDT, ErrorCode, LocationTag, LogMessage)
	SELECT SYSDATETIME(), -41, N'ResolveExcept', @errormsg;

	--besides the log message, swallow these errors
	RETURN 0;
END CATCH

	RETURN 0;
END
GO
