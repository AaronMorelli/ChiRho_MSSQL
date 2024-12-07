SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_ResolvePageLatches
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

	FILE NAME: AutoWho_ResolvePageLatches.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ResolvePageLatches

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Takes the raw data from TAW for lock waits and attempts to parse out the various identifiers
		to get more human-readable information about the resources involved.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_ResolvePageLatches @CollectionInitiatorID = 255, @FirstCaptureTimeUTC='2017-07-24 04:00', @LastCaptureTimeUTC='2017-07-24 06:00'
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
		@EffectiveLastCaptureTimeUTC		DATETIME,
		@EffectiveFirstCaptureTime			DATETIME,
		@EffectiveLastCaptureTime			DATETIME;

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
		@lv__curfileid			SMALLINT,
		@lv__curpageid			BIGINT,
		@lv__ObtainedObjID		INT,
		@lv__ObtainedIdxID		INT,
		@lv__ObtainedObjName	NVARCHAR(128),
		@lv__ObtainedSchemaName	 NVARCHAR(128),
		@lv__ResolutionName		NVARCHAR(256),
		@lv__3604EnableSuccessful NCHAR(1)=N'N',
		@lv__ResolutionsFailed	INT=0,
		@scratch__int			INT,
		@lv__wait_special_tag	NVARCHAR(100);

	DECLARE @InData_NumRows INT, 
			@InData_NumPageLatch INT;

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

	IF OBJECT_ID('tempdb..#LatchWaitProcessCaptureTimes') IS NOT NULL DROP TABLE #LatchWaitProcessCaptureTimes;
	CREATE TABLE #LatchWaitProcessCaptureTimes (
		UTCCaptureTime DATETIME NOT NULL,
		SPIDCaptureTime DATETIME NOT NULL
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #LatchWaitProcessCaptureTimes(UTCCaptureTime);

	INSERT INTO #LatchWaitProcessCaptureTimes (
		UTCCaptureTime,
		SPIDCaptureTime
	)
	SELECT 
		ct.UTCCaptureTime,
		ct.SPIDCaptureTime
	FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
	WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
	AND ct.UTCCaptureTime >= @FirstCaptureTimeUTC
	AND ct.UTCCaptureTime <= @LastCaptureTimeUTC
	AND ct.PostProcessed_Latch = 0;

	SET @rc = ROWCOUNT_BIG();

	IF @rc = 0
	BEGIN
		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'No Unprocessed LatchWaits', @Message='No unprocessed LatchWait rows to process';
		RETURN 0;
	END

	SELECT 
		@EffectiveFirstCaptureTimeUTC = ss.UTCCaptureTime,
		@EffectiveFirstCaptureTime = ss.SPIDCaptureTime
	FROM (
		SELECT TOP 1 
			t.UTCCaptureTime,
			t.SPIDCaptureTime
		FROM #LatchWaitProcessCaptureTimes t
		ORDER BY t.UTCCaptureTime ASC
	) ss;

	SELECT 
		@EffectiveLastCaptureTimeUTC = ss.UTCCaptureTime,
		@EffectiveLastCaptureTime = ss.SPIDCaptureTime
	FROM (
		SELECT TOP 1 
			t.UTCCaptureTime,
			t.SPIDCaptureTime
		FROM #LatchWaitProcessCaptureTimes t
		ORDER BY t.UTCCaptureTime DESC
	) ss;


	SET @errorloc = N'GatherProfile';
	SET @InData_NumRows = NULL; 
	SELECT 
		@InData_NumRows = NumRows, 
		@InData_NumPageLatch = NumPageLatch
	FROM (
		SELECT 
			NumRows = SUM(1), 
			NumPageLatch = SUM(CASE WHEN taw.wait_special_category IN (@enum__waitspecial__pgblocked, @enum__waitspecial__pgio, @enum__waitspecial__pg)
								THEN 1 ELSE 0 END)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC

		--We do NOT include this clause b/c we want to have a sense of how many TAW records are in the time range, and also because
		-- the node/status resolution always reviews all TAW records in the time range.
		--AND taw.resolution_successful = CONVERT(bit,0)
	) ss;

	IF ISNULL(@InData_NumPageLatch,0) = 0
	BEGIN
		--No page latch waits in this period. Mark the capture times as processed and exit
		UPDATE targ 
		SET PostProcessed_Latch = 255
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
			INNER JOIN #LatchWaitProcessCaptureTimes t
				ON targ.UTCCaptureTime = t.UTCCaptureTime
		WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
		AND targ.UTCCaptureTime >= @EffectiveFirstCaptureTimeUTC
		AND targ.UTCCaptureTime <= @EffectiveLastCaptureTimeUTC;

		IF @CollectionInitiatorID = 255
		BEGIN
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'No LatchWaits found', @Message='No page latch waits found in this period. Exiting...';
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

	CREATE TABLE #t__dbccpage (
		[ParentObject]				[varchar](100)		NULL,		--can't guarantee that DBCC PAGE will always return non-null values, so cols allow nulls
		[Objectcol]					[varchar](100)		NULL,
		[Fieldcol]					[varchar](100)		NULL,
		[Valuecol]					[varchar](100)		NULL
	);


	BEGIN TRY
		DBCC TRACEON(3604) WITH NO_INFOMSGS;
		SET @lv__3604EnableSuccessful = N'Y';
	END TRY
	BEGIN CATCH
		SET @errormsg = N'PageLatch Resolution was requested but cannot enable TF 3604. Message: ' + ERROR_MESSAGE();
		SET @lv__ResolutionsFailed = @lv__ResolutionsFailed + 1;
	
		IF @CollectionInitiatorID = 255
		BEGIN
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'TF3604Enable', @Message=@errormsg;
		END
	END CATCH

	IF @lv__3604EnableSuccessful = N'Y'
	BEGIN
		SET @lv__DurationStart = SYSUTCDATETIME(); 
		SET @lv__SmallDynSQL = N'DBCC PAGE(@dbid, @fileid, @pageid) WITH TABLERESULTS';

		SET @errorloc = N'Pgl #taw';
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
			wait_special_number,
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
			ISNULL(sar.sess__database_id,-777),
			taw.resource_associatedobjid,
			taw.wait_special_number,
			d.name,
			CONVERT(BIT,0)
		FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw WITH (NOLOCK)
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK)
				ON taw.UTCCaptureTime = sar.UTCCaptureTime
				AND taw.session_id = sar.session_id
				AND taw.request_id = sar.request_id
			INNER JOIN #LatchWaitProcessCaptureTimes t
				ON sar.UTCCaptureTime = t.UTCCaptureTime
			LEFT OUTER JOIN sys.databases d
				ON taw.resource_dbid = d.database_id
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND sar.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND sar.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
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
		ORDER BY resource_dbid, wait_special_number, resource_associatedobjid;

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
							THEN CONVERT(NVARCHAR(20),@lv__curloopdbid) + N':'
							ELSE N'' END + CONVERT(NVARCHAR(20),@lv__curfileid);
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
								ISNULL(@lv__ObtainedObjName, N'(ObjId:' +  CONVERT(NVARCHAR(20),@lv__ObtainedObjID) + N')') +
								N' (Ix:' + ISNULL(CONVERT(NVARCHAR(20), @lv__ObtainedIdxID),N'?') + N')'
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
									THEN 'ObjId:' + ISNULL(CONVERT(NVARCHAR(20),@lv__ObtainedObjID),N'?') + ', IxId:' + 
											ISNULL(CONVERT(NVARCHAR(20),@lv__ObtainedIdxID),N'?')
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

		--Now, apply our work
		BEGIN TRANSACTION;

		SET @errorloc = N'Pgl FinUpd';
		UPDATE taw 
		SET resolved_name = tawtemp.resolved_name,
			resolution_successful = CONVERT(BIT,1), 
			wait_special_tag = tawtemp.wait_special_tag
		FROM (
			SELECT 
				UTCCaptureTime,
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
														THEN ISNULL(resolved_dbname, CONVERT(NVARCHAR(20),resource_dbid)) ELSE N'' END)
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
				ON tawtemp.UTCCaptureTime = taw.UTCCaptureTime
				AND tawtemp.task_address = taw.task_address
				AND tawtemp.session_id = taw.session_id
				AND tawtemp.request_id = taw.request_id
				AND tawtemp.exec_context_id = taw.exec_context_id
				AND tawtemp.blocking_session_id = taw.blocking_session_id
				AND tawtemp.blocking_exec_context_id = taw.blocking_exec_context_id
		WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
		AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
		AND taw.wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked);

		BEGIN TRY
			DBCC TRACEOFF(3604) WITH NO_INFOMSGS;
		END TRY
		BEGIN CATCH
			SET @errormsg = N'PageLatch Resolution cannot disable TF 3604. Message: ' + ERROR_MESSAGE();
	
			IF @CollectionInitiatorID = 255
			BEGIN
				EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='TF3604Disable', @Message=@errormsg;
			END
		END CATCH

		SET @lv__DurationEnd = SYSUTCDATETIME(); 

		IF @CollectionInitiatorID = 255
		BEGIN
			SET @errormsg = N'PageLatch resolve logic processed ' + CONVERT(NVARCHAR(20),@InData_NumPageLatch) + 
				N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='ResolvePgldur', @Message=@errormsg;
		END
	END	--IF @lv__3604EnableSuccessful = N'Y'


	UPDATE targ 
	SET PostProcessed_Latch = 255
	FROM #LatchWaitProcessCaptureTimes t
		INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
			ON t.UTCCaptureTime = targ.UTCCaptureTime
	WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
	AND targ.UTCCaptureTime >= @EffectiveFirstCaptureTimeUTC
	AND targ.UTCCaptureTime <= @EffectiveLastCaptureTimeUTC;

	COMMIT TRANSACTION;

	IF @CollectionInitiatorID = 255		--we only log durations for the background trace
	BEGIN
		SET @errormsg = N'LatchWait resolve logic applied latch resource info for ' + CONVERT(NVARCHAR(20),@rc) + 
			N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'ResolveLtchWdur', @Message=@errormsg;
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