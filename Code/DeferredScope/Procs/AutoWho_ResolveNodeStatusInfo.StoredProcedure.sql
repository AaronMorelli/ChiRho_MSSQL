SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_ResolveNodeStatusInfo
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

	FILE NAME: AutoWho_ResolveNodeStatusInfo.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ResolveNodeStatusInfo

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Updates 2 fields in SAR that 
		1) summarize the NUMA Node(s) used by each running request (mainly useful for parallel queries)
		2) summarize the task statuses for a request (mainly useful for parallel queries)

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_ResolveNodeStatusInfo @CollectionInitiatorID = 255, @FirstCaptureTimeUTC='2017-07-24 04:00', @LastCaptureTimeUTC='2017-07-24 06:00'
*/
(
	@CollectionInitiatorID	TINYINT,
	@FirstCaptureTimeUTC	DATETIME,	--This proc ASSUMES that these are valid UTC capture times in @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes
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
		@errorloc					NVARCHAR(50),
		@errormsg					NVARCHAR(4000),
		@errorsev					INT,
		@errorstate					INT,
		@rc							INT,
		@cxpacketwaitid				SMALLINT,
		@lv__DurationStart			DATETIME2(7),
		@lv__DurationEnd			DATETIME2(7);

	SET @lv__DurationStart = SYSUTCDATETIME();

	
BEGIN TRY

	IF OBJECT_ID('tempdb..#NodeStatusProcessCaptureTimes') IS NOT NULL DROP TABLE #NodeStatusProcessCaptureTimes;
	CREATE TABLE #NodeStatusProcessCaptureTimes (
		UTCCaptureTime DATETIME NOT NULL
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #NodeStatusProcessCaptureTimes(UTCCaptureTime);

	INSERT INTO #NodeStatusProcessCaptureTimes (
		UTCCaptureTime
	)
	SELECT 
		ct.UTCCaptureTime
	FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
	WHERE ct.CollectionInitiatorID = @CollectionInitiatorID
	AND ct.UTCCaptureTime >= @FirstCaptureTimeUTC
	AND ct.UTCCaptureTime <= @LastCaptureTimeUTC
	AND ct.PostProcessed_NodeStatus = 0;

	SET @rc = ROWCOUNT_BIG();

	IF @rc = 0
	BEGIN
		IF @CollectionInitiatorID = 255
		BEGIN
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'No Unprocessed NodeStatus', @Message='No unprocessed NodeStatus rows to process';
		END
		RETURN 0;
	END

	BEGIN TRANSACTION;

	SELECT 
		@EffectiveFirstCaptureTimeUTC = ss.UTCCaptureTime
	FROM (
		SELECT TOP 1 
			t.UTCCaptureTime
		FROM #NodeStatusProcessCaptureTimes t
		ORDER BY t.UTCCaptureTime ASC
	) ss;

	SELECT 
		@EffectiveLastCaptureTimeUTC = ss.UTCCaptureTime
	FROM (
		SELECT TOP 1 
			t.UTCCaptureTime
		FROM #NodeStatusProcessCaptureTimes t
		ORDER BY t.UTCCaptureTime DESC
	) ss;

	--This table holds partially-aggregated data for our node/status aggregation logic
	CREATE TABLE #TaskResolve1 (
		UTCCaptureTime				DATETIME NOT NULL,
		session_id					SMALLINT NOT NULL, 
		request_id					SMALLINT NOT NULL, 
		tstate						NVARCHAR(5) NOT NULL,
		parent_node_id				INT NOT NULL, 
		NumTasks					SMALLINT NOT NULL
	);

	CREATE TABLE #TaskResolve2 (
		Rnk							INT NOT NULL, 
		UTCCaptureTime				DATETIME NOT NULL,
		session_id					SMALLINT NOT NULL,
		request_id					SMALLINT NOT NULL, 
		NodeData					NVARCHAR(256) NULL,
		StatusData					NVARCHAR(256) NULL
	);

	SELECT @cxpacketwaitid = dwt.DimWaitTypeID
	FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
	WHERE dwt.wait_type = N'CXPACKET';


	SET @errorloc = N'Insert into #TR1';
	INSERT INTO #TaskResolve1 (
		UTCCaptureTime,
		session_id,
		request_id,
		tstate,
		parent_node_id,
		NumTasks
	)
	SELECT 
		UTCCaptureTime,
		session_id,
		request_id,
		tstate,
		ISNULL(parent_node_id,999),
		NumTasks
	FROM (
		SELECT 
			UTCCaptureTime, 
			session_id,
			request_id,
			tstate,
			parent_node_id, 
			NumTasks = COUNT(*)
		FROM (
			SELECT 
				UTCCaptureTime,
				session_id,
				request_id,
				task_address,
				tstate,
				scheduler_id
			FROM (
				SELECT 
					taw.UTCCaptureTime, 
					taw.session_id, 
					taw.request_id, 
					taw.task_address, 
					tstate = CASE WHEN taw.FKDimWaitType = @cxpacketwaitid AND taw.tstate = N'S' THEN N'S(CX)' 
								ELSE taw.tstate END, 
					taw.scheduler_id,
					--because a spid/request/task_address can have multiple entries in this table, 
					-- we use task_priority (which is a ROW_NUMBER partitioned by just session & request)
					-- to decide which row to take for a particular task_address
					rn = ROW_NUMBER() OVER (PARTITION BY taw.UTCCaptureTime, taw.session_id, taw.request_id, 
												taw.task_address ORDER BY taw.task_priority ASC )
				FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
				WHERE taw.CollectionInitiatorID = @CollectionInitiatorID
				AND taw.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
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
		GROUP BY UTCCaptureTime,
			session_id,
			request_id,
			tstate,
			parent_node_id
	) grpbase
	OPTION(RECOMPILE);

	SET @errorloc = N'INSERT into #TR2';
	INSERT INTO #TaskResolve2 (
		Rnk,
		UTCCaptureTime,
		session_id,
		request_id
	)
	SELECT 
		--since I'm using the XML method to do group concatenation, and I don't want to mess
		-- with conversions to/from datetime values, we grab a rank # for each distinct
		-- unique request
		Rnk = ROW_NUMBER() OVER (ORDER BY UTCCaptureTime, session_id, request_id),
		UTCCaptureTime,
		session_id,
		request_id
	FROM (
		SELECT DISTINCT
			UTCCaptureTime,
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
						nodeformatted = CONVERT(NVARCHAR(20),NumTasks) + N'['+CONVERT(NVARCHAR(20),parent_node_id)+N']'
					FROM (
						

						SELECT 
							n2.Rnk,
							n1.parent_node_id,
							n1.NumTasks,
							rn = ROW_NUMBER() OVER (PARTITION BY n2.Rnk ORDER BY n1.parent_node_id)
						FROM (
							SELECT 
								UTCCaptureTime,
								session_id,
								request_id,
								parent_node_id,
								NumTasks = SUM(NumTasks)
							FROM #TaskResolve1
							GROUP BY UTCCaptureTime, session_id, request_id, parent_node_id
							) n1
							INNER JOIN #TaskResolve2 n2
								ON n1.UTCCaptureTime = n2.UTCCaptureTime
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
			ON t0.Rnk = targ.Rnk;


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
								UTCCaptureTime,
								session_id,
								request_id,
								tstate,
								NumTasks = SUM(NumTasks)
							FROM #TaskResolve1
							GROUP BY UTCCaptureTime, session_id, request_id, tstate 
							) n1
							INNER JOIN #TaskResolve2 n2
								ON n1.UTCCaptureTime = n2.UTCCaptureTime
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
	SET calc__node_info = SUBSTRING(n.NodeData,1,40),
		calc__status_info = SUBSTRING(n.StatusData,1,40)
	FROM #TaskResolve2 n
		INNER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests targ
			ON n.UTCCaptureTime = targ.UTCCaptureTime
			AND n.session_id = targ.session_id
			AND n.request_id = targ.request_id
	WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
	AND targ.UTCCaptureTime BETWEEN @EffectiveFirstCaptureTimeUTC AND @EffectiveLastCaptureTimeUTC
	OPTION(RECOMPILE, FORCE ORDER);

	SET @rc = ROWCOUNT_BIG();
	SET @lv__DurationEnd = SYSUTCDATETIME();

	UPDATE targ 
	SET PostProcessed_NodeStatus = 255
	FROM #NodeStatusProcessCaptureTimes t
		INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes targ
			ON t.UTCCaptureTime = targ.UTCCaptureTime
	WHERE targ.CollectionInitiatorID = @CollectionInitiatorID
	AND targ.UTCCaptureTime >= @EffectiveFirstCaptureTimeUTC
	AND targ.UTCCaptureTime <= @EffectiveLastCaptureTimeUTC;

	COMMIT TRANSACTION;

	IF @CollectionInitiatorID = 255		--we only log durations for the background trace
	BEGIN
		SET @errormsg = N'NodeStatus resolve logic applied node and status info for ' + CONVERT(NVARCHAR(20),@rc) + 
			N' rows in ' + CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__DurationStart, @lv__DurationEnd)) + N' milliseconds.';

		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location=N'ResolveNSdur', @Message=@errormsg;
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