	CREATE TABLE #SARRawStats (
		--This is the identifier of a batch
		session_id				SMALLINT NOT NULL,
		request_id				SMALLINT NOT NULL,
		TimeIdentifier			DATETIME NOT NULL,
		SPIDCaptureTime			DATETIME NOT NULL,


		query_hash				BINARY(8) NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		PKSQLStmtStoreID		BIGINT NOT NULL,
		PKQueryPlanStmtStoreID	BIGINT NULL,		--If @plan=N'N', then we leave this NULL so that it is not a differentiator
													--If @plan=N'Y', then we pull it and group by it, so that it IS a differentiator.
													--For now, we are going to allow NULL values and they *WILL* be a differentiator.
													--This annoyingly means we could have 2 rows for the same SQLStmtStoreID value, one for a
													--NULL plan and the other for a valid QPSS ID, but the alternative, if we omitted NULL
													--would be to potentially omit all representative rows/sub-rows if we didn't grab the plan
													--at all (e.g. all under capture threshold).
													--TODO: still need to think through how I'm going to handle this.

		rqst__status_code					TINYINT,
		rqst__open_transaction_count		INT,

		rqst__transaction_isolation_level	TINYINT,

		--We need to delta these values with the previous SPIDCaptureTime
		rqst__cpu_time						INT,
		TempDBAlloc_pages			BIGINT,		
		TempDBUsed_pages			BIGINT,		

		mgrant__request_time		DATETIME,		--can derive a "milliseconds to grant" metric
		mgrant__grant_time			DATETIME,		--with these 2 fields

		mgrant__requested_memory_kb	BIGINT,
		mgrant__used_memory_kb		BIGINT,
		mgrant__dop					SMALLINT,

		calc__duration_ms			BIGINT,
		calc__blocking_session_id	SMALLINT,
		calc__is_blocker			BIT
		--calc__tmr_wait		maybe consider this later
		--calc__node_info		maybe consider this later
		--calc__status_info		maybe consider this later

	);

	

	INSERT INTO #SARRawStats (
		session_id,
		request_id,
		TimeIdentifier,
		SPIDCaptureTime,

		PKSQLStmtStoreID,

		rqst__cpu_time,
		calc__duration_ms
	)
	SELECT 
		sar.session_id,
		sar.request_id,
		sar.TimeIdentifier,
		sar.SPIDCaptureTime,
		sar.FKSQLStmtStoreID,
		sar.rqst__cpu_time,
		sar.calc__duration_ms
	FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
	WHERE sar.CollectionInitiatorID = @init
	AND sar.SPIDCaptureTime BETWEEN @startMinus1 AND @end		--we want the statement stats for the SPID Capture Time that precedes @start. (See above logic for @startMinus1)
	AND sar.sess__is_user_process = 1
	AND sar.calc__threshold_ignore = 0
	AND --Active spid with stmt text. (On occasion active requests can have null stmt text)
			sar.request_id <> @lv__nullsmallint AND sar.FKSQLStmtStoreID IS NOT NULL
	;


	
	INSERT INTO #StmtStats (
		--This is the identifier of a batch
		session_id,
		request_id,
		TimeIdentifier,

		PKSQLStmtStoreID,
		FirstSPIDCaptureTime,
		LastSPIDCaptureTime,
		PreviousSPIDCaptureTime
	)
	SELECT 
		s.session_id,
		s.request_id,
		s.TimeIdentifier,

		s.PKSQLStmtStoreID,
		FirstSPIDCaptureTime = s.SPIDCaptureTime,
		LastSPIDCaptureTime = ISNULL(lastCap.SPIDCaptureTime,s.SPIDCaptureTime),
		s.PrevSPIDCaptureTime
	FROM #StmtCalcIntervals s
		OUTER APPLY (
			--find the next time this spid/request/TimeIdentifier changes statement
			SELECT TOP 1
				FirstCapture = s2.SPIDCaptureTime
			FROM #StmtCalcIntervals s2
			WHERE s2.session_id = s.session_id
			AND s2.request_id = s.request_id
			AND s2.TimeIdentifier = s.TimeIdentifier
			AND s2.StmtIsDifferent = 1
			AND s2.SPIDCaptureTime > s.SPIDCaptureTime
			ORDER BY s2.SPIDCaptureTime ASC
		) nextStmt
		OUTER APPLY (
			--Now, get the max SPIDCaptureTime for this spid/request/TimeIdentifier BEFORE the "next statement"
			SELECT TOP 1 
				s3.SPIDCaptureTime
			FROM #StmtCalcIntervals s3
			WHERE s3.session_id = s.session_id
			AND s3.request_id = s.request_id
			AND s3.TimeIdentifier = s.TimeIdentifier
			AND s3.StmtIsDifferent = 0
			AND s3.SPIDCaptureTime > s.SPIDCaptureTime
			AND s3.SPIDCaptureTime < ISNULL(nextStmt.FirstCapture, CONVERT(DATETIME, '3000-01-01'))
			ORDER BY s3.SPIDCaptureTime DESC
		) lastCap
	WHERE s.StmtIsDifferent = 1;


	UPDATE targ 
	SET calc__duration_ms_delta = l.calc__duration_ms - ISNULL(p.calc__duration_ms,0),
		cpu_time_delta = l.rqst__cpu_time - ISNULL(p.rqst__cpu_time,0)
	FROM #StmtStats targ
		INNER JOIN #SARRawStats l		--last
			ON targ.session_id = l.session_id
			AND targ.request_id = l.request_id
			AND targ.TimeIdentifier = l.TimeIdentifier
			AND targ.LastSPIDCaptureTime = l.SPIDCaptureTime
		LEFT OUTER JOIN #SARRawStats p
			ON targ.session_id = p.session_id
			AND targ.request_id = p.request_id
			AND targ.TimeIdentifier = p.TimeIdentifier
			AND targ.PreviousSPIDCaptureTime = l.SPIDCaptureTime;
	



	/*
		We display "representative rows" aka "sub-rows" in our output for active queries, where the key of the sub-row
		is actually the parent key + several additional identifying fields.
		For query hash data, the high-level key (Lev 1) is query_hash. The Lev 2 key is session_id/request_id/TimeIdentifier.
		However, the sub-rows 
		
		we need to first
		calculate our stats for these sub-rows 
	*/
	CREATE TABLE #QHSubRowStats (
		--identifier fields
		session_id				SMALLINT,
		request_id				SMALLINT,
		TimeIdentifier			DATETIME NOT NULL,

		query_hash				BINARY(8) NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		/* TODO: do these belong in this table? Or in the separate "sub-rows" table?
		FKSQLStmtStoreID			BIGINT NULL,
		FKQueryPlanStmtStoreID		BIGINT NULL,		--TODO: when we are capturing plan info, we need to 
														--handle the case where the QP is null for the first capture, and non-null
														--for further captures.
		*/

		--TODO: Consider adding sess__open_transaction_count at a later time
		--TODO: Consider adding rqst__open_transaction_count at a later time

		rqst__status_code			TINYINT,
		rqst__cpu_time				INT,		--max observed for the key (session_id/request_id/TimeIdentifier)
		rqst__reads					BIGINT,		--max observed
		rqst__writes				BIGINT,		--max observed
		rqst__logical_reads			BIGINT,		--max observed

		TempDBAlloc_pages			BIGINT,		--we store the max observed for the key over any of its SPIDCaptureTimes
		TempDBUsed_pages			BIGINT,		--max observed
		tempdb__CalculatedNumberOfTasks	SMALLINT,	--max observed (usually goes down over time but it CAN increase sometimes,
													-- so we take the max rather than the first observed)

		mgrant__requested_memory_kb	BIGINT,		--max observed
		mgrant__granted_memory_kb	BIGINT,		--max observed
		mgrant__used_memory_kb		BIGINT,		--max observed
		mgrant__dop					BIGINT,		--max observed

		calc__duration_ms			BIGINT,		--max observed
		calc__block_relevant		TINYINT,	--max observed
		calc__is_blocker			TINYINT,	--max observed

		--TODO: potentially add logic based on calc__tmr_wait if we find that useful
		--TODO: potentially add logic based on these fields: calc__node_info, calc__status_info
		--TODO: add in stuff from TAW table
		--TODO: consider adding in stuff from TransactionDetails table
	);

	CREATE TABLE #QH_SARcache (
		query_hash				BINARY(8) NOT NULL,
		SPIDCaptureTime			DATETIME NOT NULL,
		session_id				INT,
		request_id				INT,

		PKSQLStmtStoreID		BIGINT,
		PKQueryPlanStmtStoreID	BIGINT,

		
		
		cpu						BIGINT,
		reads					BIGINT,
		lreads					BIGINT,
		writes					BIGINT,
		tdb_alloc				INT,
		tdb_used				INT,
		mgrant_req				INT,
		mgrant_gr				INT,
		mgrant_used				INT
	);

	CREATE TABLE #QH_SARagg (
		query_hash				BINARY(8) NOT NULL,

		PKSQLStmtStoreID		BIGINT,
		PKQueryPlanStmtStoreID	BIGINT,

		NumRows					INT,

		status_running			INT,
		status_runnable			INT,
		status_suspended		INT,
		status_other			INT,

		duration_sum	BIGINT,
		--duration_min	BIGINT,			since we capture via polling, we could easily capture at 0.0. But that doesn't tell us anything.
		duration_max	BIGINT,
		duration_avg	DECIMAL(21,1),
		--unitless counts:
		duration_0toP5	INT,
		duration_P5to1	INT,
		duration_1to2	INT,
		duration_2to5	INT,
		duration_5to10	INT,
		duration_10to20	INT,
		duration_20plus	INT,

		--request cpu. unit is native (milliseconds)
		cpu_sum			BIGINT,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max			BIGINT,
		cpu_avg			DECIMAL(21,1),

		--reads. unit is native (8k page reads)
		reads_sum		BIGINT,
		reads_max		BIGINT,
		reads_avg		DECIMAL(21,1),

		writes_sum		BIGINT,
		writes_max		BIGINT,
		writes_avg		DECIMAL(21,1),

		lreads_sum		BIGINT,
		lreads_max		BIGINT,
		lreads_avg		DECIMAL(21,1),

		--from dm_exec_query_memory_grants. unit is native (kb)
		mgrant_req_min	INT,
		mgrant_req_max	INT,
		mgrant_req_avg	DECIMAL(21,1),

		mgrant_gr_min	INT,
		mgrant_gr_max	INT,
		mgrant_gr_avg	DECIMAL(21,1),

		mgrant_used_min	INT,
		mgrant_used_max	INT,
		mgrant_used_avg	DECIMAL(21,1),

		DisplayOrderWithinGroup INT
	);

	--object stmt cache
	CREATE TABLE #Stmt_SARcache (
		PKSQLStmtStoreID		BIGINT,
		SPIDCaptureTime			DATETIME NOT NULL,
		session_id				INT,
		request_id				INT,

		PKQueryPlanStmtStoreID	BIGINT,

		rqst__status_code		TINYINT,
		calc__duration_ms		BIGINT,
		tempdb__CalculatedNumberOfTasks	BIGINT,
		cpu						BIGINT,
		reads					BIGINT,
		lreads					BIGINT,
		writes					BIGINT,
		tdb_alloc				INT,
		tdb_used				INT,
		mgrant_req				INT,
		mgrant_gr				INT,
		mgrant_used				INT
	);

	CREATE TABLE #St_SARagg (
		PKSQLStmtStoreID		BIGINT,
		PKQueryPlanStmtStoreID	BIGINT,

		NumRows					INT,

		status_running			INT,
		status_runnable			INT,
		status_suspended		INT,
		status_other			INT,

		duration_sum	BIGINT,
		--duration_min	BIGINT,			since we capture via polling, we could easily capture at 0.0. But that doesn't tell us anything.
		duration_max	BIGINT,
		duration_avg	DECIMAL(21,1),
		--unitless counts:
		duration_0toP5	INT,
		duration_P5to1	INT,
		duration_1to2	INT,
		duration_2to5	INT,
		duration_5to10	INT,
		duration_10to20	INT,
		duration_20plus	INT,

		--request cpu. unit is native (milliseconds)
		cpu_sum			BIGINT,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max			BIGINT,
		cpu_avg			DECIMAL(21,1),

		--reads. unit is native (8k page reads)
		reads_sum		BIGINT,
		reads_max		BIGINT,
		reads_avg		DECIMAL(21,1),

		writes_sum		BIGINT,
		writes_max		BIGINT,
		writes_avg		DECIMAL(21,1),

		lreads_sum		BIGINT,
		lreads_max		BIGINT,
		lreads_avg		DECIMAL(21,1),

		--from dm_exec_query_memory_grants. unit is native (kb)
		mgrant_req_min	INT,
		mgrant_req_max	INT,
		mgrant_req_avg	DECIMAL(21,1),

		mgrant_gr_min	INT,
		mgrant_gr_max	INT,
		mgrant_gr_avg	DECIMAL(21,1),

		mgrant_used_min	INT,
		mgrant_used_max	INT,
		mgrant_used_avg	DECIMAL(21,1),

		DisplayOrderWithinGroup INT
	);
	/*
	CREATE TABLE #ActiveStats (
		PrepID		INT NOT NULL,
			--this surrogate represents both the identifier fields (hash or stmt store id, context DB if requested) and
			-- the query plan (which may just always be NULL if the user did not request the plan)

		--duration fields, unit is our standard "time" formatting
		duration_sum	BIGINT,
		--duration_min	BIGINT,			since we capture via polling, we could easily capture at 0.0. But that doesn't tell us anything.
		duration_max	BIGINT,
		duration_avg	DECIMAL(21,1),
		--unitless counts:
		duration_0toP5	INT,
		duration_P5to1	INT,
		duration_1to2	INT,
		duration_2to5	INT,
		duration_6to10	INT,
		duration_10to20	INT,
		duration_20plus	INT,

		
		--blocking. We measure this by the top-priority wait type if the wait is a lock wait (LCK)
		--unit is our standard "time" formatting
		TimesBlocked	INT,
		blocked_sum		INT,
		--blocked_min		INT,		see above note about polling & capturing at 0.0
		blocked_max		INT,
		blocked_avg		DECIMAL(21,1),
		--unitless counts:
		blocked_0toP5	INT,
		blocked_P5to1	INT,
		blocked_1to2	INT,
		blocked_2to5	INT,
		blocked_6to10	INT,
		blocked_10to20	INT,
		blocked_20plus	INT,

		--request status codes. unitless counts
		numRunning		INT,
		numRunnable		INT,
		numSuspended	INT,
		numOther		INT,		--sleeping, background

		--request cpu. unit is native (milliseconds)
		cpu_sum			BIGINT,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max			BIGINT,
		cpu_avg			DECIMAL(21,1),

		--reads. unit is native (8k page reads)
		reads_sum		BIGINT,
		reads_max		BIGINT,
		reads_avg		DECIMAL(21,1),

		writes_sum		BIGINT,
		writes_max		BIGINT,
		writes_avg		DECIMAL(21,1),

		lreads_sum		BIGINT,
		lreads_max		BIGINT,
		lreads_avg		DECIMAL(21,1),

		--from dm_db_tasks_space_usage. unit is native (8k page allocations)
		tdb_alloc_sum	BIGINT,
		tdb_alloc_max	BIGINT,
		tdb_alloc_avg	DECIMAL(21,1),
		tdb_used_sum	BIGINT,
		tdb_used_max	BIGINT,
		tdb_used_avg	DECIMAL(21,1),

		--from dm_exec_query_memory_grants. unit is native (kb)
		mgrant_req_min	INT,
		mgrant_req_max	INT,
		mgrant_req_avg	DECIMAL(21,1),

		mgrant_gr_min	INT,
		mgrant_gr_max	INT,
		mgrant_gr_avg	DECIMAL(21,1),

		mgrant_used_min	INT,
		mgrant_used_max	INT,
		mgrant_used_avg	DECIMAL(21,1)
	);
	*/
	





	--query hash cache
	
	/*
	INSERT INTO #QH_SARcache (
		query_hash,
		SPIDCaptureTime,
		session_id,
		request_id,

		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		rqst__status_code,
		calc__duration_ms,
		tempdb__CalculatedNumberOfTasks,
		cpu,
		reads,
		lreads,
		writes,
		tdb_alloc,
		tdb_used,
		mgrant_req,
		mgrant_gr,
		mgrant_used
	)
	SELECT 
		sar.rqst__query_hash,
		sar.SPIDCaptureTime,
		sar.session_id,
		sar.request_id,

		sar.FKSQLStmtStoreID,
		sar.FKQueryPlanStmtStoreID,

		sar.rqst__status_code,
		DurationMS = CASE WHEN sar.calc__duration_ms >= tm.diffMS THEN sar.calc__duration_ms - tm.diffMS ELSE sar.calc__duration_ms END,
		sar.tempdb__CalculatedNumberOfTasks,
		sar.rqst__cpu_time,
		sar.rqst__reads,
		sar.rqst__logical_reads,
		sar.rqst__writes,
		-1,
		-1, 
		sar.mgrant__requested_memory_kb,
		sar.mgrant__granted_memory_kb,
		sar.mgrant__used_memory_kb
	FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
		INNER JOIN #QH_Identifiers qh
			ON qh.query_hash = sar.rqst__query_hash
		INNER JOIN #TimeMinus1 tm
			ON sar.SPIDCaptureTime = tm.SPIDCaptureTime
	WHERE sar.CollectionInitiatorID = @init
	AND sar.SPIDCaptureTime BETWEEN @start AND @end 
	AND sar.sess__is_user_process = 1
	AND sar.calc__threshold_ignore = 0
	;

	--TODO: for durations > 15 seconds, need to correct that in my sar cache table.
	-- (And do this for waits also). 
	-- Easiest to grab list of times from @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes (or UserCaptureTimes),
	-- and then self-join to grab the NOW minus 1 match for each time. Then, take
	-- that table and join it to SAR above to provide the value for another SAR join
	-- to get the previous duration. 

	*/

	

	/*
	INSERT INTO #QH_SARagg (
		query_hash, 

		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		NumRows,

		status_running,
		status_runnable,
		status_suspended,
		status_other,

		duration_sum,
		--duration_min,
		duration_max,
		duration_avg,
		--unitless counts:
		duration_0toP5,
		duration_P5to1,
		duration_1to2,
		duration_2to5,
		duration_5to10,
		duration_10to20,
		duration_20plus,

		--request cpu. unit is native (milliseconds)
		cpu_sum,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max,
		cpu_avg,

		--reads. unit is native (8k page reads)
		reads_sum,
		reads_max,
		reads_avg,

		writes_sum,
		writes_max,
		writes_avg,

		lreads_sum,
		lreads_max,
		lreads_avg,

		--from dm_exec_query_memory_grants. unit is native (kb)
		mgrant_req_min,
		mgrant_req_max,
		mgrant_req_avg,

		mgrant_gr_min,
		mgrant_gr_max,
		mgrant_gr_avg,

		mgrant_used_min,
		mgrant_used_max,
		mgrant_used_avg,

		DisplayOrderWithinGroup
	)
	SELECT 
		query_hash, 
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		NumRows = COUNT(*),

		status_running = SUM(CASE WHEN qh.rqst__status_code=1 THEN 1 ELSE 0 END), 
		status_runnable = SUM(CASE WHEN qh.rqst__status_code=2 THEN 1 ELSE 0 END),
		status_suspended = SUM(CASE WHEN qh.rqst__status_code=4 THEN 1 ELSE 0 END),
		status_other = SUM(CASE WHEN qh.rqst__status_code NOT IN (1,2,4) THEN 1 ELSE 0 END),

		duration_sum = SUM(qh.calc__duration_ms),
		duration_max = MAX(qh.calc__duration_ms),
		duration_avg = AVG(qh.calc__duration_ms),
		duration_0toP5 = SUM(CASE WHEN qh.calc__duration_ms >= 0 AND qh.calc__duration_ms < 0.5 THEN 1 ELSE 0 END),
		duration_P5to1 = SUM(CASE WHEN qh.calc__duration_ms >= 0.5 AND qh.calc__duration_ms < 1.0 THEN 1 ELSE 0 END),
		duration_1to2 = SUM(CASE WHEN qh.calc__duration_ms >= 1.0 AND qh.calc__duration_ms < 2.0 THEN 1 ELSE 0 END),
		duration_2to5 = SUM(CASE WHEN qh.calc__duration_ms >= 2.0 AND qh.calc__duration_ms < 5.0 THEN 1 ELSE 0 END),
		duration_5to10 = SUM(CASE WHEN qh.calc__duration_ms >= 5.0 AND qh.calc__duration_ms < 10.0 THEN 1 ELSE 0 END),
		duration_10to20 = SUM(CASE WHEN qh.calc__duration_ms >= 10.0 AND qh.calc__duration_ms < 20.0 THEN 1 ELSE 0 END),
		duration_20plus = SUM(CASE WHEN qh.calc__duration_ms >= 20.0 THEN 1 ELSE 0 END),

		cpu_sum = SUM(qh.cpu),
		cpu_max = MAX(qh.cpu),
		cpu_avg = AVG(qh.cpu),

		reads_sum = SUM(qh.reads),
		reads_max = MAX(qh.reads), 
		reads_avg = AVG(qh.reads),

		writes_sum = SUM(qh.writes),
		writes_max = MAX(qh.writes),
		writes_avg = AVG(qh.writes), 

		lreads_sum = SUM(qh.lreads), 
		lreads_max = MAX(qh.lreads), 
		lreads_avg = AVG(qh.lreads),

		mgrant_req_min = MIN(qh.mgrant_req),
		mgrant_req_max = MAX(qh.mgrant_req),
		mgrant_req_avg = AVG(qh.mgrant_req),

		mgrant_gr_min = MIN(qh.mgrant_gr),
		mgrant_gr_max = MAX(qh.mgrant_gr),
		mgrant_gr_avg = AVG(qh.mgrant_gr),

		mgrant_used_min = MIN(qh.mgrant_used), 
		mgrant_used_max = MAX(qh.mgrant_used), 
		mgrant_used_avg = AVG(qh.mgrant_used),

		[DisplayOrderWithinGroup] = ROW_NUMBER() OVER (PARTITION BY query_hash ORDER BY SUM(qh.calc__duration_ms) DESC)
	FROM #QH_SARcache qh
	GROUP BY query_hash, 
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID
		;


	INSERT INTO #QH_SARagg (
		query_hash, 

		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		NumRows,

		status_running,
		status_runnable,
		status_suspended,
		status_other,

		duration_sum,
		--duration_min,
		duration_max,
		duration_avg,
		--unitless counts:
		duration_0toP5,
		duration_P5to1,
		duration_1to2,
		duration_2to5,
		duration_5to10,
		duration_10to20,
		duration_20plus,

		--request cpu. unit is native (milliseconds)
		cpu_sum,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max,
		cpu_avg,

		--reads. unit is native (8k page reads)
		reads_sum,
		reads_max,
		reads_avg,

		writes_sum,
		writes_max,
		writes_avg,

		lreads_sum,
		lreads_max,
		lreads_avg,

		DisplayOrderWithinGroup
	)
	SELECT 
		query_hash, 
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,
		NumRows, 
		status_running,
		status_runnable,
		status_suspended,
		status_other, 
		duration_sum, 
		duration_max,
		duration_avg = CONVERT(DECIMAL(21,1),(duration_sum*1.) / (NumRows*1.)),
		duration_0toP5,
		duration_P5to1,
		duration_1to2,
		duration_2to5,
		duration_5to10,
		duration_10to20,
		duration_20plus,

		cpu_sum,
		cpu_max,
		cpu_avg = CONVERT(DECIMAL(21,1),(cpu_sum*1.) / (NumRows*1.)),

		reads_sum, 
		reads_max, 
		reads_avg = CONVERT(DECIMAL(21,1),(reads_sum*1.) / (NumRows*1.)),

		writes_sum, 
		writes_max, 
		writes_avg = CONVERT(DECIMAL(21,1),(writes_sum*1.) / (NumRows*1.)),

		lreads_sum,
		lreads_max,
		lreads_avg = CONVERT(DECIMAL(21,1),(lreads_sum*1.) / (NumRows*1.)),

		DisplayOrderWithinGroup
	FROM (
		SELECT 
			query_hash, 
			PKSQLStmtStoreID = NULL,
			PKQueryPlanStmtStoreID = NULL,

			NumRows = SUM(NumRows),

			status_running = SUM(qh.status_running), 
			status_runnable = SUM(qh.status_runnable),
			status_suspended = SUM(qh.status_suspended),
			status_other = SUM(qh.status_other),

			duration_sum = SUM(qh.duration_sum),
			duration_max = MAX(qh.duration_max),
			--duration_avg = AVG(qh.calc__duration_ms),
			duration_0toP5 = SUM(duration_0toP5),
			duration_P5to1 = SUM(duration_P5to1),
			duration_1to2 = SUM(duration_1to2),
			duration_2to5 = SUM(duration_2to5),
			duration_5to10 = SUM(duration_5to10),
			duration_10to20 = SUM(duration_10to20),
			duration_20plus = SUM(duration_20plus),

			cpu_sum = SUM(cpu_sum),
			cpu_max = MAX(cpu_max),
			--cpu_avg = AVG(qh.cpu),

			reads_sum = SUM(reads_sum),
			reads_max = MAX(reads_max), 
			--reads_avg = AVG(reads),

			writes_sum = SUM(writes_sum),
			writes_max = MAX(writes_max),
			--writes_avg = AVG(qh.writes), 

			lreads_sum = SUM(lreads_sum), 
			lreads_max = MAX(lreads_max), 
			--lreads_avg = AVG(qh.lreads),

			[DisplayOrderWithinGroup] = 0
		FROM #QH_SARagg qh
		GROUP BY query_hash
	) ss
	;
	*/

	/*
	SELECT q.query_hash, q.NumUnique, q.TimesSeen, q.FirstSeen, q.LastSeen,
		agg.*
	from #QH_Identifiers q
		inner join #QH_SARagg agg
			on q.query_hash = agg.query_hash
			--and agg.DisplayOrderWithinGroup <= 3
	;

	return 0;
	*/



	/*

	INSERT INTO #Stmt_SARcache (
		PKSQLStmtStoreID,
		SPIDCaptureTime,
		session_id,
		request_id,

		PKQueryPlanStmtStoreID,

		rqst__status_code,
		calc__duration_ms,
		tempdb__CalculatedNumberOfTasks,
		cpu,
		reads,
		lreads,
		writes,
		tdb_alloc,
		tdb_used,
		mgrant_req,
		mgrant_gr,
		mgrant_used
	)
	SELECT 
		sar.FKSQLStmtStoreID,
		sar.SPIDCaptureTime,
		sar.session_id,
		sar.request_id,

		sar.FKQueryPlanStmtStoreID,

		sar.rqst__status_code,
		sar.calc__duration_ms,
		sar.tempdb__CalculatedNumberOfTasks,
		sar.rqst__cpu_time,
		sar.rqst__reads,
		sar.rqst__logical_reads,
		sar.rqst__writes,
		-1,
		-1, 
		sar.mgrant__requested_memory_kb,
		sar.mgrant__granted_memory_kb,
		sar.mgrant__used_memory_kb
	FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
		INNER JOIN #Stmt_Identifiers st
			ON st.PKSQLStmtStoreID = sar.FKQueryPlanStmtStoreID
	WHERE sar.CollectionInitiatorID = @init
	AND sar.SPIDCaptureTime BETWEEN @start AND @end 
	AND sar.sess__is_user_process = 1
	AND sar.calc__threshold_ignore = 0
	;



	


	INSERT INTO #St_SARagg (
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		NumRows,

		status_running,
		status_runnable,
		status_suspended,
		status_other,

		duration_sum,
		--duration_min,
		duration_max,
		duration_avg,
		--unitless counts:
		duration_0toP5,
		duration_P5to1,
		duration_1to2,
		duration_2to5,
		duration_5to10,
		duration_10to20,
		duration_20plus,

		--request cpu. unit is native (milliseconds)
		cpu_sum,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max,
		cpu_avg,

		--reads. unit is native (8k page reads)
		reads_sum,
		reads_max,
		reads_avg,

		writes_sum,
		writes_max,
		writes_avg,

		lreads_sum,
		lreads_max,
		lreads_avg,

		--from dm_exec_query_memory_grants. unit is native (kb)
		mgrant_req_min,
		mgrant_req_max,
		mgrant_req_avg,

		mgrant_gr_min,
		mgrant_gr_max,
		mgrant_gr_avg,

		mgrant_used_min,
		mgrant_used_max,
		mgrant_used_avg,

		DisplayOrderWithinGroup
	)
	SELECT 
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		NumRows = COUNT(*),

		status_running = SUM(CASE WHEN qh.rqst__status_code=1 THEN 1 ELSE 0 END), 
		status_runnable = SUM(CASE WHEN qh.rqst__status_code=2 THEN 1 ELSE 0 END),
		status_suspended = SUM(CASE WHEN qh.rqst__status_code=4 THEN 1 ELSE 0 END),
		status_other = SUM(CASE WHEN qh.rqst__status_code NOT IN (1,2,4) THEN 1 ELSE 0 END),

		duration_sum = SUM(qh.calc__duration_ms),
		duration_max = MAX(qh.calc__duration_ms),
		duration_avg = AVG(qh.calc__duration_ms),
		duration_0toP5 = SUM(CASE WHEN qh.calc__duration_ms >= 0 AND qh.calc__duration_ms < 0.5 THEN 1 ELSE 0 END),
		duration_P5to1 = SUM(CASE WHEN qh.calc__duration_ms >= 0.5 AND qh.calc__duration_ms < 1.0 THEN 1 ELSE 0 END),
		duration_1to2 = SUM(CASE WHEN qh.calc__duration_ms >= 1.0 AND qh.calc__duration_ms < 2.0 THEN 1 ELSE 0 END),
		duration_2to5 = SUM(CASE WHEN qh.calc__duration_ms >= 2.0 AND qh.calc__duration_ms < 5.0 THEN 1 ELSE 0 END),
		duration_5to10 = SUM(CASE WHEN qh.calc__duration_ms >= 5.0 AND qh.calc__duration_ms < 10.0 THEN 1 ELSE 0 END),
		duration_10to20 = SUM(CASE WHEN qh.calc__duration_ms >= 10.0 AND qh.calc__duration_ms < 20.0 THEN 1 ELSE 0 END),
		duration_20plus = SUM(CASE WHEN qh.calc__duration_ms >= 20.0 THEN 1 ELSE 0 END),

		cpu_sum = SUM(qh.cpu),
		cpu_max = MAX(qh.cpu),
		cpu_avg = AVG(qh.cpu),

		reads_sum = SUM(qh.reads),
		reads_max = MAX(qh.reads), 
		reads_avg = AVG(qh.reads),

		writes_sum = SUM(qh.writes),
		writes_max = MAX(qh.writes),
		writes_avg = AVG(qh.writes), 

		lreads_sum = SUM(qh.lreads), 
		lreads_max = MAX(qh.lreads), 
		lreads_avg = AVG(qh.lreads),

		mgrant_req_min = MIN(qh.mgrant_req),
		mgrant_req_max = MAX(qh.mgrant_req),
		mgrant_req_avg = AVG(qh.mgrant_req),

		mgrant_gr_min = MIN(qh.mgrant_gr),
		mgrant_gr_max = MAX(qh.mgrant_gr),
		mgrant_gr_avg = AVG(qh.mgrant_gr),

		mgrant_used_min = MIN(qh.mgrant_used), 
		mgrant_used_max = MAX(qh.mgrant_used), 
		mgrant_used_avg = AVG(qh.mgrant_used),

		[DisplayOrderWithinGroup] = ROW_NUMBER() OVER (PARTITION BY PKSQLStmtStoreID ORDER BY SUM(qh.calc__duration_ms) DESC)
	FROM #Stmt_SARcache qh
	GROUP BY PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID
		;
		


	INSERT INTO #St_SARagg (
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		NumRows,

		status_running,
		status_runnable,
		status_suspended,
		status_other,

		duration_sum,
		--duration_min,
		duration_max,
		duration_avg,
		--unitless counts:
		duration_0toP5,
		duration_P5to1,
		duration_1to2,
		duration_2to5,
		duration_5to10,
		duration_10to20,
		duration_20plus,

		--request cpu. unit is native (milliseconds)
		cpu_sum,
		--cpu_min		INT,		see above notes on "min" fields
		cpu_max,
		cpu_avg,

		--reads. unit is native (8k page reads)
		reads_sum,
		reads_max,
		reads_avg,

		writes_sum,
		writes_max,
		writes_avg,

		lreads_sum,
		lreads_max,
		lreads_avg,

		DisplayOrderWithinGroup
	)
	SELECT 
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,
		NumRows, 
		status_running,
		status_runnable,
		status_suspended,
		status_other, 
		duration_sum, 
		duration_max,
		duration_avg = CONVERT(DECIMAL(21,1),(duration_sum*1.) / (NumRows*1.)),
		duration_0toP5,
		duration_P5to1,
		duration_1to2,
		duration_2to5,
		duration_5to10,
		duration_10to20,
		duration_20plus,

		cpu_sum,
		cpu_max,
		cpu_avg = CONVERT(DECIMAL(21,1),(cpu_sum*1.) / (NumRows*1.)),

		reads_sum, 
		reads_max, 
		reads_avg = CONVERT(DECIMAL(21,1),(reads_sum*1.) / (NumRows*1.)),

		writes_sum, 
		writes_max, 
		writes_avg = CONVERT(DECIMAL(21,1),(writes_sum*1.) / (NumRows*1.)),

		lreads_sum,
		lreads_max,
		lreads_avg = CONVERT(DECIMAL(21,1),(lreads_sum*1.) / (NumRows*1.)),

		DisplayOrderWithinGroup
	FROM (
		SELECT 
			PKSQLStmtStoreID, 
			PKQueryPlanStmtStoreID = NULL,

			NumRows = SUM(NumRows),

			status_running = SUM(qh.status_running), 
			status_runnable = SUM(qh.status_runnable),
			status_suspended = SUM(qh.status_suspended),
			status_other = SUM(qh.status_other),

			duration_sum = SUM(qh.duration_sum),
			duration_max = MAX(qh.duration_max),
			--duration_avg = AVG(qh.calc__duration_ms),
			duration_0toP5 = SUM(duration_0toP5),
			duration_P5to1 = SUM(duration_P5to1),
			duration_1to2 = SUM(duration_1to2),
			duration_2to5 = SUM(duration_2to5),
			duration_5to10 = SUM(duration_5to10),
			duration_10to20 = SUM(duration_10to20),
			duration_20plus = SUM(duration_20plus),

			cpu_sum = SUM(cpu_sum),
			cpu_max = MAX(cpu_max),
			--cpu_avg = AVG(qh.cpu),

			reads_sum = SUM(reads_sum),
			reads_max = MAX(reads_max), 
			--reads_avg = AVG(reads),

			writes_sum = SUM(writes_sum),
			writes_max = MAX(writes_max),
			--writes_avg = AVG(qh.writes), 

			lreads_sum = SUM(lreads_sum), 
			lreads_max = MAX(lreads_max), 
			--lreads_avg = AVG(qh.lreads),

			[DisplayOrderWithinGroup] = 0
		FROM #ST_SARagg qh
		GROUP BY PKSQLStmtStoreID
	) ss
	;

	*/

	/*
	SELECT q.PKSQLStmtStoreID, q.NumUnique, q.TimesSeen, q.FirstSeen, q.LastSeen,
		agg.*
	FROM #Stmt_Identifiers q
		INNER JOIN #St_SARagg agg
			ON q.PKSQLStmtStoreID = agg.PKSQLStmtStoreID
			AND agg.DisplayOrderWithinGroup <= 3
	;
	*/


	SELECT GroupID = CONVERT(VARCHAR(20),q.query_hash), 
		[Statement] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE sss.stmt_xml END,
		[NumUnique] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE NumUnique END,
		[TimesSeen] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE q.TimesSeen END, 
		[FirstSeen] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE q.FirstSeen END, 
		[LastSeen] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE q.LastSeen END,
		[Statii] = CASE WHEN status_running > 0 THEN CONVERT(VARCHAR(20),status_running) + 'xRun' ELSE '' END + 
					CASE WHEN status_runnable > 0 THEN CONVERT(VARCHAR(20),status_runnable) + 'xRabl' ELSE '' END + 
					CASE WHEN status_suspended > 0 THEN CONVERT(VARCHAR(20),status_suspended) + 'xSus' ELSE '' END + 
					CASE WHEN status_other > 0 THEN CONVERT(VARCHAR(20),status_other) + 'xOth' ELSE '' END,
		[Duration (Sum)] = duration_sum,
		[(Max)] = duration_max,
		[(Avg)] = duration_avg,
		[(0-0.5)] = duration_0toP5,
		[(0.5-1)] = duration_P5to1,
		[(1-2)] = duration_1to2,
		[(2-5)] = duration_2to5,
		[(5-10)] = duration_5to10,
		[(10-20)] = duration_10to20,
		[(20+)] = duration_20plus,
		
		[CPU (Sum)] = cpu_sum,
		[(Max)] = cpu_max,
		[(Avg)] = cpu_avg,
		
		[PReads (Sum)] = reads_sum,
		[(Max)] = reads_max,
		[(Avg)] = reads_avg,
		
		[Writes (Sum)] = writes_sum,
		[(Max)] = writes_max,
		[(Avg)] = writes_avg,
		
		[LReads (Sum)] = lreads_sum,
		[(Max)] = lreads_max,
		[(Avg)] = lreads_avg,
		
		[M Req (Min)] = mgrant_req_min,
		[(Max)] = mgrant_req_max,
		[(Avg)] = mgrant_req_avg,
		
		[M Grnt (Min)] = mgrant_gr_min,
		[(Max)] = mgrant_gr_max,
		[(Avg)] = mgrant_gr_avg,
		
		[M Used (Min)] = mgrant_used_min,
		[(Max)] = mgrant_used_max,
		[(Avg)] = mgrant_used_avg,
		
		DisplayOrderWithinGroup

	FROM #QH_Identifiers q
		INNER JOIN #QH_SARagg qagg
			on q.query_hash = qagg.query_hash
		LEFT OUTER JOIN #SQLStmtStore sss
			ON qagg.PKSQLStmtStoreID = sss.PKSQLStmtStoreID

	UNION ALL

	SELECT GroupIdentifier = '',
		[Statement] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE sss.stmt_xml END,
		[NumUnique] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE NumUnique END,
		[TimesSeen] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE s.TimesSeen END, 
		[FirstSeen] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE s.FirstSeen END, 
		[LastSeen] = CASE WHEN DisplayOrderWithinGroup = 0 THEN N'' ELSE s.LastSeen END,
		[Statii] = CASE WHEN status_running > 0 THEN CONVERT(VARCHAR(20),status_running) + 'xRun' ELSE '' END + 
					CASE WHEN status_runnable > 0 THEN CONVERT(VARCHAR(20),status_runnable) + 'xRabl' ELSE '' END + 
					CASE WHEN status_suspended > 0 THEN CONVERT(VARCHAR(20),status_suspended) + 'xSus' ELSE '' END + 
					CASE WHEN status_other > 0 THEN CONVERT(VARCHAR(20),status_other) + 'xOth' ELSE '' END,
		[Duration (Sum)] = duration_sum,
		[(Max)] = duration_max,
		[(Avg)] = duration_avg,
		[(0-0.5)] = duration_0toP5,
		[(0.5-1)] = duration_P5to1,
		[(1-2)] = duration_1to2,
		[(2-5)] = duration_2to5,
		[(5-10)] = duration_5to10,
		[(10-20)] = duration_10to20,
		[(20+)] = duration_20plus,
		
		[CPU (Sum)] = cpu_sum,
		[(Max)] = cpu_max,
		[(Avg)] = cpu_avg,
		
		[PReads (Sum)] = reads_sum,
		[(Max)] = reads_max,
		[(Avg)] = reads_avg,
		
		[Writes (Sum)] = writes_sum,
		[(Max)] = writes_max,
		[(Avg)] = writes_avg,
		
		[LReads (Sum)] = lreads_sum,
		[(Max)] = lreads_max,
		[(Avg)] = lreads_avg,
		
		[M Req (Min)] = mgrant_req_min,
		[(Max)] = mgrant_req_max,
		[(Avg)] = mgrant_req_avg,
		
		[M Grnt (Min)] = mgrant_gr_min,
		[(Max)] = mgrant_gr_max,
		[(Avg)] = mgrant_gr_avg,
		
		[M Used (Min)] = mgrant_used_min,
		[(Max)] = mgrant_used_max,
		[(Avg)] = mgrant_used_avg,
		
		DisplayOrderWithinGroup
	FROM #Stmt_Identifiers s
		INNER JOIN #St_SARagg sagg
			ON s.PKSQLStmtStoreID = sagg.PKSQLStmtStoreID
		LEFT OUTER JOIN #SQLStmtStore sss
			ON sagg.PKSQLStmtStoreID = sss.PKSQLStmtStoreID

	ORDER BY duration_sum DESC, DisplayOrderWithinGroup ASC;
	*/