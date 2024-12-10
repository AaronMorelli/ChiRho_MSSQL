SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_Collector
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

	FILE NAME: AutoWho_Collector.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_Collector

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: This is the heart of AutoWho. This proc collects data from a wide array of session-focused DMVs and stores 
		the data in various AutoWho tables. Much care has gone into finding the right balance of completeness and efficiency, 
		and much of the below 4800+ lines of code are crafted in a specific fashion to reduce the impact to the SQL instance. 
		The AutoWho_Options table''s extended properties includes meanings for most of the parameters to this procedure, and 
		inline comments below will explain many other aspects of this procedure''s logic.

		See the "Control Flow Summary" comment below.


	FUTURE ENHANCEMENTS: 
 		- What if we used the OUTPUT into tabvar approach with the initial SPID capture query? We could save off fields like session_id, blocking_session_id, duration, 
			and other stuff that would be useful for the scope queries and other stuff. This output tabvar would be much smaller to scan than the #sar table (since
			#sar has so many fields), reducing the # of page reads for later statements.

		- If there are Lazy Writer, CHECKPOINT, or Backup spids active, we could go to the Perfmon DMV and pull info there to get throughput numbers

		--Eventually optimize the Batch/Stmt query plan logic so that if we get query plans for batch, use that base data to 
		  get statement-level query plans from what we have already pulled, like what we do for the SQL batch/statement logic if
		  both are enabled.

To Execute
------------------------
<called from the AutoWho_Executor procedure>
*/
(
	--Note that validation of these variables is done by the caller (AutoWho_Executor or AutoWho_UserCollector)
	@CollectionInitiatorID				TINYINT,
	@TempDBCreateTime					DATETIME,		--used as a fall-back value for some Date function and ISNULL calculations
	@IncludeIdleWithTran				NCHAR(1),		--Y/N
	@IncludeIdleWithoutTran				NCHAR(1),		--Y/N
	@DurationFilter						INT,			--unit=milliseconds, must be >= 0
	@FilterTable						dbo.CoreXRFiltersType READONLY,
	@DBInclusionsExist					BIT,
	@HighTempDBThreshold				INT,			--MB		if a SPID has used this much tempdb space, even if it has no 
														--			trans open and @IncludeIdleWithoutTran=N'N', it is still included
	@CollectSystemSpids					NCHAR(1),		--Y/N
	@HideSelf							NCHAR(1),		--Y/N
	
	@ObtainBatchText					NCHAR(1),		--Y/N
	@ObtainQueryPlanForStatement		NCHAR(1),		--Y/N
	@ObtainQueryPlanForBatch			NCHAR(1),		--Y/N

	--All of these parameters involve "threshold logic" that controls when certain auxiliary data captures
	-- are triggered
	@QueryPlanThreshold					INT,			--unit=milliseconds, must be >= 0
	@QueryPlanThresholdBlockRel			INt,			--unit=milliseconds, must be >= 0
	@ParallelWaitsThreshold				INT,			--unit=milliseconds, must be >= 0
	@ObtainLocksForBlockRelevantThreshold	INT,			--unit=milliseconds, must be >= 0
	@InputBufferThreshold				INT,			--unit=milliseconds, must be >= 0
	@BlockingChainThreshold				INT,			--unit=milliseconds, must be >= 0
	@BlockingChainDepth					TINYINT,		-- # of levels deep to include in the blocking grapch
	@TranDetailsThreshold				INT,			--unit= milliseconds, must be positive


	@DebugSpeed							NCHAR(1),		--Y/N
	@SaveBadDims						NCHAR(1),		--Y/N
	@NumSPIDs							INT OUTPUT,
	@SPIDCaptureTime					DATETIME OUTPUT,
	@UTCCaptureTime						DATETIME OUTPUT
)
AS
BEGIN
/* Control Flow Summary

	1. Variable declaration & initialization

	2. Temp table declaration

	3. Initial population of the #sessions_and_requests (aka "#sar") table. This joins all of the main
		session/request-focused DMVs together and grabs the relevant columns/rows

	4. Initial population of the #tasks_and_waits (aka "#taw") table. This joins dm_os_tasks & dm_os_waiting_tasks
		and grabs the relevant columns/rows

	(the 3 scoping queries are where calc__return_to_user is set)
	5. Main scoping query: applies filter table, maps blocker/blockee info.

	6. Scoping query #2: pulls back in sessions that were excluded by filtering but are blocking sessions that were not filtered.

	7. Scoping query #3: pulls back in sessions that were excluded by the initial #sar population statement b/c they were not
		running, did not have an open tran, were not an interesting system session, and were not using a "large" amount of TempDB,
		but ARE blocking a session that did qualify for the initial #sar population. 
	
	8. Scan the #sar table, populating a number of "threshold variables" that help drive which auxiliary captures we enter.

	9. Scan the #taw table, populating a few more "threshold variables"

	10. If THREADPOOL waits were found in the #taw "threshold variable" scan, insert a "dummy spid" into #sar that will
		represent those threadpool waits.

	11. If there was a blocked SPID that had been blocked for @thresh__maxWaitLength_BlockedSPID milliseconds, 
		enter the Blocking Tree logic, which recursively builds blocking chains.

	12. If we need to capture Input Buffers (need depends on several different things), we enter the IB logic that
		loops over every SPID whose IB needs to be captured, and we run DBCC INPUTBUFFER.

	13. If we need to capture transaction info, populate the @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails table with info from
		the dm_tran_* views

	14. For user spids with calc__return_to_user > 0, we join the #sar table to the SQL statement store (@@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore)
		and grab the PK IDs. This is basically "capturing" the sql text (and potentially batch text) for SPIDs who
		are reusing a sql_handle/statement_start_offset/statement_end_offset that has already been placed into
		@@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore before. This can potentially avoid the cost of resolving lots of sql_handle/offset combos
		through dm_exec_sql_text.

	15. For #sar records that we need to resolve batch & stmt text for, but #14 did not fulfill, loop over the
		sql_handle/offset combos and call dm_exec_sql_text

	16. If our threshold scan found SPIDs that need their query plan obtained, enter the query plan statement logic 
		and grab query plans with dm_exec_text_query_plan.

	17. If our threshold scan found SPIDs whose lock info needs to be captured and aggregated, enter the logic
		for grabbing dm_tran_locks info.

	-- This logic has been moved to the @@CHIRHO_SCHEMA@@.AutoWho_PostProcessor procedure
	-- 18. If the Collector has been directed to resolve page latches, enter the logic to pull all page latch waits
	--	(the resource_description column) and use DBCC PAGE to obtain object and index IDs.

	19. If we entered the BChain logic earlier, and actually generated BChain data, insert a dummy row that
		the BChain data will be tied to.

	20. Dimension logic: 
			Our threshold scan also checked for Dimension IDs that were null in #sar & #taw... that is, where
			the joins to the dimension tables didn't find a match. This means we need to insert a new dimension member.

			For each dimension table, we check to see if @NewDims__<dim table> is > 0, and if so, we grab the new member
			and insert it.

			Once this check (and any necessary new member insertion) has been done for all Dims, we check all Dims 
			together and if any had an insertion, we construct dynamic SQL and update the #sar table with the new
			dimension keys that were just inserted.

			Finally, if there are STILL null dims in the #sar table, we save those rows off to the SARException table
			for diagnosis later.

	21. If we pulled (into temp tables) SQL text, Input Buffers, or Query Plans, we then update the permanent store 
			tables with the stuff we pulled into temp tables.

	22. We then persist the #sar data to @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests, joining in the qp and ib tables as needed.

	23. We persist the #taw data to @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits, persisting background tasks (null session_id) if they
		have certain interesting wait types (practically speaking, THREADPOOL is the main one here). We persist
		all tasks for parallel queries only if the request's duration is above a certain threshold.

	24. Persist the BlockingGraph data, if we gathered any.

	25. Done!
*/
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET ANSI_WARNINGS OFF;		--suppress the aggregation-of-NULL messages

	DECLARE @errorloc NVARCHAR(40);

BEGIN TRY
	SET @errorloc = N'VariableDeclare';

	DECLARE		
		--Variables for error handling
		@err__ErrorText						NVARCHAR(4000), 
		@err__ErrorSeverity					INT, 
		@err__ErrorState					INT,

		--Variables for recording time
		@lv__SPIDCaptureTime				DATETIME,	--local time
		@lv__UTCCaptureTime					DATETIME,	--UTC time
		@lv__beforedt						DATETIME,	--UTC time
		@lv__afterdt						DATETIME,	--UTC time
		@lv__procstartdt					DATETIME,	--UTC time
		@lv__stmtdurations					NVARCHAR(1000),

		--Variables for supporting the various cursor loops
		@lv__CursorCurrentSPID				SMALLINT, 
		@lv__CursorLastSPID					SMALLINT, 
		@lv__SmallDynSQL					NVARCHAR(400),
		@lv__curHandle						VARBINARY(64),
		@lv__curStatementOffsetStart		INT,
		@lv__curStatementOffsetEnd			INT,
		@lv__usedStartOffset				INT, 
		@lv__usedEndOffset					INT,

		@lv__curlatchdbid					SMALLINT,
		@lv__curfileid						SMALLINT,
		@lv__curpageid						BIGINT,

		--miscellaneous
		@lv__BigNvar						NVARCHAR(MAX),
		@lv__TempDBUsage_pages				BIGINT,
		@lv__SAR_numrecords					INT,
		@scratch__int						INT, 
		@lv__StatementsPulled				BIT,
		@lv__BatchesPulled					BIT,

		@lv__MemGrantFake1					INT, 
		@lv__MemGrantFake2					INT,
		@lv__BChainRecsExist				BIT,
		@lv__nullstring						NVARCHAR(8),
		@lv__nullint						INT,
		@lv__nullsmallint					SMALLINT,
		@lv__nulldatetime					DATETIME,

		--the action we take on the wait_type & resource_description fields varies by the type of wait.
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
		@enum__waitspecial__other			TINYINT,

		--for parallel queries, the "top wait" (or "not waiting" if none of the threads are waiting) depends on what type of wait it is
		-- we assign a numeric "priority" category to each task based on its wait type and then assign
		-- an overall "task priority" (across all tasks in a session/requests pair) ordered by wait category & wait duration
		-- this categorization comes in handy in several cases, including Bchain logic and in displaying wait info to the user
		@enum__waitorder__none				TINYINT,
		@enum__waitorder__lck				TINYINT,
		@enum__waitorder__latchblock		TINYINT,
		@enum__waitorder_pglatch			TINYINT,
		@enum__waitorder__cxp				TINYINT,
		@enum__waitorder__other				TINYINT,

		--We capture "core" info (the populations of #sar and #taw, and the subsequent scoping logic) every time. However, 
		-- there are auxiliary captures (lock details, tran details, Blocking Chain logic, update of dimension fields, etc) that are only executed if 
		-- there are spid durations or scenarios that actually require us to execute the auxiliary logic.
		-- In order to efficiently determine whether any of those scenarios exist, we do a one-time scan of #sar, and another scan of #taw,
		-- and store whether these states exist.

		--NOTE: some spids are to be excluded from threshold consideration (see the "istfx" calculation further down below) UNLESS they are block-relevant. A good
		--	example of this is a monitoring spid that sits in a loop all day and every X seconds wakes up and does work. 
		--NOTE2: the following threshold calculations only reflect spids that have calc__return_to_user > 0. i.e. spids that are not going to be returned
		-- (e.g. because their context is a DB that has been excluded) do not influence the value of these threshold variables.

		--calculated from #SAR table
		@thresh__OpenTransExist							TINYINT,	-- if "istfx=0", holds a 1 if any sess__open_transaction_count values are 1, or if the session or request 
																	--  tran iso levels are 0 (unspecified), 3 (RR), or 4 (serializable)
																	--	EFFECT: if 1, causes the auxiliary capture on the Tran DMVs to be fired, even if there are no active or IdleWithTran
																	--		spids that have a duration > the @TranDetailsThreshold.

		@thresh__maxActiveDuration						BIGINT,		--> (For USER spids only) the maximum duration of any running batch.
																	--  EFFECT: (1) If the max active duration is >= the @InputBufferThreshold, causes user spids that are over this threshold
																	--		to have their InputBuffer captured. (as long as calc__return_to_user > 0, of course)
																	--		(2) If max active duration is >= the @TranDetailsThreshold, triggers entry into the Tran Details aux capture,
																	--			where every calc__return_to_user spid with either sess__open_transaction_count or a duration >= @TranDetailsThreshold
																	--			to have their trans captured from the tran DMVs

		@thresh__maxIdleWOTranDuration					BIGINT,		--	(USER spids only) the max "time since last batch" (last_request_end_time) of any spids that do NOT have a tran open
																	--  EFFECT: if this value is >= the @InputBufferThreshold, causes user spids that are over this threshold
																	--		to have their InputBuffer captured. (as long as calc__return_to_user > 0, of course)

		@thresh__maxIdleWithTranDuration				BIGINT,		--  (USER spids only) same as above, except for idle spids that DO have a tran open
																	--  EFFECT: (1) if this value is >= the @InputBufferThreshold, causes user spids that are over this threshold
																	--		to have their InputBuffer captured. (as long as calc__return_to_user > 0, of course)
																	--		(2) If max Idle With Tran duration is >= the @TranDetailsThreshold, triggers entry into the Tran Details aux capture,
																	--			where every calc__return_to_user spid with either sess__open_transaction_count or a duration >= @TranDetailsThreshold
																	--			to have their trans captured from the tran DMVs

		@thresh__QueryPlansNeeded						TINYINT,	-- we check for spids that need their query plan obtained. If even one spid has the following criteria, we set this to 1:
																	--		it is block-relevant, and its running duration is >= @QueryPlanThresholdBlockRel
																	--		it is NOT block-relevant, and its running duration is >= @QueryPlanThreshold
																	--		it is a threshold-ignore spid (and not block-relevant) and it is NOT waiting with the WAITFOR type

		@thresh__GhostCleanupIsRunning					TINYINT,	-- I have seen some terrible runtimes for DBCC PAGE when GHOST CLEANUP is running. To work around this, we check
																	--  for whether Ghost Cleanup is running by pre-defining the DimCommand value (=2) and then checking for its existence
																	--  in SAR. If we do see a spid running this command, then we know to avoid any page latch resolution logic.

		--calculated from #TAW table
		@thresh__THREADPOOLpresent						INT,		--  whether there are any THREADPOOL waits currently. If so, a "special spid" with session_id -998 will be created
																	--  and these waits will be tied to that "spid".

		@thresh__PAGELATCHpresent						INT,		-- whether there are any PAGELATCH or PAGEIOLATCH waits currently. If so, and @ResolvePageLatches = N'Y', then
																	-- logic will be run to resolve the latch resource_description values into the objectid/indexid values

		@thresh__maxWaitLength_BlockedSPID				BIGINT,		-- (For both USER and system spids) the longest wait_duration where blocking_session_id is not null (and <> self)
																	-- This value is used in determining whether to execute Bchain logic and to obtain Lock Details
																	--  EFFECT: (1) If the max wait length of any blocked spid (regardless of whether wait is lock, memory, pagelatch, or other)
																	--		is >= @BlockingChainThreshold, then the BChain logic is triggered.
																	--		(2) If the max wait length of any blocked spid is >= the @ObtainLocksForBlockRelevantThreshold value, then the
																	--		aux capture for Lock Details is triggered

		--calculated from #sar, except for @NewDims__WaitType_taw. Note that the "istfx" calculation is not relevant for these.
		@NewDims__Command								TINYINT,	--In order to save space, both in the  temp tables below (to reduce the # of tempdb pages that must be allocated
		@NewDims__ConnectionAttribute					TINYINT,    -- and thus reduce the risk of this proc running longer when there is high TempDB activity or latency), and in the
		@NewDims__LoginName								TINYINT,	-- permanent tables, many of the varchar fields have been pivoted out into dimension-like tables. These dimension
		@NewDims__NetAddress							TINYINT,	-- tables are populated as new values come in. Thus, the #sar records try to match up their varchar fields to existing
		@NewDims__SessionAttribute						TINYINT,	-- dimension records -- if there is a match, then only the surrogate value is stored, but if there is not, then the varchar
		@NewDims__WaitType_sar							TINYINT,	-- values are stored. During our scan of #sar (and also #taw for wait types), we check to see if there are any string values
		@NewDims__WaitType_taw							TINYINT		-- that we have not put into dimension records yet, and if so, we execute certain logic to do that.
		;

	SET @errorloc = N'Variable Initialize';
	SET @lv__procstartdt = GETUTCDATE();
	SET @lv__BChainRecsExist = 0;			--start out assuming that Blocking Chain records do not exist.
	SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" would collide with a DMV value
	SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
	SET @lv__nullsmallint = -929;			-- overlapping with some special system value
	SET @lv__nulldatetime = '2005-01-01';
	SET @NumSPIDs = -1;
	SET @lv__StatementsPulled = CONVERT(BIT,0);
	SET @lv__BatchesPulled = CONVERT(BIT,0);

	SET @lv__TempDBUsage_pages = CONVERT(BIGINT,@HighTempDBThreshold) * 1024 * 1024		--convert to bytes
									/ 8192;		--and then to pages
	
	--For the "waitspecial" enumeration, the numeric values do not necessarily have any comparison/ordering meaning among each other.
	-- Thus, the fact that @enum__waitspecial__pgblocked = 7 and this is larger than 5 (@enum__waitspecial__lck) is not significant.
	SET @enum__waitspecial__none =			CONVERT(TINYINT, 0);
	SET @enum__waitspecial__lck =			CONVERT(TINYINT, 5);
	SET @enum__waitspecial__pgblocked =		CONVERT(TINYINT, 7);
	SET @enum__waitspecial__pgio =			CONVERT(TINYINT, 10);
	SET @enum__waitspecial__pg =			CONVERT(TINYINT, 15);
	SET @enum__waitspecial__latchblocked =	CONVERT(TINYINT, 17);
	SET @enum__waitspecial__latch =			CONVERT(TINYINT, 20);
	SET @enum__waitspecial__cxp =			CONVERT(TINYINT, 30);
	SET @enum__waitspecial__other =			CONVERT(TINYINT, 25);

	--However, for the "waitorder" enumeration, the relative order DOES matter, as we use this in an ORDER BY clause below
	SET @enum__waitorder__none =			CONVERT(TINYINT, 250);		--a. we typically want a "not waiting" task to sort near the end 
	SET @enum__waitorder__lck =				CONVERT(TINYINT, 5);		--b. lock waits should be at the top (so that blocking data is correct)
	SET @enum__waitorder__latchblock =		CONVERT(TINYINT, 10);		--c. sometimes latch waits can have a blocking spid, so those sort next, after lock waits.
																		--	these can be any type of latch (pg, pgio, a memory object, etc); 
	SET @enum__waitorder_pglatch =			CONVERT(TINYINT, 15);		-- Page and PageIO latches are fairly common, and in parallel plans we want them
																		-- to sort higher than other latches, e.g. the fairly common ACCESS_METHODS_DATASET_PARENT
	SET @enum__waitorder__cxp =				CONVERT(TINYINT, 200);		--d. parallel sorts near the end, since a parallel wait does not mean the spid is completely halted
	SET @enum__waitorder__other =			CONVERT(TINYINT, 20);		--e. catch-all bucket

	SET @errorloc = N'TempTable declare';

	--Holds T-SQL batches from the plan cache, but only if we have been directed to capture them.
	CREATE TABLE #t__batch (
		[sql_handle]				[varbinary](64)		NOT NULL,
		[dbid]						[smallint]			NOT NULL,	--a special ISNULL calc is used for NULL (ad-hoc batches); non-null makes it easier to SARG on this column into the permanent store
		[objectid]					[int]				NOT NULL,	--ditto
		[fail_to_obtain]			[bit]				NOT NULL,	--we can run into a variety of problems when trying to obtain T-SQL batches. This is on overall indicator of probs
		[batch_text]				[nvarchar](max)		NOT NULL
	);

	--Holds T-SQL statements from the plan cache for spids captured in this run. These are always obtained.
	--NOTE: to understand the purpose and nullability of these columns, cf. the #t__batch table
	CREATE TABLE #t__stmt (
		[sql_handle]				[varbinary](64)		NOT NULL,
		[statement_start_offset]	[int]				NOT NULL,
		[statement_end_offset]		[int]				NOT NULL,
		[dbid]						[smallint]			NOT NULL,
		[objectid]					[int]				NOT NULL,
		[fail_to_obtain]			[bit]				NOT NULL, 
		[datalen_batch]				[int]				NOT NULL,
		[stmt_text]					[nvarchar](max)		NOT NULL
	);

	--Holds query plans for batches from the plan cache, but only if we have been directed to capture them. (Off by default)
	--NOTE: to understand the purpose and nullability of these columns, cf. the #t__batch table
	CREATE TABLE #t__batchqp (
		[plan_handle]				[varbinary](64)		NOT NULL, 
		[dbid]						[smallint]			NOT NULL,
		[objectid]					[int]				NOT NULL, 
		[fail_to_obtain]			[bit]				NOT NULL, 
		[query_plan]				[nvarchar](max)		NOT NULL,
		[aw_batchplan_hash]			[varbinary](64)		NOT NULL,
		[PKQueryPlanBatchStoreID]	[bigint]			NULL
	);

	--Holds query plans for statements from the plan cache, but only if we have been directed to capture them. (ON by default)
	--NOTE: to understand the purpose and nullability of these columns, cf. the #t__batch table
	CREATE TABLE #t__stmtqp (
		[plan_handle]				[varbinary](64)		NOT NULL, 
		[statement_start_offset]	[int]				NOT NULL,
		[statement_end_offset]		[int]				NOT NULL,
		[dbid]						[smallint]			NOT NULL,
		[objectid]					[int]				NOT NULL,
		[fail_to_obtain]			[bit]				NOT NULL, 
		[query_plan]				[nvarchar](max)		NOT NULL,
		[aw_stmtplan_hash]			[varbinary](64)		NOT NULL,
		[PKQueryPlanStmtStoreID]	[bigint]			NULL
	);

	CREATE TABLE #t__ib (
		[idcol]						[int]				NOT NULL IDENTITY, 
		[session_id]				[int]				NULL, 
		[EventType]					[varchar](100)		NULL, 
		[Parameters]				[int]				NULL, 
		[InputBuffer]				[nvarchar](4000)	NULL, 
		[aw_buffer_hash]			[varbinary](64)		NULL,
		[PKInputBufferStoreID]		[int]				NULL,
		PRIMARY KEY CLUSTERED (idcol)
	);

	/* Moving page latch resolution logic to the Every 15 Minute Master job
	CREATE TABLE #t__dbccpage (
		[ParentObject]				[varchar](100)		NULL,		--cannot guarantee that DBCC PAGE will always return non-null values, so cols allow nulls
		[Objectcol]					[varchar](100)		NULL,
		[Fieldcol]					[varchar](100)		NULL,
		[Valuecol]					[varchar](100)		NULL
	);
	*/

	CREATE TABLE #BChain (
		[session_id]				[smallint]			NOT NULL, 
		[request_id]				[smallint]			NOT NULL, 
		[exec_context_id]			[smallint]			NULL,
		[calc__blocking_session_id]	[smallint]			NULL, 
		[wait_type]					[nvarchar](60)		NULL, 
		[wait_duration_ms]			[bigint]			NULL, 
		[resource_description]		[nvarchar](500)		NULL, 
		[sql_handle]				[varbinary](64)		NULL, 
		[statement_start_offset]	[int]				NULL, 
		[statement_end_offset]		[int]				NULL,
		[sort_value]				[nvarchar](400)		NOT NULL, 
		[block_group]				[smallint]			NOT NULL,
		[levelindc]					[smallint]			NOT NULL, 
		[rn]						[smallint]			NOT NULL
	);

	CREATE TABLE #tasks_and_waits (
		[task_address]				[varbinary](8)		NOT NULL,
		[parent_task_address]		[varbinary](8)		NULL,
		[session_id]				[smallint]			NOT NULL,	--  Instead of using @lv__nullsmallint, we use -998 bc it has a special value "tasks not tied to spids",
																	--		and our display logic will take certain action if a spid is = -998
		[request_id]				[smallint]			NOT NULL,	--  can hold @lv__nullsmallint
		[exec_context_id]			[smallint]			NOT NULL,	--	ditto
		[tstate]					[nchar](1)			NOT NULL,
		[scheduler_id]				[int]				NULL, 
		[context_switches_count]	[bigint]			NOT NULL,	-- 0 if null
		[wait_type]					[nvarchar](60)		NOT NULL,	-- LATCH_xx string has been converted to "subtype(xx)"; null has been converted to @lv__nullstring
		[wait_latch_subtype]		[nvarchar](100)		NOT NULL,
		[wait_duration_ms]			[bigint]			NOT NULL,	-- 0 if null
		[wait_special_category]		[tinyint]			NOT NULL,	--we use the special category of "none" if this is NULL
		[wait_order_category]		[tinyint]			NOT NULL, 
		[wait_special_number]		[int]				NULL,		-- node id for CXP, lock type for lock waits, file id for page latches
																	-- left NULL for the temp table, but not-null for the perm table
		[wait_special_tag]			[nvarchar](100)		NULL,		-- varies by wait type:
																		--lock waits --> the mode from resource_description
																		--cxpacket --> the sub-wait type
																		--page/io latch --> the DBID:FileID:PageID string at first; if DBCC PAGE is run, then the Obj/Idx results
																		-- are placed here.
																	-- left NULL for the temp table, but not-null for the perm table
		[task_priority]				[int]				NOT NULL,	-- = 1 for the top (aka "most relevant/important") task in a parallel query.
																	-- every spid in #sar should have 1. (If not, prob due to timing issues between #sar and #taw capture)
		[blocking_task_address]		[varbinary](8)		NULL,
		[blocking_session_id]		[smallint]			NULL,		--null if = session_id in the base waiting tasks DMV
		[blocking_exec_context_id]	[smallint]			NULL,
		[resource_description]		[nvarchar](3072)	NULL,
		[resource_dbid]				[int]				NULL,		--dbid; populated for lock and latch waits
		[resource_associatedobjid]	[bigint]			NULL		--the page # for latch waits, the "associatedobjid=" value for lock waits
	);


	/*
		 ****  *****   ****   ****  ***   ***    *   *    *******    *      ****   *      *****  
		*      *      *      *       *   *   *   **  *       *      * *     *   *  *      *      
		 ***   *****   ***    ***    *  *     *  * * *       *     *   *    ****   *      *****  
			*  *          *      *   *   *   *   *  **       *    *******   *   *  *      *      
		****   *****  ****   ****   ***   ***    *   *       *   *       *  ****   *****  *****  
	*/

	-- The below CREATE defines the central table for this procedure. Several notes are in order:
	--  1. Each column name has a prefix tag, then 2 underscores, and then the column name that corresponds to the DMV column from where it was taken.
	--		Thus, the "start_time" column from the sys.dm_exec_requests DMV is named "rqst__start_time".

	--  2. Fields that are not directly copied from DMVs, but instead hold a result of logic in this proc, begin with "calc__"

	CREATE TABLE #sessions_and_requests (
		--core identifier fields
		[sess__session_id]									[smallint]		NOT NULL,
		[rqst__request_id]									[smallint]		NOT NULL,		--dm type is int.... we are banking on the fact that 32k requests is a LOT
																							--we use @lv__nullsmallint for null values
		[TimeIdentifier]									[datetime]		NOT NULL,
		-- For active spids, is rqst.start_time; for idle spids, is sess.last_request_end_time
		-- If the DMV value is 1900-01-01, we use @TempDBCreateTime instead
		-- for special spids, we use 2000-01-01

		--session attributes. These need to be NULL since we insert "special spids" (e.g. -998, -997) where none of these attributes are relevant
		[sess__login_time]									[datetime]		NULL,
		[sess__host_name]									[nvarchar](128) NULL,
		[sess__program_name]								[nvarchar](128) NULL,
		[sess__host_process_id]								[int]			NULL,
		[sess__client_version]								[int]			NULL, 
		[sess__client_interface_name]						[nvarchar](32)	NULL,
		[sess__login_name]									[nvarchar](128) NULL,
		[sess__status_code]									[tinyint]		NULL,
		--[sess__status] [nvarchar](30) NULL,				-- BOL: Possible values [and the TINYINT code we use to stand-in to reduce the table row length]:
															--			0 --> Running - Currently running one or more requests
															--			1 --> Sleeping - Currently running no requests
															--			2 --> Dormant – Session has been reset because of connection pooling and is now in prelogin state.
															--			3 --> Preconnect - Session is in the Resource Governor classifier.
															--			254 --> other?
		[sess__cpu_time]									[int]			NULL,
		[sess__memory_usage]								[int]			NULL,
		[sess__total_scheduled_time]						[int]			NULL,
		[sess__total_elapsed_time]							[int]			NULL,
		[sess__endpoint_id]									[int]			NULL, 
		[sess__last_request_start_time]						[datetime]		NULL, 
		[sess__last_request_end_time]						[datetime]		NULL, 
		[sess__reads]										[bigint]		NULL,
		[sess__writes]										[bigint]		NULL,
		[sess__logical_reads]								[bigint]		NULL,
		[sess__is_user_process]								[bit]			NULL, 
		[sess__transaction_isolation_level]					[smallint]		NULL,
		[sess__lock_timeout]								[int]			NULL,
		[sess__deadlock_priority]							[smallint]		NULL,		--dm type is int... we are banking on the fact that all deadlock priority values are small pos or neg
		[sess__row_count]									[bigint]		NULL,
		[sess__original_login_name]							[nvarchar](128) NULL,
		[sess__open_transaction_count]						[int]			NULL,
		[sess__group_id]									[int]			NULL, 
		[sess__database_id]									[smallint]		NULL,		--the context that the spid is running in
		[sess__FKDimLoginName]								[smallint]		NULL,
		[sess__FKDimSessionAttribute]						[int]			NULL,
		
		--Connection info
		[conn__connect_time]								[datetime]		NULL,
		[conn__net_transport]								[nvarchar](40)	NULL,
		[conn__protocol_type]								[nvarchar](40)	NULL,
		[conn__protocol_version]							[int]			NULL,
		[conn__endpoint_id]									[int]			NULL,
		[conn__encrypt_option]								[nvarchar](40)	NULL,
		[conn__auth_scheme]									[nvarchar](40)	NULL,
		[conn__node_affinity]								[smallint]		NULL,
		[conn__net_packet_size]								[int]			NULL,
		[conn__client_net_address]							[varchar](48)	NULL,
		[conn__client_tcp_port]								[int]			NULL,
		[conn__local_net_address]							[varchar](48)	NULL,
		[conn__local_tcp_port]								[int]			NULL,
		[conn__FKDimNetAddress]								[smallint]		NULL,
		[conn__FKDimConnectionAttribute]					[smallint]		NULL,

		--request attributes
		[rqst__start_time]									[datetime]		NULL,
		[rqst__status_code]									[tinyint]		NULL, 
		--[rqst__status] [nvarchar](30) NULL,				-- BOL: Possible values [and our stand-in TINYINT values to minimize table row length]:
																	--			0 --> Background
																	--			1 --> Running
																	--			2 --> Runnable
																	--			3 --> Sleeping
																	--			4 --> Suspended
																	--			254 --> other?

		[rqst__command]										[nvarchar](40)	NULL,	
		[rqst__sql_handle]									[varbinary](64) NULL,
		[rqst__statement_start_offset]						[int]			NULL,
		[rqst__statement_end_offset]						[int]			NULL,
		[rqst__plan_handle]									[varbinary](64) NULL,
		[rqst__blocking_session_id]							[smallint]		NULL,		--most of our logic depends on calc__blocking_session_id, so only persisting this for research reasons
		[rqst__wait_type]									[nvarchar](60)	NULL,
		[rqst__wait_latch_subtype]							[nvarchar](100) NULL,
		[rqst__wait_time]									[int]			NULL, 
		[rqst__wait_resource]								[nvarchar](256) NULL, 
		[rqst__open_transaction_count]						[int]			NULL,
		[rqst__open_resultset_count]						[int]			NULL, 
		[rqst__percent_complete]							[real]			NULL,
		[rqst__cpu_time]									[int]			NULL,
		[rqst__total_elapsed_time]							[int]			NULL, 
		[rqst__scheduler_id]								[int]			NULL, 
		[rqst__reads]										[bigint]		NULL,
		[rqst__writes]										[bigint]		NULL,
		[rqst__logical_reads]								[bigint]		NULL,
		[rqst__transaction_isolation_level]					[tinyint]		NULL,	--dm type is 'smallint'... banking on the fact that tran iso level only has a handful of possible values
		[rqst__lock_timeout]								[int]			NULL, 
		[rqst__deadlock_priority]							[smallint]		NULL,	--dm type is 'int'... banking on the fact that deadlock priority nums are very small pos or neg
		[rqst__row_count]									[bigint]		NULL, 
		[rqst__granted_query_memory]						[int]			NULL, 
		[rqst__executing_managed_code]						[bit]			NULL, 
		[rqst__group_id]									[int]			NULL, 
		[rqst__query_hash]									binary(8)		NULL,
		[rqst__query_plan_hash]								binary(8)		NULL,
		[rqst__FKDimCommand]								[smallint]		NULL, 
		[rqst__FKDimWaitType]								[smallint]		NULL, 

		--TempDB utilization
		[tempdb__sess_user_objects_alloc_page_count]		[bigint]		NULL,
		[tempdb__sess_user_objects_dealloc_page_count]		[bigint]		NULL,
		[tempdb__sess_internal_objects_alloc_page_count]	[bigint]		NULL,
		[tempdb__sess_internal_objects_dealloc_page_count]	[bigint]		NULL,
		[tempdb__task_user_objects_alloc_page_count]		[bigint]		NULL,
		[tempdb__task_user_objects_dealloc_page_count]		[bigint]		NULL,
		[tempdb__task_internal_objects_alloc_page_count]	[bigint]		NULL,
		[tempdb__task_internal_objects_dealloc_page_count]	[bigint]		NULL,
		[tempdb__CalculatedNumberOfTasks]					[smallint]		NULL, 
		[tempdb__CalculatedCurrentTempDBUsage_pages]		[bigint]		NULL,

		--Memory Grant info
		[mgrant__request_time]								[datetime]		NULL, 
		[mgrant__grant_time]								[datetime]		NULL, 
		[mgrant__requested_memory_kb]						[bigint]		NULL,
		[mgrant__required_memory_kb]						[bigint]		NULL, 
		[mgrant__granted_memory_kb]							[bigint]		NULL,
		[mgrant__used_memory_kb]							[bigint]		NULL, 
		[mgrant__max_used_memory_kb]						[bigint]		NULL, 
		[mgrant__dop]										[smallint]		NULL,

		--values that we will calculate ourselves:
		[calc__record_priority]								[tinyint]		NULL,
			--used when displaying results (to keep special "spids" at the top, system spids second, then user-active, then user-idle)

		[calc__is_compiling]								[bit]			NULL,
		[calc__duration_ms]									[bigint]		NULL,
		[calc__blocking_session_id]							[smallint]		NULL, 
		[calc__block_relevant]								[tinyint]		NULL,
		[calc__return_to_user]								[smallint]		NULL,
		[calc__is_blocker]									[bit]			NULL, 
		[calc__sysspid_isinteresting]						[bit]			NULL,
		[calc__tmr_wait]									[tinyint]		NULL,
			--under certain circumstances, we want the viewer to alter its normal behavior for the Object_Name, Current_Command, and Progress fields
			--1		TM REQUEST		<running>
			--2		TM REQUEST		WRITELOG
			--3		TM REQUEST		PREEMPTIVE_TRANSIMPORT
			--4		TM REQUEST		PREEMPTIVE_DTC_ENLIST
			--5		TM REQUEST		DTC_STATE
			--6		TM REQUEST		DTC
			--7		TM REQUEST		LOGBUFFER
			--8		TM REQUEST		TRANSACTION_MUTEX
			--254	TM REQUEST		<catch-all for other waits>
		[calc__threshold_ignore]							[bit]			NULL,
		[calc__FKSQLStmtStoreID]							[bigint]		NULL,
		[calc__FKSQLBatchStoreID]							[bigint]		NULL 
	);

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = N'TTdec:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__procstartdt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END

/***************************************************************************************************************************
											End Session Table & Statistics creation  
***************************************************************************************************************************/


	/*
		***  *   *  ***  *****  ***     *      *          ****      *      ****   *****  *   *  ***    ****
		 *   **  *   *     *     *     * *     *         *         * *     *   *    *    *   *  *  *   *
		 *   * * *   *     *     *    *   *    *        *         *   *    ****     *    *   *  ***    ****
		 *   *  **   *     *     *   *******   *         *       *******   *        *    *   *  *  *   *
		***  *   *  ***    *    *** *       *  *****      ****  *       *  *        *    *****  *   *  ****
	*/
	SET @errorloc = N'SAR Initial Population';

	SET @lv__SPIDCaptureTime = GETDATE();
	SET @lv__UTCCaptureTime = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @lv__SPIDCaptureTime);
	--Set the output parameters
	SET @SPIDCaptureTime = @lv__SPIDCaptureTime;
	SET @UTCCaptureTime = @lv__UTCCaptureTime;

	INSERT INTO #sessions_and_requests (
		[sess__session_id],					--1
		[rqst__request_id],
		[TimeIdentifier],

		[sess__login_time],
		[sess__host_name],					--5
		[sess__program_name],
		[sess__host_process_id],
		[sess__client_version],
		[sess__client_interface_name],
		[sess__login_name],					--10
		[sess__status_code],													
		[sess__cpu_time],
		[sess__memory_usage],
		[sess__total_scheduled_time],
		[sess__total_elapsed_time],			--15
		[sess__endpoint_id],
		[sess__last_request_start_time],
		[sess__last_request_end_time],
		[sess__reads],
		[sess__writes],						--20
		[sess__logical_reads],
		[sess__is_user_process],
		[sess__transaction_isolation_level],
		[sess__lock_timeout],
		[sess__deadlock_priority],			--25
		[sess__row_count],
		[sess__original_login_name],
		[sess__open_transaction_count],
		[sess__group_id],
		[sess__database_id],				--30
		[sess__FKDimLoginName],
		[sess__FKDimSessionAttribute],

		--Connection info
		[conn__connect_time],
		[conn__net_transport],
		[conn__protocol_type],				--35
		[conn__protocol_version],
		[conn__endpoint_id],
		[conn__encrypt_option],
		[conn__auth_scheme],
		[conn__node_affinity],				--40
		[conn__net_packet_size],
		[conn__client_net_address],
		[conn__client_tcp_port],
		[conn__local_net_address],
		[conn__local_tcp_port],				--45
		[conn__FKDimNetAddress],
		[conn__FKDimConnectionAttribute],

		--request attributes; all of these fields must be nullable since a session might not have a running request
		[rqst__start_time],
		[rqst__status_code],
		[rqst__command],					--50
		[rqst__sql_handle],
		[rqst__statement_start_offset],
		[rqst__statement_end_offset],
		[rqst__plan_handle],
		[rqst__blocking_session_id],		--55
		[rqst__wait_type],
		[rqst__wait_latch_subtype],
		[rqst__wait_time],
		[rqst__wait_resource],
		[rqst__open_transaction_count],		--60
		[rqst__open_resultset_count],
		[rqst__percent_complete],
		[rqst__cpu_time],
		[rqst__total_elapsed_time],
		[rqst__scheduler_id],				--65
		[rqst__reads],
		[rqst__writes],
		[rqst__logical_reads],
		[rqst__transaction_isolation_level],
		[rqst__lock_timeout],				--70
		[rqst__deadlock_priority],
		[rqst__row_count],
		[rqst__granted_query_memory],
		[rqst__executing_managed_code],
		[rqst__group_id],					--75
		[rqst__query_hash],
		[rqst__query_plan_hash],
		[rqst__FKDimCommand],
		[rqst__FKDimWaitType],

		--TempDB utilization
		[tempdb__sess_user_objects_alloc_page_count],			--80
		[tempdb__sess_user_objects_dealloc_page_count],
		[tempdb__sess_internal_objects_alloc_page_count],
		[tempdb__sess_internal_objects_dealloc_page_count],
		[tempdb__task_user_objects_alloc_page_count],
		[tempdb__task_user_objects_dealloc_page_count],			--85
		[tempdb__task_internal_objects_alloc_page_count],
		[tempdb__task_internal_objects_dealloc_page_count],
		[tempdb__CalculatedNumberOfTasks],
		[tempdb__CalculatedCurrentTempDBUsage_pages],

		--Memory Grant info
		[mgrant__request_time],					--90
		[mgrant__grant_time],
		[mgrant__requested_memory_kb],
		[mgrant__required_memory_kb],
		[mgrant__granted_memory_kb],
		[mgrant__used_memory_kb],				--95
		[mgrant__max_used_memory_kb],
		[mgrant__dop],

		[calc__record_priority],
		[calc__is_compiling],
		[calc__duration_ms],					--100
		[calc__blocking_session_id],
		[calc__return_to_user],
		[calc__is_blocker],
		[calc__sysspid_isinteresting],
		[calc__tmr_wait]						--105
	)
	SELECT 
		[sess__session_id],					--1
		[rqst__request_id],
		[TimeIdentifier],

		--session attributes
		[sess__login_time],
						--for the string fields that are in dim tables, we NULL them out if we found a match in the dimension 
						-- table. This should be the normal case, and thus we'll normally avoid persisting longer string
						-- values to tempdb pages. This helps to keep the row size from being too obscene.
		[sess__host_name] = CASE WHEN withdims.DimSessionAttributeID IS NULL THEN ISNULL(sess__host_name,@lv__nullstring) ELSE NULL END,			--5
		[sess__program_name] = CASE WHEN withdims.DimSessionAttributeID IS NULL THEN ISNULL(sess__program_name,@lv__nullstring) ELSE NULL END,
		[sess__host_process_id],
		[sess__client_version] = ISNULL(sess__client_version,@lv__nullint),
		[sess__client_interface_name] = CASE WHEN withdims.DimSessionAttributeID IS NULL THEN ISNULL(sess__client_interface_name,@lv__nullstring) ELSE NULL END,
		[sess__login_name] = CASE WHEN withdims.DimLoginNameID IS NULL THEN ISNULL(sess__login_name,@lv__nullstring) ELSE NULL END,			--10
		[sess__status_code],
		[sess__cpu_time],
		[sess__memory_usage],
		[sess__total_scheduled_time],
		[sess__total_elapsed_time],			--15
		[sess__endpoint_id],
		[sess__last_request_start_time],
		[sess__last_request_end_time],
		[sess__reads],
		[sess__writes],						--20
		[sess__logical_reads],
		[sess__is_user_process],
		[sess__transaction_isolation_level],
		[sess__lock_timeout],
		[sess__deadlock_priority],			--25
		[sess__row_count],
		[sess__original_login_name] = CASE WHEN withdims.DimLoginNameID IS NULL THEN ISNULL(sess__original_login_name,@lv__nullstring) ELSE NULL END,
		[sess__open_transaction_count],
		[sess__group_id],
		[sess__database_id],				--30
		[sess__FKDimLoginName] = CASE WHEN withdims.DimLoginNameID IS NOT NULL THEN withdims.DimLoginNameID 
									WHEN sess__login_name IS NULL AND sess__original_login_name IS NULL THEN 1
									ELSE NULL END,
		[sess__FKDimSessionAttribute] = withdims.DimSessionAttributeID,

		--Connection info
		[conn__connect_time],
		[conn__net_transport] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__net_transport,@lv__nullstring) ELSE NULL END,
		[conn__protocol_type] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__protocol_type,@lv__nullstring) ELSE NULL END,		--35
		[conn__protocol_version] = ISNULL(conn__protocol_version,@lv__nullint),
		[conn__endpoint_id] = ISNULL(conn__endpoint_id,@lv__nullint),
		[conn__encrypt_option] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__encrypt_option,@lv__nullstring) ELSE NULL END,
		[conn__auth_scheme] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__auth_scheme,@lv__nullstring) ELSE NULL END,
		[conn__node_affinity] = ISNULL(conn__node_affinity,@lv__nullsmallint),					--40
		[conn__net_packet_size] = ISNULL(conn__net_packet_size,@lv__nullint),

		[conn__client_net_address] = CASE WHEN withdims.DimNetAddressID IS NOT NULL THEN NULL ELSE ISNULL(withdims.conn__client_net_address,@lv__nullstring) END,
		[conn__client_tcp_port],
		[conn__local_net_address] = CASE WHEN withdims.DimNetAddressID IS NOT NULL THEN NULL ELSE ISNULL(withdims.conn__local_net_address,@lv__nullstring) END,
		[conn__local_tcp_port] = ISNULL(conn__local_tcp_port,@lv__nullint),					--45
		[conn__FKDimNetAddress] = CASE WHEN withdims.DimNetAddressID IS NOT NULL THEN withdims.DimNetAddressID
									WHEN conn__local_net_address IS NULL AND conn__local_tcp_port IS NULL
										AND conn__client_net_address IS NULL THEN 1
									ELSE NULL END,

		[conn__FKDimConnectionAttribute] = CASE WHEN sess__is_user_process = 0 THEN 1 ELSE withdims.DimConnectionAttributeID END,
									--system spids don't have a connection, so we always give them the "null connection" row

		--request attributes
		[rqst__start_time],
		[rqst__status_code],
		[rqst__command] = CASE WHEN withdims.DimCommandID IS NULL THEN ISNULL(withdims.rqst__command,@lv__nullstring) ELSE NULL END,		--50
		[rqst__sql_handle],						
		[rqst__statement_start_offset],
		[rqst__statement_end_offset],
		[rqst__plan_handle],
		[rqst__blocking_session_id],				--55
		[rqst__wait_type] = CASE WHEN withdims.DimWaitTypeID IS NULL THEN ISNULL(withdims.rqst__wait_type,@lv__nullstring) ELSE NULL END,
		[rqst__wait_latch_subtype] = CASE WHEN withdims.DimWaitTypeID IS NULL THEN rqst__wait_latch_subtype ELSE NULL END,
		[rqst__wait_time],
		[rqst__wait_resource],
		[rqst__open_transaction_count],		--60
		[rqst__open_resultset_count],
		[rqst__percent_complete],
		[rqst__cpu_time],
		[rqst__total_elapsed_time],
		[rqst__scheduler_id],				--65
		[rqst__reads],
		[rqst__writes],					
		[rqst__logical_reads],
		[rqst__transaction_isolation_level],
		[rqst__lock_timeout],				--70
		[rqst__deadlock_priority],
		[rqst__row_count],
		[rqst__granted_query_memory],
		[rqst__executing_managed_code],
		[rqst__group_id],					--75
		[rqst__query_hash],
		[rqst__query_plan_hash],
		[rqst__FKDimCommand] = CASE WHEN withdims.DimCommandID IS NOT NULL THEN withdims.DimCommandID
									WHEN rqst__request_id = @lv__nullsmallint THEN 1	--idle spids get a pre-defined Dim code
									WHEN withdims.rqst__command IS NULL THEN 1		--don't think this can happen... just a CYA 
									ELSE NULL END,		--probably a new entry, will be added to our dimension later
		[rqst__FKDimWaitType] = CASE WHEN withdims.DimWaitTypeID IS NOT NULL THEN withdims.DimWaitTypeID
									WHEN ISNULL(LTRIM(RTRIM(withdims.rqst__wait_type)),N'') = N'' THEN 1
									ELSE NULL END,

		--TempDB utilization
		[tempdb__sess_user_objects_alloc_page_count],			--80
		[tempdb__sess_user_objects_dealloc_page_count],
		[tempdb__sess_internal_objects_alloc_page_count],
		[tempdb__sess_internal_objects_dealloc_page_count],
		[tempdb__task_user_objects_alloc_page_count],
		[tempdb__task_user_objects_dealloc_page_count],			--85
		[tempdb__task_internal_objects_alloc_page_count],
		[tempdb__task_internal_objects_dealloc_page_count],
		[tempdb__CalculatedNumberOfTasks],
		[tempdb__CalculatedCurrentTempDBUsage_pages],

		--Memory Grant info
		[mgrant__request_time],					--90
		[mgrant__grant_time],
		[mgrant__requested_memory_kb],
		[mgrant__required_memory_kb],
		[mgrant__granted_memory_kb],
		[mgrant__used_memory_kb],			--95
		[mgrant__max_used_memory_kb],
		[mgrant__dop],

		[calc__record_priority],
		[calc__is_compiling],
		[calc__duration_ms],				--100
		[calc__blocking_session_id],
		[calc__return_to_user],
		[calc__is_blocker],
		[calc__sysspid_isinteresting],
		[calc__tmr_wait]					--105
	FROM (
		SELECT 
			dco.DimCommandID,
			dwt.DimWaitTypeID,
			dca.DimConnectionAttributeID,
			dna.DimNetAddressID,
			dln.DimLoginNameID,
			dsa.DimSessionAttributeID, 
			[sess__session_id] = s.session_id,
			[rqst__request_id] = ISNULL(r.request_id,@lv__nullsmallint),
			[TimeIdentifier] = CASE WHEN r.request_id IS NOT NULL 
									THEN ISNULL(NULLIF(r.start_time,'1900-01-01'),@TempDBCreateTime)
									ELSE ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime) 
									END,

			--session attributes
			[sess__login_time] = s.login_time,
			[sess__host_name] = s.[host_name],
			[sess__program_name] = s.[program_name],
			[sess__host_process_id] = s.host_process_id,
			[sess__client_version] = s.client_version,
			[sess__client_interface_name] = s.client_interface_name,
			[sess__login_name] = s.login_name,

			[sess__status_code] = CASE LOWER(s.[status]) 
									WHEN N'running'		THEN CONVERT(TINYINT,0)
									WHEN N'sleeping'	THEN CONVERT(TINYINT,1)
									WHEN N'dormant'		THEN CONVERT(TINYINT,2)
									WHEN N'preconnect'	THEN CONVERT(TINYINT,3)
									ELSE CONVERT(TINYINT,255)
									END,			
			[sess__cpu_time] = s.cpu_time,
			[sess__memory_usage] = s.memory_usage,
			[sess__total_scheduled_time] = s.total_scheduled_time,
			[sess__total_elapsed_time] = s.total_elapsed_time,
			[sess__endpoint_id] = s.endpoint_id,
			[sess__last_request_start_time] = s.last_request_start_time,
			[sess__last_request_end_time] = s.last_request_end_time,
			[sess__reads] = s.reads,
			[sess__writes] = s.writes,
			[sess__logical_reads] = s.logical_reads,
			[sess__is_user_process] = s.is_user_process,
			[sess__transaction_isolation_level] = s.transaction_isolation_level,
			[sess__lock_timeout] = s.[lock_timeout],
			[sess__deadlock_priority] = s.[deadlock_priority],
			[sess__row_count] = s.[row_count],
			[sess__original_login_name] = s.original_login_name,
			[sess__open_transaction_count] = sysproc.open_tran,					--s.open_transaction_count,
			[sess__group_id] = s.group_id,
			[sess__database_id] = sysproc.[dbid],								--2012 and later: s.database_id,

			--Connection info
			[conn__connect_time] = c.connect_time,
			[conn__net_transport] = c.net_transport,
			[conn__protocol_type] = c.protocol_type,
			[conn__protocol_version] = c.protocol_version,
			[conn__endpoint_id] = c.endpoint_id,
			[conn__encrypt_option] = c.encrypt_option,
			[conn__auth_scheme] = c.auth_scheme,
			[conn__node_affinity] = c.node_affinity,
			[conn__net_packet_size] = c.net_packet_size,
			[conn__client_net_address] = c.client_net_address,
			[conn__client_tcp_port] = c.client_tcp_port,
			[conn__local_net_address] = c.local_net_address,
			[conn__local_tcp_port] = c.local_tcp_port,

			--request attributes
			[rqst__start_time] = r.start_time,
			[rqst__status_code] = CASE LOWER(r.[status]) 
									WHEN N'background'	THEN CONVERT(TINYINT,0)
									WHEN N'running'		THEN CONVERT(TINYINT,1)
									WHEN N'runnable'	THEN CONVERT(TINYINT,2)
									WHEN N'sleeping'	THEN CONVERT(TINYINT,3)
									WHEN N'suspended'	THEN CONVERT(TINYINT,4)
									ELSE CONVERT(TINYINT,5)
									END,
			[rqst__command] = r.command,
			[rqst__sql_handle] = r.[sql_handle],
			[rqst__statement_start_offset] = r.statement_start_offset,
				--2015-11-10: not sure if this logic is still needed
				--CASE WHEN r.command IN ('CREATE INDEX') THEN 0
					--						ELSE r.statement_start_offset END,
			[rqst__statement_end_offset] = r.statement_end_offset,
				--ditto:
				--CASE WHEN r.command IN ('CREATE INDEX', 'ALTER INDEX')
				--AND r.statement_end_offset = 0 THEN -1 ELSE r.statement_end_offset END,
			[rqst__plan_handle] = r.plan_handle,
			[rqst__blocking_session_id] = r.blocking_session_id,
			[rqst__wait_type] = r.wait_type, 
			[rqst__wait_latch_subtype] = (
				CASE WHEN r.wait_type LIKE N'LATCH%' 
						--old logic: THEN SUBSTRING(wait_resource, 1, CHARINDEX(' ', wait_resource)-1) + REPLACE(r.wait_type, 'LATCH_', '(') + ')'
						THEN (CASE WHEN wait_resource IS NULL THEN N'' 
								ELSE SUBSTRING(wait_resource, 1, CHARINDEX(' ', wait_resource)-1) 
								END )
					ELSE N'' END),
			[rqst__wait_time] = r.wait_time,
			[rqst__wait_resource] = r.wait_resource,
			[rqst__open_transaction_count] = null,  --not in SQL 2008: r.open_transaction_count,
			[rqst__open_resultset_count] = r.open_resultset_count,
			[rqst__percent_complete] = r.percent_complete,
			[rqst__cpu_time] = r.cpu_time,
			[rqst__total_elapsed_time] = r.total_elapsed_time,
			[rqst__scheduler_id] = r.scheduler_id,
			[rqst__reads] = r.reads,
			[rqst__writes] = r.writes,
			[rqst__logical_reads] = r.logical_reads,
			[rqst__transaction_isolation_level] = r.transaction_isolation_level,
			[rqst__lock_timeout] = r.[lock_timeout],
			[rqst__deadlock_priority] = r.[deadlock_priority],
			[rqst__row_count] = r.[row_count],
			[rqst__granted_query_memory] = r.granted_query_memory,
			[rqst__executing_managed_code] = r.executing_managed_code,
			[rqst__group_id] = r.group_id,
			[rqst__query_hash] = r.query_hash,
			[rqst__query_plan_hash] = r.query_plan_hash, 

			--TempDB utilization
			[tempdb__sess_user_objects_alloc_page_count] = ssu.user_objects_alloc_page_count,
			[tempdb__sess_user_objects_dealloc_page_count] = ssu.user_objects_dealloc_page_count,
			[tempdb__sess_internal_objects_alloc_page_count] = ssu.internal_objects_alloc_page_count,
			[tempdb__sess_internal_objects_dealloc_page_count] = ssu.internal_objects_dealloc_page_count,
			[tempdb__task_user_objects_alloc_page_count] = tsu.user_objects_alloc_page_count,
			[tempdb__task_user_objects_dealloc_page_count] = tsu.user_objects_dealloc_page_count,
			[tempdb__task_internal_objects_alloc_page_count] = tsu.internal_objects_alloc_page_count,
			[tempdb__task_internal_objects_dealloc_page_count] = tsu.internal_objects_dealloc_page_count,
			[tempdb__CalculatedNumberOfTasks] = tsu.num_tasks,
			[tempdb__CalculatedCurrentTempDBUsage_pages] = (
						CASE WHEN (ISNULL(ssu.user_objects_alloc_page_count,0) - ISNULL(ssu.user_objects_dealloc_page_count,0)) < 0 THEN 0
							ELSE (ISNULL(ssu.user_objects_alloc_page_count,0) - ISNULL(ssu.user_objects_dealloc_page_count,0))
							END + 
						CASE WHEN (ISNULL(ssu.internal_objects_alloc_page_count,0) - ISNULL(ssu.internal_objects_dealloc_page_count,0)) < 0 THEN 0
							ELSE (ISNULL(ssu.internal_objects_alloc_page_count,0) - ISNULL(ssu.internal_objects_dealloc_page_count,0))
							END + 
						CASE WHEN (ISNULL(tsu.user_objects_alloc_page_count,0) - ISNULL(tsu.user_objects_dealloc_page_count,0)) < 0 THEN 0
							ELSE (ISNULL(tsu.user_objects_alloc_page_count,0) - ISNULL(tsu.user_objects_dealloc_page_count,0))
							END + 
						CASE WHEN (ISNULL(tsu.internal_objects_alloc_page_count,0) - ISNULL(tsu.internal_objects_dealloc_page_count,0)) < 0 THEN 0
							ELSE (ISNULL(tsu.internal_objects_alloc_page_count,0) - ISNULL(tsu.internal_objects_dealloc_page_count,0))
							END
				),

			--Memory Grant info
			[mgrant__request_time] = mg.request_time,
			[mgrant__grant_time] = mg.grant_time,
			[mgrant__requested_memory_kb] = mg.requested_memory_kb,
			[mgrant__required_memory_kb] = mg.required_memory_kb,
			[mgrant__granted_memory_kb] = mg.granted_memory_kb,
			[mgrant__used_memory_kb] = mg.used_memory_kb,
			[mgrant__max_used_memory_kb] = mg.max_used_memory_kb,
			[mgrant__dop] = mg.dop,

			--this is a display-relevent field, but we calc it now to save on calc time @ presentation time
			[calc__record_priority] = (CASE WHEN s.is_user_process = 0 THEN CONVERT(TINYINT,5) 
							WHEN r.request_id IS NULL THEN CONVERT(TINYINT,10) ELSE CONVERT(TINYINT,9) END),

			--As of 2016-04-25, this logic still isn't working correctly; more research is needed to determine whether there are clear
			-- patterns for detecting a request that is actually in compilation. In the meantime, the calc__is_compiling field is not
			-- used by the display logic.
			[calc__is_compiling] = CASE WHEN r.query_hash = 0x0 AND r.query_plan_hash = 0x0 
										AND r.statement_end_offset = 0 AND r.command <> 'CREATE INDEX'
									THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END,
			-- A duration is positive if the spid is active (request start_time is not null), and negative if the spid is idle (duration based off
			-- of session.last_request_end_time). Note that this logic has to be tricky because of the risk of data type overflows. Our duration
			-- is stored in milliseconds, but a system spid on a server that hasn't been rebooted in a while will overflow the DATEDIFF function.
			-- Therefore, the below logic first evaluates on a DATEDIFF(SECOND... calculation before branching into a calculation that will produce
			-- the appropriate difference in milliseconds.
			-- Note that (rarely) a request start time can be 1900-01-01, and we also defend against NULL values. We use the TempDB creation time
			-- as a fallback value in these cases.
			[calc__duration_ms] = (
					CASE WHEN r.request_id IS NOT NULL
						THEN (
							CASE WHEN DATEDIFF(SECOND, ISNULL(NULLIF(r.start_time,'1900-01-01'),@TempDBCreateTime), @lv__SPIDCaptureTime) > 300 
								THEN CONVERT(BIGINT,
												DATEDIFF(SECOND, 
															ISNULL(NULLIF(r.start_time,'1900-01-01'),@TempDBCreateTime), 
															@lv__SPIDCaptureTime
														)
											)*CONVERT(BIGINT,1000)	--note that we lose the millisecond-precision in this case, but for long-running spids, that isn't important.
								ELSE CONVERT(BIGINT,DATEDIFF(MILLISECOND,ISNULL(NULLIF(r.start_time,'1900-01-01'),@TempDBCreateTime), @lv__SPIDCaptureTime))
							END)
					ELSE (	--r.request_id IS null, idle spid. Do a similar calculation but on last_request_end_time
						CASE WHEN DATEDIFF(second, ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime), @lv__SPIDCaptureTime) > 300 
								THEN CONVERT(BIGINT,
												DATEDIFF(SECOND, 
															ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime), 
															@lv__SPIDCaptureTime
														)
											)*CONVERT(BIGINT,1000)
								ELSE CONVERT(BIGINT,DATEDIFF(MILLISECOND,ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime), @lv__SPIDCaptureTime))
							END
					)
					END),
			[calc__blocking_session_id] = ISNULL(NULLIF(r.blocking_session_id,r.session_id),0),	--clear field for parallel waits; this field may get overwritten by the task-related logic below
			[calc__return_to_user] = 0,			--start out assuming that nothing will qualify. Our scope query will set this to > 0 for the appropriate spids
			[calc__is_blocker]  = 0, 	--We cannot use dm_exec_requests to drive what is and is not a blocker from the dm_exec_requests data that we are pulling, 
										-- due to spids that are running a parallel query and thus show as blocking themselves. Thus, this "is_blocker" 
										-- column will be populated when we pull data from the dm_os_waiting_tasks view

			--We basically compare each SPID (and its "command") with its known waiting type/status to see if the session spid is active or not.
			[calc__sysspid_isinteresting] = (
					CASE WHEN s.is_user_process = 1									THEN CONVERT(BIT,0)
						WHEN @CollectSystemSpids = N'N'							THEN CONVERT(BIT,0)
						WHEN r.command IS NULL										THEN CONVERT(BIT,0)
						WHEN r.command = N'RESOURCE MONITOR' 
							AND r.wait_type IS NULL									THEN CONVERT(BIT,0)
						WHEN r.command = N'RECOVERY WRITER' 
							AND ISNULL(r.wait_type,N'') = N'DIRTY_PAGE_POLL'		THEN CONVERT(BIT,0) 
						WHEN r.command = N'XE TIMER' 
							AND ISNULL(r.wait_type,N'') = N'XE_TIMER_EVENT'			THEN CONVERT(BIT,0)
						WHEN r.command = N'XE DISPATCHER' 
							AND ISNULL(r.wait_type,N'') = N'XE_DISPATCHER_WAIT'		THEN CONVERT(BIT,0)
						WHEN r.command = N'LAZY WRITER' 
							AND ISNULL(r.wait_type,N'') = N'LAZYWRITER_SLEEP'		THEN CONVERT(BIT,0)
						WHEN r.command = N'LOG WRITER' 
							AND ISNULL(r.wait_type,N'') = N'LOGMGR_QUEUE'			THEN CONVERT(BIT,0)
						WHEN r.command = N'LOCK MONITOR' 
							AND ISNULL(r.wait_type,N'') = N'REQUEST_FOR_DEADLOCK_SEARCH' THEN CONVERT(BIT,0)
						WHEN r.command = N'DB STARTUP'								THEN CONVERT(BIT,1) --for now, always want to know when master startup thread(s) are running --AND ISNULL(r.wait_type,'') = 'SLEEP_DBSTARTUP' THEN 1
						WHEN r.command = N'TASK MANAGER' 
							AND ISNULL(r.wait_type,N'') IN (N'',N'ONDEMAND_TASK_QUEUE') THEN CONVERT(BIT,0)
						WHEN r.command = N'TRACE QUEUE TASK' 
							AND ISNULL(r.wait_type,N'') IN 
							(N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 
							N'SQLTRACE_BUFFER_FLUSH')								THEN CONVERT(BIT,0)
						WHEN r.command = N'BRKR TASK' 
							AND ISNULL(r.wait_type,N'') IN (N'BROKER_TO_FLUSH',
							N'BROKER_TRANSMITTER',N'SLEEP_TASK',
							N'HADR_FILESTREAM_IOMGR_IOCOMPLETION')					THEN CONVERT(BIT,0)
						WHEN r.command = N'BRKR EVENT HNDLR' 
							AND ISNULL(r.wait_type,N'') = N'BROKER_EVENTHANDLER'	THEN CONVERT(BIT,0)
						WHEN r.command = N'CHECKPOINT' 
							AND ISNULL(r.wait_type,N'') = N'CHECKPOINT_QUEUE'		THEN CONVERT(BIT,0)
						WHEN r.command = N'SIGNAL HANDLER' 
							AND ISNULL(r.wait_type,N'') = N'KSOURCE_WAKEUP'			THEN CONVERT(BIT,0)
						WHEN r.command = N'FT FULL PASS' 
							AND ISNULL(r.wait_type,N'') = N'FT_IFTS_SCHEDULER_IDLE_WAIT' THEN CONVERT(BIT,0)
						WHEN r.command = N'FT CRAWL MON' 
							AND ISNULL(r.wait_type,N'') = N'FT_IFTS_SCHEDULER_IDLE_WAIT' THEN CONVERT(BIT,0)
						WHEN r.command = N'FT GATHERER' 
							AND ISNULL(r.wait_type,N'') = N'FT_IFTS_SCHEDULER_IDLE_WAIT' THEN CONVERT(BIT,0)
						WHEN r.command = N'FSAGENT TASK'
							AND ISNULL(r.wait_type,N'') = N'FSAGENT' THEN CONVERT(BIT,0)
						--"UNKNOWN TOKEN" pops up a lot, and really doesn't ever give us anything useful. So omit it entirely
						WHEN r.command = N'UNKNOWN TOKEN' THEN CONVERT(BIT,0)	
						/*
							AND ISNULL(r.wait_type,N'') IN 
							(N'FT_IFTSHC_MUTEX', N'SLEEP_TASK',
								N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 
								N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'--the last 2 are SQL 2014 waits
							)														THEN CONVERT(BIT,0)	
						*/
						WHEN r.command = N'SYSTEM_HEALTH_MONITOR' 
							AND ISNULL(r.wait_type,N'') = N'SP_SERVER_DIAGNOSTICS_SLEEP' THEN CONVERT(BIT,0)
						WHEN r.command = N'RECEIVE' 
							AND ISNULL(r.wait_type,N'') IN (N'',N'PREEMPTIVE_OS_REPORTEVENT') THEN CONVERT(BIT,0)
						WHEN r.command = N'GHOST CLEANUP' THEN CONVERT(BIT,1)
						--SQL 2014 tasks:
						WHEN r.command = N'XTP_CKPT_AGENT' 
							AND ISNULL(r.wait_type,N'') = N'WAIT_XTP_HOST_WAIT'		THEN CONVERT(BIT,0)
						WHEN r.command = N'XTP_THREAD_POOL' 
							AND ISNULL(r.wait_type,N'') = N'DISPATCHER_QUEUE_SEMAPHORE' THEN CONVERT(BIT,0)
						WHEN r.command = N'XTP_OFFLINE_CKPT' 
							AND ISNULL(r.wait_type,N'') = N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG' THEN CONVERT(BIT,0)
					ELSE 1
					END 
				),
			--see the definition of calc__tmr_wait for more info on why we're doing this.
			[calc__tmr_wait] = CASE WHEN s.is_user_process = 1 AND r.command = N'TM REQUEST'
								THEN (CASE WHEN ISNULL(r.wait_type,N'') = N'' THEN CONVERT(TINYINT,1)
										WHEN r.wait_type = N'WRITELOG' THEN CONVERT(TINYINT,2)
										WHEN r.wait_type = N'PREEMPTIVE_TRANSIMPORT' THEN CONVERT(TINYINT,3)
										WHEN r.wait_type = N'PREEMPTIVE_DTC_ENLIST' THEN CONVERT(TINYINT,4)
										WHEN r.wait_type = N'DTC_STATE' THEN CONVERT(TINYINT,5)
										WHEN r.wait_type = N'DTC' THEN CONVERT(TINYINT,6)
										WHEN r.wait_type = N'LOGBUFFER' THEN CONVERT(TINYINT,7)
										WHEN r.wait_type = N'TRANSACTION_MUTEX' THEN CONVERT(TINYINT,8)
										ELSE CONVERT(TINYINT,254)
										END)
								ELSE CONVERT(TINYINT, 0) END

		/* We use RIGHT OUTER JOIN and join hints to force the plan shape that we want. We want to ensure that the optimizer 
			pulls from the Dim tables first before it grabs anything from the DMVs. This assists in creating the illusion of 
			a true "point-in-time" snapshot of the DMVs (impossible to actually get in a changing system), since the dynamic
			content is accessed "closer together" in the query plan.

			The order that the DMVs are accessed roughly corresponds to how volatile they are. That is, we access DMVs that
			are highly volatile first, since more stable DMVs are likely to have the same contents for the extra few dozen
			milliseconds that it will take to get there in the query plan.

			Thus, through the use of ROJ, join hints, and placement, we get a query plan where the most volatile DMVs
			are captured to their hash bucket quickly, and the less volatile DMVs are captured to their hash bucket later,
			"towards the far lower right" of the query plan.
			
			Note also the use of @@CHIRHO_SCHEMA@@.AutoWho_CollectorOptFakeout. It is a simple 2 row table (values of 0 and 1) whose sole purpose
			is to allow us to NOT have a DMV in the very lowest-rightest position. If we had a DMV in that position, rows would 
			stream up to the upper-left from that DMV, but one at a time. That would increase the latency between the first GetRow()
			call to that DMV and the last, decreasing our illusion of a "point in time" snapshot of the system. Therefore, we
			use @@CHIRHO_SCHEMA@@.AutoWho_CollectorOptFakeout in that position instead, so that sys.dm_exec_sessions is pulled into a hash table
			all at once.

		*/
		FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
			RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna
			RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca
			RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa

			RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln
			RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimCommand dco
			RIGHT OUTER hash JOIN 
					(SELECT tsu.session_id, tsu.request_id,
						[num_tasks] = COUNT(*),
						[internal_objects_alloc_page_count] = SUM(tsu.internal_objects_alloc_page_count),
						[internal_objects_dealloc_page_count] = SUM(tsu.internal_objects_dealloc_page_count),
						[user_objects_alloc_page_count] = SUM(tsu.user_objects_alloc_page_count),
						[user_objects_dealloc_page_count] = SUM(tsu.user_objects_dealloc_page_count) 
					FROM sys.dm_db_task_space_usage tsu 
					WHERE tsu.database_id = 2
					GROUP BY tsu.session_id, tsu.request_id
					) tsu

						RIGHT OUTER hash JOIN	--Join Clause #1
							(SELECT session_id, 
								request_id, 
								request_time, 
								grant_time,  
								requested_memory_kb, 
								required_memory_kb, 
								granted_memory_kb, 
								used_memory_kb, 
								max_used_memory_kb, 
								dop, 
								[rn] = ROW_NUMBER() OVER (PARTITION BY session_id, request_id ORDER BY request_time DESC)
								FROM sys.dm_exec_query_memory_grants) mg

							RIGHT OUTER hash JOIN 	--Join Clause #2
								sys.dm_exec_requests r	
									ON mg.session_id = r.session_id		--#ON for Join Clause #2
									AND mg.request_id = r.request_id
									AND mg.rn = 1		--since we are not guaranteed transactional consistency or constraints on the data (it is coming from
														-- transient DMVs), we use the ROW_NUMBER() function combined with the filter on mg.rn=1 to get rid of Dups
		
							ON r.session_id = tsu.session_id			--#ON for Join Clause #1
							AND r.request_id = tsu.request_id

							--the above 3 DMVs are probably the most transient, hence our structuring of the query to capture them first (via the blocking side of a hash join)

						RIGHT OUTER hash JOIN --#3
						--We pull data from sysprocesses for a couple of reasons:
						--		1. it has the # of trans open for a SPID
						--		2. It has the database context that the SPID is executing in (the DMVs do not have this info until SQL 2012)
							(SELECT spid, [dbid], open_tran 
								FROM master.dbo.sysprocesses
								WHERE ecid = 0		--for parallel queries, it appears that this view will have open_tran = 1 for the parent, and = 0 for the children
							) sysproc
			
							RIGHT OUTER hash JOIN --#4
								sys.dm_db_session_space_usage ssu 
		
								RIGHT OUTER hash JOIN --#5
									sys.dm_exec_connections c

									RIGHT OUTER hash JOIN --#6
										sys.dm_exec_sessions s
										RIGHT OUTER hash JOIN 
											@@CHIRHO_SCHEMA@@.AutoWho_CollectorOptFakeout cof
											ON cof.ZeroOrOne = s.is_user_process
										ON s.session_id = c.session_id		--ON for #6
										AND c.parent_connection_id IS NULL	--MARS connections will have multiple rows in the view that we really do not care about
										AND c.session_id >= 0		--another dummy clause for the optimizer to affect cardinality estimates

								ON s.session_id = ssu.session_id	--ON for #5
								AND ssu.database_id = 2
								AND ssu.session_id >= 0		--another dummy clause for the optimizer
							ON s.session_id = sysproc.spid		--ON for #4
							AND sysproc.spid >= 0	--The optimizer tends to way-overestimate the resulting cardinality of this join. 
												--(since SQL does not have stats on the data (b/c it is a DMV, of course)
												--Thus, we throw in a functionally-redundant filter to help calm its estimates down. 
												-- The same approach has been used several other times in this query.
						ON s.session_id = r.session_id		--ON for #3

			ON dco.command = r.command		--BOL: r.command is NOT nullable, but of course idle sessions will have a NULL value here

			ON dln.login_name = s.login_name					--BOL: NOT nullable
			AND dln.original_login_name = s.original_login_name	--BOL: NOT nullable

			ON dsa.endpoint_id = s.endpoint_id			--BOL: NOT nullable
			AND dsa.transaction_isolation_level = s.transaction_isolation_level		--BOL: NOT nullable
			AND dsa.[deadlock_priority] = s.deadlock_priority		--BOL: NOT nullable
			AND dsa.group_id = s.group_id				--BOL: NOT nullable
			AND dsa.[host_name] = ISNULL(s.host_name,@lv__nullstring)			--BOL: null for internal sessions
			AND dsa.[program_name] = ISNULL(s.program_name,@lv__nullstring)		--BOL: null for internal sessions
			AND dsa.client_version = ISNULL(s.client_version,@lv__nullint)	--BOL: null for internal sessions
			AND dsa.client_interface_name = ISNULL(s.client_interface_name,@lv__nullstring)		--BOL: null for internal sessions

			ON dca.net_transport = c.net_transport					--BOL: NOT nullable
			AND dca.node_affinity = c.node_affinity					--BOL: NOT nullable
			AND dca.encrypt_option = c.encrypt_option				--BOL: NOT nullable
			AND dca.auth_scheme = c.auth_scheme						--BOL: NOT nullable
			AND dca.protocol_type = ISNULL(c.protocol_type,@lv__nullstring)				--BOL: yes, NULLABLE
			AND dca.protocol_version = ISNULL(c.protocol_version,@lv__nullint)			--BOL: yes, NULLABLE
			AND dca.endpoint_id = ISNULL(c.endpoint_id,@lv__nullint)					--BOL: yes, NULLABLE
			AND dca.net_packet_size = ISNULL(c.net_packet_size,@lv__nullint)			--BOL: yes, NULLABLE

			ON dna.client_net_address = c.client_net_address		--BOL: yes, is NULLABLE
			AND dna.local_net_address = ISNULL(c.local_net_address,@lv__nullstring)			--BOL: yes, is NULLABLE
			AND dna.local_tcp_port = ISNULL(c.local_tcp_port,@lv__nullint)				--BOL: yes, is NULLABLE

			ON dwt.wait_type = r.wait_type		--BOL: yes, is NULLABLE
			AND dwt.latch_subtype = CASE WHEN r.wait_type LIKE N'LATCH%'
									THEN (CASE WHEN wait_resource IS NULL THEN N'' 
											ELSE SUBSTRING(wait_resource, 1, CHARINDEX(' ', ISNULL(wait_resource,N' '))-1)
											END) 
									ELSE N'' END
	) withdims
	WHERE sess__is_user_process = 0		--Even though we calculate whether system spids are interesting or not in this
											--query (above, in the calc__sysspid_isinteresting field), we leave them in as captured
											--in case they are blocking. We could re-work our logic later so that we leave non-interesting
											-- system spids out unless they are blocking an in-scope spid
											--the main reason I've left them in is because they technically have running requests,
											-- and the query below that pulls in blockers that weren't in the original set assumes
											-- that those spids lack a running request.

	--actively-running are always captured
	--NOTE: at this point in the query, null has been handled: OR rqst__request_id IS NOT NULL		
	OR rqst__request_id <> @lv__nullsmallint

	--we always capture idle w/tran since they can be blockers. (idle w/o tran can be blockers in rare cases, see below)
	-- we'll use the scope logic below to exclude idle w/tran if @IncludeIdleWithTran = N'N'
	OR sess__open_transaction_count > 0		--idle, has open tran

	OR (@IncludeIdleWithoutTran = N'Y')	--if idle w/o tran = 'Y', causes every spid to be captured
	OR tempdb__CalculatedCurrentTempDBUsage_pages >= @lv__TempDBUsage_pages
	OPTION(MAXDOP 1, FORCE ORDER)
	;

	SET @lv__SAR_numrecords = @@ROWCOUNT;

	--print '#recs from SarInit: ' + isnull(convert(varchar(20), @lv__SAR_numrecords),'<null>');

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'SARinit:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END

	SET @errorloc = N'TAW Population';

	SET @lv__MemGrantFake1 = 2147483647;
	SET @lv__MemGrantFake2 = 2147483647;		--for use in our TOP @ logic below

	INSERT INTO #tasks_and_waits (
		[task_address],
		[parent_task_address],
		[session_id],
		[request_id],
		[exec_context_id],
		[tstate],
		[scheduler_id],
		[context_switches_count],
		[wait_type],
		[wait_latch_subtype],
		[wait_duration_ms],
		[wait_special_category],
		[wait_order_category],
		[wait_special_number],
		[wait_special_tag],
		[task_priority],
		[blocking_task_address],
		[blocking_session_id],
		[blocking_exec_context_id],
		[resource_description],
		[resource_dbid],
		[resource_associatedobjid]
	)
		SELECT 
			task_address,
			parent_task_address,
			session_id,
			request_id, 
			exec_context_id, 
			tstate,
			scheduler_id,
			context_switches_count, 
			wait_type,
			wait_latch_subtype,
			wait_duration_ms,
			wait_special_category,
			wait_order_category,

			--A multi-purpose numeric value that lets us store info we extract from the waiting_tasks fields, and that
			-- is context-sensitive based on the actual wait_type value
			--		lock wait types --> the sub-type of lock
			--		cxpacket		--> the node id
			--		page/io latch	--> the file id	(since the resource_dbid and the resource_assocobjid [which holds page id] have the other 2 parts covered)
			wait_special_number = (
					CASE WHEN wait_special_category = @enum__waitspecial__cxp
							THEN (CASE 
									WHEN CHARINDEX(N'nodeid=', resource_description) <= 0 THEN CONVERT(INT,@lv__nullint)
									ELSE CONVERT(INT, 
												SUBSTRING(resource_description, 
													CHARINDEX(N'nodeid=', resource_description)+7, --starting point

													--ending point is at the next space
													-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
													ISNULL(
														NULLIF(CHARINDEX(N' ', 
																SUBSTRING(resource_description, 
																	CHARINDEX(N'nodeid=', resource_description)+7,
																	--There should be a space (or the end of the string) within the next 100 characters :-)
																	100
																	)
																), 
																0		--NULL IF = 0
															)
															, 50
														)
													)
												)
									END)
						WHEN wait_special_category = @enum__waitspecial__lck	--TODO: do I need to LOWER() the below resource_description?
							THEN (CASE WHEN resource_description LIKE N'%keylock%' THEN		CONVERT(INT,1)		-- N'KEY'
									WHEN resource_description LIKE N'%ridlock%' THEN		CONVERT(INT,2)		-- N'RID'
									WHEN resource_description LIKE N'%pagelock%' THEN		CONVERT(INT,3)		-- N'PAGE'
									WHEN resource_description LIKE N'%objectlock%' THEN		CONVERT(INT,4)		-- N'OBJECT'
									WHEN resource_description LIKE N'%applicationlock%' THEN CONVERT(INT,5)		-- N'APP'
									WHEN resource_description LIKE N'%hobtlock%' THEN		CONVERT(INT,6)		-- N'HOBT'
									WHEN resource_description LIKE N'%allocunitlock%' THEN  CONVERT(INT,7)		-- N'ALLOCUNIT'
									WHEN resource_description LIKE N'%databaselock%' THEN	CONVERT(INT,8)		-- N'DB'
									WHEN resource_description LIKE N'%filelock%' THEN		CONVERT(INT,9)		-- N'FILE'
									WHEN resource_description LIKE N'%extentlock%' THEN		CONVERT(INT,10)		-- N'EXTENT'
									WHEN resource_description LIKE N'%metadatalock%' THEN	CONVERT(INT,11)		-- N'META'
								END)

						WHEN wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked)
							THEN (CASE WHEN CHARINDEX(N':', resource_description) > 0 
									THEN SUBSTRING(
											SUBSTRING(resource_description, CHARINDEX(':',resource_description)+1, 1000), 
											1,
											CHARINDEX(':',SUBSTRING(resource_description, CHARINDEX(':',resource_description)+1, 1000))-1
											)
									ELSE CONVERT(INT,@lv__nullint)
									END)
						ELSE CONVERT(INT,@lv__nullint)
					END
				),

			--A multi-purpose string field that lets us store info we extract from the waiting_tasks fields, and that
			-- is context-sensitive based on the actual wait_type value
			--		lock wait types --> the mode from resource_description
			--		cxpacket		--> the CXPACKET wait sub-type
			--		page/io latch	--> for now, we put the Dbid:fileId:pageId string value here, so that when we run our 
			--								page-resolution logic (DBCC PAGE WITH TABLE_RESULTS), we can just REPLACE to a comma and go
			--							we'll put the results of that DBCC PAGE call into this field in the format IndexId (as a string)
			wait_special_tag = (
					CASE WHEN wait_special_category = @enum__waitspecial__cxp
							THEN (
									--TODO: ugh, I hate the fact that I have to call LOWER this many times, but 
									-- on a case-sensitive server collation, the logic won't work unless I do b/c
									-- the wait subtypes are GetRow, NewRow, etc.
									CASE WHEN LOWER(resource_description) LIKE N'%getrow%' THEN N'GetRow'
										WHEN LOWER(resource_description) LIKE N'%portopen%' THEN N'PortOpen'
										WHEN LOWER(resource_description) LIKE N'%newrow%' THEN N'NewRow'
										WHEN LOWER(resource_description) LIKE N'%portclose%' THEN N'PortClose'
										WHEN LOWER(resource_description) LIKE N'%synchronize%' THEN N'SynchConsumer'
										WHEN LOWER(resource_description) LIKE N'%range%' THEN N'Range'
									ELSE N'?'
									END)
						WHEN wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked)
							THEN resource_description
						WHEN wait_special_category = @enum__waitspecial__lck
							THEN (CASE WHEN CHARINDEX(N'mode=', resource_description) > 0 
									THEN SUBSTRING(resource_description, 
													CHARINDEX(N'mode=', resource_description)+5, --starting point

													--ending point is at the next space
													-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
													ISNULL(
														NULLIF(CHARINDEX(N' ', 
																SUBSTRING(resource_description, 
																	CHARINDEX(N'mode=', resource_description)+5, 
																	--There should be a space (or the end of the string) within the next 100 characters :-)
																	100
																	)
																), 
																0
															)
															, 50
														)
													)
									ELSE @lv__nullstring
									END)
							ELSE N''
						END
				),

			[task_priority] = ROW_NUMBER() OVER (PARTITION BY session_id, request_id		-- This field is for the blocking tree functionality
												ORDER BY wait_order_category ASC, wait_duration_ms DESC	--we want "1" to represent the very top row... the wait record 
												),														-- that we'll display when we construct the blocking tree text
			blocking_task_address,
			blocking_session_id, 
			blocking_exec_context_id, 
			resource_description,
			[resource_dbid] = (
					CASE 
						WHEN wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked)
						THEN (CASE WHEN CHARINDEX(N':', resource_description) > 0 
											THEN CONVERT(INT,SUBSTRING(resource_description, 1, CHARINDEX(N':', resource_description)-1))
										ELSE CONVERT(INT,@lv__nullint)
									END)
						WHEN wait_special_category = @enum__waitspecial__lck
							THEN (CASE WHEN CHARINDEX(N'dbid=', resource_description) > 0 
										THEN CONVERT(INT,SUBSTRING(resource_description, 
														CHARINDEX(N'dbid=', resource_description)+5, --starting point

														--ending point is at the next space
														-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
														ISNULL(
															NULLIF(CHARINDEX(N' ', 
																	SUBSTRING(resource_description, 
																		CHARINDEX(N'dbid=', resource_description)+5, 
																		--There should be a space (or the end of the string) within the next 100 characters :-)
																		100
																		)
																	), 
																	0
																)
																, 50
															)
														)
													)
									ELSE CONVERT(INT,@lv__nullint)
									END)
						ELSE CONVERT(INT,@lv__nullint)
					END),
			[resource_associatedobjid] = (
					CASE 
						--for latch waits, leverage the "objid" field and place our page # there.
						WHEN wait_special_category IN (@enum__waitspecial__pg, @enum__waitspecial__pgio, @enum__waitspecial__pgblocked)
							THEN (
								CASE WHEN CHARINDEX(N':', resource_description) > 0
									THEN CONVERT(BIGINT,REVERSE(SUBSTRING(REVERSE(resource_description),
											1,
											CHARINDEX(N':', REVERSE(resource_description))-1
											)))
									ELSE CONVERT(BIGINT,@lv__nullint)
								END
							)
						WHEN wait_special_category = @enum__waitspecial__lck
							THEN (CASE   --pull out file id for these 2 lock types
										WHEN resource_description LIKE N'%filelock%' OR resource_description LIKE N'%extentlock%' 
										THEN ( CASE WHEN CHARINDEX(N'fileid=', resource_description) > 0 
													THEN CONVERT(BIGINT, SUBSTRING(resource_description, 
															CHARINDEX(N'fileid=', resource_description)+7, --starting point

															--ending point is at the next space
															-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
															ISNULL(
																NULLIF(CHARINDEX(N' ', 
																		SUBSTRING(resource_description, 
																			CHARINDEX(N'fileid=', resource_description)+7, 
																			--There should be a space (or the end of the string) within the next 100 characters :-)
																			100
																			)
																		), 
																		0
																	)
																	, 50
																)
															)
														)
													ELSE CONVERT(BIGINT,@lv__nullint)
													END)
										--pull out hobtid for these 2 lock types
										WHEN resource_description LIKE N'%hobtlock%' OR resource_description LIKE N'%allocunitlock%'
										THEN ( CASE WHEN CHARINDEX(N'hobtid=', resource_description) > 0 
													THEN CONVERT(BIGINT, SUBSTRING(resource_description, 
															CHARINDEX(N'hobtid=', resource_description)+7, --starting point

															--ending point is at the next space
															-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
															ISNULL(
																NULLIF(CHARINDEX(N' ', 
																		SUBSTRING(resource_description, 
																			CHARINDEX(N'hobtid=', resource_description)+7, 
																			--There should be a space (or the end of the string) within the next 100 characters :-)
																			100
																			)
																		), 
																		0
																	)
																	, 50
																)
															)
														)
													ELSE CONVERT(BIGINT,@lv__nullint)
													END)
									--for everything else, search for associatedObjectId
									WHEN CHARINDEX(N'associatedobjectid=', resource_description) > 0 
										THEN CONVERT(BIGINT, SUBSTRING(resource_description, 
														CHARINDEX(N'associatedobjectid=', resource_description)+19, --starting point

														--ending point is at the next space
														-- Or, if there is no space (because the string ends), then we just grab 50 characters worth:
														ISNULL(
															NULLIF(CHARINDEX(N' ', 
																	SUBSTRING(resource_description, 
																		CHARINDEX(N'associatedobjectid=', resource_description)+19, 
																		--There should be a space (or the end of the string) within the next 100 characters :-)
																		100
																		)
																	), 
																	0
																)
																, 50
															)
														)
													)
									ELSE CONVERT(BIGINT,@lv__nullint)
									END)
							ELSE CONVERT(BIGINT,@lv__nullint)
					END)
		FROM (
			SELECT 
				tsk.task_address,
				tsk.parent_task_address,
				tsk.session_id, 
				tsk.request_id, 
				tsk.exec_context_id, 
				tsk.tstate,
				tsk.scheduler_id,
				tsk.context_switches_count,
				wtsk.blocking_task_address,
				wtsk.blocking_session_id, 
				blocking_exec_context_id = CASE WHEN wtsk.blocking_task_address = tsk.parent_task_address THEN 0 ELSE wtsk.blocking_exec_context_id END, 
				wait_duration_ms = ISNULL(wtsk.wait_duration_ms,0), 
				[wait_type] = ISNULL(wtsk.wait_type,@lv__nullstring), 
				wait_latch_subtype = ISNULL(wait_latch_subtype,N''),
				[wait_special_category] = ISNULL(wtsk.wait_special_category,@enum__waitspecial__none),
				wtsk.resource_description,

				--useful when we have parallel queries and multiple waits; we need some sort of order to determine which will show up
				-- if we aren't displaying them all.
				[wait_order_category] = CASE WHEN wtsk.waiting_task_address IS NULL THEN @enum__waitorder__none
								WHEN wtsk.wait_special_category IN (@enum__waitspecial__pgblocked, @enum__waitspecial__latchblocked) THEN @enum__waitorder__latchblock
								WHEN wtsk.wait_special_category = @enum__waitspecial__lck THEN @enum__waitorder__lck
								WHEN wtsk.wait_special_category IN (@enum__waitspecial__pgio, @enum__waitspecial__pg) THEN @enum__waitorder_pglatch 
								WHEN wtsk.wait_special_category = @enum__waitspecial__cxp THEN @enum__waitorder__cxp
								ELSE @enum__waitorder__other
							END
			FROM 
				(SELECT TOP (@lv__MemGrantFake1)
					t.task_address,
					t.parent_task_address, 
					[session_id] = CONVERT(SMALLINT,ISNULL(t.session_id,-998)), 
					[request_id] = convert(SMALLINT,ISNULL(t.request_id,@lv__nullsmallint)), 
					[exec_context_id] = CONVERT(SMALLINT,ISNULL(t.exec_context_id,@lv__nullsmallint)), 
					tstate = CASE t.task_state
								WHEN N'SUSPENDED' THEN N'S'
								WHEN N'RUNNING' THEN N'R'
								WHEN N'DONE' THEN N'D'
								WHEN N'RUNNABLE' THEN N'A'
								WHEN N'PENDING' THEN N'P'
								WHEN N'SPINLOOP' THEN N'L'
								ELSE N'?'
								END,
					t.scheduler_id, 
					context_switches_count = ISNULL(t.context_switches_count,0)
				FROM sys.dm_os_tasks t
				WHERE t.task_state <> N'DONE'
				-- can't do this next clause, as we want to be able to track the # of 
				-- requests that haven't obtained a SPID yet, and are in THREADPOOL wait, but
				-- we can't identify those tasks until we join to the waiting tasks DMV: AND t.session_id IS NOT NULL 
				) tsk

				LEFT OUTER hash JOIN (
					SELECT TOP (@lv__MemGrantFake2)
						wt.waiting_task_address, 
						session_id = CONVERT(SMALLINT,ISNULL(wt.session_id,-998)),
						blocking_task_address, 
						blocking_session_id = CONVERT(SMALLINT,NULLIF(wt.blocking_session_id,wt.session_id)), 
						blocking_exec_context_id = CONVERT(SMALLINT,wt.blocking_exec_context_id),
						wt.wait_duration_ms,
						[wait_special_category] = (	--making categories makes comparison logic in this proc and in display logic; the numerical order isn't meaningful at this time
								CASE WHEN wait_type IS NULL THEN @enum__waitspecial__none
									WHEN wait_type LIKE N'LCK%' THEN @enum__waitspecial__lck

									--if the task is blocked, and it isn't a lock wait (otherwise it would have qualified for the immediate-previous WHEN),
									-- then it must be one of the latch waits that can have blocking info (most common with page/pageio, but I believe also
									-- possible with other latch types)
									WHEN NULLIF(wt.blocking_session_id,wt.session_id) IS NOT NULL AND wait_type LIKE N'PAGE%LATCH' THEN @enum__waitspecial__pgblocked
									WHEN NULLIF(wt.blocking_session_id,wt.session_id) IS NOT NULL THEN @enum__waitspecial__latchblocked
									WHEN wait_type LIKE N'PAGEIOLATCH%' THEN @enum__waitspecial__pgio
									WHEN wait_type LIKE N'PAGELATCH%' THEN @enum__waitspecial__pg
									WHEN wait_type LIKE N'LATCH%' THEN @enum__waitspecial__latch
									WHEN wait_type LIKE N'CXP%' THEN @enum__waitspecial__cxp
									ELSE @enum__waitspecial__other
								END
							),
						wait_type,
						wait_latch_subtype = CASE WHEN wait_type LIKE N'LATCH%' 
										THEN (CASE WHEN resource_description IS NULL THEN N'' 
											ELSE --old logic: SUBSTRING(resource_description, 1, CHARINDEX(' ', resource_description)-1) + REPLACE(wait_type, 'LATCH_', '(') + ')'
												SUBSTRING(resource_description, 1, CHARINDEX(' ', resource_description)-1)
											END )
									ELSE N'' END,
						--reconsider this later: CONVERT(nvarchar(500),LOWER(resource_description)) as resource_description	--truncate to 500 chars for mem grant purposes
						[resource_description] = LTRIM(RTRIM(wt.resource_description))
					FROM sys.dm_os_waiting_tasks wt 
				) wtsk
					ON tsk.task_address = wtsk.waiting_task_address
					--The estimated cardinality explodes after the join between the 2 subqueries, so the 2 clauses below help to keep the optimizer's
					-- estimations a bit more realistic, while having no semantic effect on the query
					AND tsk.session_id = wtsk.session_id
					-- UPDATE: no longer correct, as null requests are now set to @lv__nullsmallint: AND tsk.request_id >= 0
					-- if we need to add another clause for cardinality estimation control, we'll have to utilize something else.
		) t_and_w_base
	OPTION(OPTIMIZE FOR (@lv__MemGrantFake1 = 700, @lv__MemGrantFake2 = 700),		--optimize for 700 so we don't have a huge memory grant. Real value of both is MAXINT
		MAXDOP 1, FORCE ORDER);


	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'TAWinit:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END
/*
	 ****     ****   ****    ****   ****
	*        *      *    *   *   *  *
	 ****   *      *      *  ****   ****
	     *   *      *    *   *      *
	 ****     ****   ****    *      ****

	 Based on the input parameters and the attributes of the sessions/requests/tasks, determine which is "in-scope".

	 First, we need to determine what stuff is blocking
*/

/*
There are a number of points worth noting re: the below scoping queries:

	1) The weird way of joining these tables below is intentional: 
		the Right Outer Joins allow us to force a hash match, with the hash tables being built on the much smaller derived tables (the 2 
		references to #TaskSnapshot). This gives us a "Data Warehouse-style plan shape, where the 
		the choice to put the "ON s.sess__session_id = ListOfBlockers.blocker_session_id" clause (to finish the join criteria between the
		#SpidMon_Sessions table and the ListOfBlockers derived table) at the very end of the FROM section is also intentional. The alternative
		would be to put the join between #SpidMon_sessions and one of the derived tables into a derived table, something like:

		UPDATE #SpidMon_Sessions
		FROM 
			( #TaskSnapshot) ListOfBLockers
				RIGHT OUTER JOIN 
				(
					(#TaskSnapshot) blockedRequests
						RIGHT OUTER JOIN
							#SpidMon_sessions
								ON blah blah
				) myDerivedTable
					ON blah blah

		The problem with this approach is that the "UPDATE" portion of the statement cannot "see" the #SpidMon_sessions table reference. 
		The "line of sight" to that reference has been blocked, as it were. Thus, we would have to join in #SpidMon_Sessions AGAIN 
		in order for the UPDATE portion to be able to "see" the table that it is updating. This means a second reference to #SpidMon_Sessions,
		and thus an extra join, and thus a slower query.

	2) We let the Waiting Tasks snapshot drive which spids are actually blocked rather than the dm_exec_requests DMV,
		since this is more accurate for parallel queries. Note that since the below statement assigns blocking spid information 
		without taking into account whether the blocked task is actually the task that has been waiting the longest, we could 
		assign a "blocked" status to a spid that has actually been waiting longer on something else. For example, a parallel query 
		could have 1 task that has been waiting on a PAGEIOLATCH type for 230 ms (a really slow disk IO), and have 
		another task that has been waiting only 80 ms for a lock that another SPID has. In these scenarios, we report 
		the spid as blocked even though the worst wait is actually not a blocking scenario. This will typically not 
		be a problem b/c most blocking scenarios will either resolve themselves quickly (when the app is programmed decently) 
		or will quickly become the longest wait for any task in a parallel query. 
*/
	SET @errorloc = N'Scope Query';

	UPDATE s
	SET 
		calc__block_relevant = (
			CASE WHEN ListOfBlockers.blocker_session_id IS NOT NULL 
						OR blockedRequests.blocked_session_id_blocking_spid IS NOT NULL 
						--UPDATE: insert of -997 spid has been moved further down the proc:
						-- OR s.sess__session_id = -997		--special "spid" for the blocking chain
				THEN CONVERT(TINYINT,1)
				ELSE CONVERT(TINYINT,0)
			END),
		calc__is_blocker = (CASE WHEN ListOfBlockers.blocker_session_id IS NOT NULL THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END),
		calc__blocking_session_id = blockedRequests.blocked_session_id_blocking_spid,
		calc__threshold_ignore = CASE WHEN threshignore.FilterID IS NOT NULL THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END,
		calc__return_to_user = (
			CASE 
				--Next, handle exclusion rules... if the user does not want to see them, then the user doesn't see them. :-)
				WHEN s.sess__session_id = @@SPID 
					AND @HideSelf = N'Y' 
						THEN CONVERT(SMALLINT,-1)		--exclusion reason: isSelf
				-- we don't include or filter by SPID in our automated version of this logic
				--WHEN @lv__SPIDInclusionsExist =  1
				--		AND sint.SPIDNumber IS NULL			--Current SPID isn't in the SPID inclusion list... thus, doesn't make the cut.
				--		THEN -2		
				--WHEN sxt.SPIDNumber IS NOT NULL --SPID joins with our SPID exclusion table, meaning user has explicitly excluded this SPID #
				--	THEN -3		
				WHEN @DBInclusionsExist = CONVERT(BIT,1)
						AND dint.FilterID IS NULL			--The DB Context for the SPID is not in our list of DBs to include... spid doesn't make the cut.
						THEN CONVERT(SMALLINT,-4)
				WHEN dxt.FilterID IS NOT NULL				-- The DB Context for the SPID has been explicitly excluded by the user
					THEN CONVERT(SMALLINT,-5)

				--inclusion reason code #1: amount of TempDB utilized is >= a hard-coded constant
				WHEN ISNULL(tempdb__CalculatedCurrentTempDBUsage_pages,0) >= @lv__TempDBUsage_pages
					THEN CONVERT(SMALLINT,1)

				--Inclusion reason code #2: SPID has used >= a certain threshold of one of the "diff" resources (cpu, physical reads, writes, context switches)
				--Diff logic has been removed for the auto-version of this logic

				--reason code #3: state of system spid is such that it is considered "interesting"
				WHEN 
					(s.sess__is_user_process = 0
					AND s.sess__session_id > 0		--not a "special" spid

					AND 
						(	--capture system spids if they are progressing on something
							CONVERT(DECIMAL(15,12),ISNULL(s.rqst__percent_complete, 0.0)) > CONVERT(DECIMAL(15,12),0)
						OR  --or if they are in an unexpected status
							--old version when we used literal strings directly: 
							--   ISNULL(s.rqst__status,'norequest') NOT IN ('background','sleeping', 'norequest')
							ISNULL(s.rqst__status_code, 254) NOT IN (0, 3, -1)

						OR	--system spids that are blocked are always included.
							ISNULL(blockedRequests.blocked_session_id_blocking_spid,0) <> 0
						OR  -- if the system spid is blocking others, include it
							ListOfBlockers.blocker_session_id IS NOT NULL

						--or if known types of system spids have an unexpected wait type
						OR calc__sysspid_isinteresting = CONVERT(BIT,1) 
						)
					)
					THEN CONVERT(SMALLINT,3)		--reason code: system spid is "interesting"

				--reason code #4: user spid passes various criteria
				WHEN 
					(s.sess__is_user_process = 1
					AND 1 = (CASE 
								WHEN 
									-- (For actively-running SPIDs only) The duration of the currently-running query is less than our requested threshold
									s.rqst__request_id <> @lv__nullsmallint
									AND @DurationFilter > s.calc__duration_ms
									THEN CONVERT(SMALLINT,6)
								--For idle spids, if there is a @DurationFilter value, then we hide any spids that have been idle for LESS time
								-- than that value.
								WHEN 
									s.rqst__request_id = @lv__nullsmallint
									AND @DurationFilter > s.calc__duration_ms
									THEN CONVERT(SMALLINT,-7)
								WHEN @IncludeIdleWithTran = N'N'
										AND s.rqst__request_id = @lv__nullsmallint
										AND s.sess__open_transaction_count > 0
									THEN CONVERT(SMALLINT,-8)
								WHEN @IncludeIdleWithoutTran = N'N'
									AND s.rqst__request_id = @lv__nullsmallint
									AND s.sess__open_transaction_count = 0
									THEN CONVERT(SMALLINT,-9)
							ELSE CONVERT(SMALLINT,1)		--catchall: include
							END
							)
					)
					THEN CONVERT(SMALLINT,4)		--reason code: user spid passed the various criteria
				ELSE 
					s.calc__return_to_user		--pass the buck; but this case shouldn't ever happen if we've written the above logic correctly.
			END
		)
	FROM
		@FilterTable threshignore
		RIGHT OUTER hash JOIN
			@FilterTable dxt	--1. 
			RIGHT OUTER hash JOIN
				@FilterTable dint	--2. 
				RIGHT OUTER hash JOIN 
					(SELECT DISTINCT 
						[blocker_session_id] = t.blocking_session_id
					FROM #tasks_and_waits t 
					WHERE t.blocking_session_id IS NOT NULL --remember, we've already set blocking_spid to null when it = session_id (cxpacket waits)
					AND t.task_priority = 1		--we calculated the "most important" task when we populated taw, reuse that here
					) as ListOfBlockers								--5. 

					RIGHT OUTER hash JOIN

						(SELECT 
							[blocked_session_id] = session_id, 
							[blocked_request_id] = request_id, 
							[blocked_session_id_blocking_spid] = blocking_session_id
							FROM #tasks_and_waits t 
							WHERE t.blocking_session_id IS NOT NULL
							AND t.task_priority = 1
						) blockedRequests												--6.

						RIGHT OUTER hash JOIN #sessions_and_requests s
								ON blockedRequests.blocked_session_id = s.sess__session_id		--6. 
								AND blockedRequests.blocked_request_id = s.rqst__request_id

						ON s.sess__session_id = ListOfBlockers.blocker_session_id		--5. 

					ON dint.FilterID = s.sess__database_id	--2. 
					AND dint.FilterType = CONVERT(TINYINT,0)	--inclusion code
				ON dxt.FilterID = s.sess__database_id		--1. 
				AND dxt.FilterType = CONVERT(TINYINT,1)	--exclusion code
			ON threshignore.FilterID = s.sess__session_id
			AND threshignore.FilterType = CONVERT(TINYINT,128)	--threshold code
	OPTION(FORCE ORDER, MAXDOP 1, KEEPFIXED PLAN);

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'Scope:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END

	--select * from #sessions_and_requests order by sess__session_id;
	--select * from #tasks_and_waits taw order by taw.session_id

	--We have just scoped (i.e. defined whether the spid will be kept or not) every spid that our initial capture query obtained.
	-- However, there are 2 possible gaps here:
	--		1. @IncludeIdleWithoutTran was set to N, so no idle-without-tran spids were captured, but an idle spid is blocking
	--			an active spid. As far as I know, this can only happen when an active spid is trying to execute a command that is
	--			not compatible with a shared DB lock (i.e. the type of lock even idle spids have). Thus, it should be rare, typically
	--			happening with major operations like detaching a DB, putting a DB in single-user mode, etc.

	--		2. An active batch is blocked by a spid that has been excluded due to filtering or exclusion rules. For example, this 
	--			could happen if the blocker was executing in a context of a DB that is in the @FilterTable tabvar, or if the 
	--			blocker had only been running its current query for a few seconds (i.e. < the @DurationFilter value).
	-- In either case, we want to include the blocker

	SET @errorloc = N'Resurrect OutOfScope Blockers';

	--This takes care of case #2:
	UPDATE s1 
		SET calc__return_to_user = 99,		--code for "brought back in"
			calc__threshold_ignore = CASE WHEN threshignore.FilterID IS NOT NULL THEN 1 ELSE 0 END
	FROM 
		@FilterTable threshignore
		RIGHT OUTER hash JOIN
			#sessions_and_requests s1
			INNER hash JOIN #sessions_and_requests s2
				ON s1.sess__session_id = s2.calc__blocking_session_id
				AND s2.calc__return_to_user > 0
			ON threshignore.FilterID = s1.sess__session_id
			AND threshignore.FilterType = CONVERT(TINYINT,128)
	WHERE s1.calc__return_to_user <= 0
	OPTION(MAXDOP 1, KEEPFIXED PLAN, FORCE ORDER);

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'Resurrect:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END


	SET @errorloc = N'Missing Idle Blockers';
	--below takes care of #1
	IF @IncludeIdleWithoutTran <> N'Y' AND EXISTS (SELECT 1
				FROM #sessions_and_requests blockedspid
					LEFT OUTER hash JOIN #sessions_and_requests blockernotcaptured
						ON blockedspid.calc__blocking_session_id = blockernotcaptured.sess__session_id
				WHERE blockedspid.calc__blocking_session_id > 0
				AND blockernotcaptured.sess__session_id IS NULL		--the blocker isn't present at all in #sar
				)
	BEGIN
		INSERT INTO #sessions_and_requests (
			--core identifier fields & important attributes
			[sess__session_id],				--1
			[rqst__request_id],
			[TimeIdentifier],

			--session attributes
			[sess__login_time],
			[sess__host_name],				--5
			[sess__program_name],
			[sess__host_process_id],
			[sess__client_version],
			[sess__client_interface_name],
			[sess__login_name],				--10
			[sess__status_code],
			--[sess__status] [nvarchar](30) NULL,					
																/* BOL: Possible values [and the code we use to stand-in to reduce the table row length]:
																			0 --> Running - Currently running one or more requests
																			1 --> Sleeping - Currently running no requests
																			2 --> Dormant – Session has been reset because of connection pooling and is now in prelogin state.
																			3 --> Preconnect - Session is in the Resource Governor classifier.
																*/
			[sess__cpu_time],
			[sess__memory_usage],
			[sess__total_scheduled_time],
			[sess__total_elapsed_time],		--15
			[sess__endpoint_id],
			[sess__last_request_start_time],
			[sess__last_request_end_time],
			[sess__reads],
			[sess__writes],					--20
			[sess__logical_reads],
			[sess__is_user_process],
			[sess__transaction_isolation_level],
			[sess__lock_timeout],
			[sess__deadlock_priority],		--25
			[sess__row_count],
			[sess__original_login_name],
			[sess__open_transaction_count],
			[sess__group_id],
			[sess__database_id],			--30
			[sess__FKDimLoginName],
			[sess__FKDimSessionAttribute],
		
			--Connection info
			[conn__connect_time],
			[conn__net_transport],
			[conn__protocol_type],			--35
			[conn__protocol_version],
			[conn__endpoint_id],
			[conn__encrypt_option],
			[conn__auth_scheme],
			[conn__node_affinity],			--40
			[conn__net_packet_size],
			[conn__client_net_address],
			[conn__client_tcp_port],
			[conn__local_net_address],
			[conn__local_tcp_port],			--45
			[conn__FKDimNetAddress],
			[conn__FKDimConnectionAttribute],

			--TempDB utilization
			[tempdb__sess_user_objects_alloc_page_count],
			[tempdb__sess_user_objects_dealloc_page_count],
			[tempdb__sess_internal_objects_alloc_page_count],		--50
			[tempdb__sess_internal_objects_dealloc_page_count],
			[tempdb__CalculatedCurrentTempDBUsage_pages],

			--values that we will calculate ourselves
			[calc__duration_ms],
			[calc__record_priority],
			[calc__block_relevant],
			[calc__return_to_user],					--55
			[calc__is_blocker],
			[calc__sysspid_isinteresting],
			[calc__threshold_ignore],				--58
			[rqst__FKDimCommand]
		)
		SELECT 
			[sess__session_id],					--1
			[rqst__request_id],
			[TimeIdentifier],

			--session attributes
			[sess__login_time],
							--for the string fields that are in dim tables, we NULL them out if we found a match in the dimension 
							-- table. This should be the normal case, and thus we'll normally avoid persisting longer string
							-- values to tempdb pages. This helps to keep the row size from being too obscene.
			[sess__host_name] = CASE WHEN withdims.DimSessionAttributeID IS NULL THEN ISNULL(sess__host_name,@lv__nullstring) ELSE NULL END,			--5
			[sess__program_name] = CASE WHEN withdims.DimSessionAttributeID IS NULL THEN ISNULL(sess__program_name,@lv__nullstring) ELSE NULL END,
			[sess__host_process_id],
			[sess__client_version] = ISNULL(sess__client_version,@lv__nullint),
			[sess__client_interface_name] = CASE WHEN withdims.DimSessionAttributeID IS NULL THEN ISNULL(sess__client_interface_name,@lv__nullstring) ELSE NULL END,
			[sess__login_name] = CASE WHEN withdims.DimLoginNameID IS NULL THEN ISNULL(sess__login_name,@lv__nullstring) ELSE NULL END,			--10
			[sess__status_code],
			[sess__cpu_time],
			[sess__memory_usage],
			[sess__total_scheduled_time],
			[sess__total_elapsed_time],			--15
			[sess__endpoint_id],
			[sess__last_request_start_time],
			[sess__last_request_end_time],
			[sess__reads],
			[sess__writes],						--20
			[sess__logical_reads],
			[sess__is_user_process],
			[sess__transaction_isolation_level],
			[sess__lock_timeout],
			[sess__deadlock_priority],			--25
			[sess__row_count],
			[sess__original_login_name] = CASE WHEN withdims.DimLoginNameID IS NULL THEN ISNULL(sess__original_login_name,@lv__nullstring) ELSE NULL END,
			[sess__open_transaction_count],
			[sess__group_id],
			[sess__database_id],				--30
			[sess__FKDimLoginName] = CASE WHEN withdims.DimLoginNameID IS NOT NULL THEN withdims.DimLoginNameID 
										WHEN sess__login_name IS NULL AND sess__original_login_name IS NULL THEN 1
										ELSE NULL END,
			[sess__FKDimSessionAttribute] = withdims.DimSessionAttributeID,

			--Connection info
			[conn__connect_time],
			[conn__net_transport] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__net_transport,@lv__nullstring) ELSE NULL END,
			[conn__protocol_type] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__protocol_type,@lv__nullstring) ELSE NULL END,		--35
			[conn__protocol_version] = ISNULL(conn__protocol_version,@lv__nullint),
			[conn__endpoint_id] = ISNULL(conn__endpoint_id,@lv__nullint),
			[conn__encrypt_option] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__encrypt_option,@lv__nullstring) ELSE NULL END,
			[conn__auth_scheme] = CASE WHEN withdims.DimConnectionAttributeID IS NULL THEN ISNULL(withdims.conn__auth_scheme,@lv__nullstring) ELSE NULL END,
			[conn__node_affinity] = ISNULL(conn__node_affinity,@lv__nullsmallint),					--40
			[conn__net_packet_size] = ISNULL(conn__net_packet_size,@lv__nullint),

			[conn__client_net_address] = CASE WHEN withdims.DimNetAddressID IS NOT NULL THEN NULL ELSE ISNULL(withdims.conn__client_net_address,@lv__nullstring) END,
			[conn__client_tcp_port],
			[conn__local_net_address] = CASE WHEN withdims.DimNetAddressID IS NOT NULL THEN NULL ELSE ISNULL(withdims.conn__local_net_address,@lv__nullstring) END,
			[conn__local_tcp_port] = ISNULL(conn__local_tcp_port,@lv__nullint),					--45
			[conn__FKDimNetAddress] = CASE WHEN withdims.DimNetAddressID IS NOT NULL THEN withdims.DimNetAddressID
										WHEN conn__local_net_address IS NULL AND conn__local_tcp_port IS NULL
											AND conn__client_net_address IS NULL THEN 1
										ELSE NULL END,

			[conn__FKDimConnectionAttribute] = CASE WHEN sess__is_user_process = 0 THEN 1 ELSE withdims.DimConnectionAttributeID END,
										--system spids don't have a connection, so we always give them the "null connection" row

			--TempDB utilization
			[tempdb__sess_user_objects_alloc_page_count],
			[tempdb__sess_user_objects_dealloc_page_count],
			[tempdb__sess_internal_objects_alloc_page_count],		--80
			[tempdb__sess_internal_objects_dealloc_page_count],
			[tempdb__CalculatedCurrentTempDBUsage_pages],

			--values that we will calculate ourselves
			[calc__duration_ms],
			[calc__record_priority],
			[calc__block_relevant],
			[calc__return_to_user],				--100
			[calc__is_blocker],
			[calc__sysspid_isinteresting],
			[calc__threshold_ignore],
			[rqst__FKDimCommand] 
		FROM (
			SELECT 
				dca.DimConnectionAttributeID,
				dna.DimNetAddressID,
				dln.DimLoginNameID,
				dsa.DimSessionAttributeID, 
				[sess__session_id] = s.session_id,
				[rqst__request_id] = @lv__nullsmallint,
				[TimeIdentifier] = ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime),

				--session attributes
				[sess__login_time] = s.login_time,
				[sess__host_name] = s.[host_name],
				[sess__program_name] = s.[program_name],
				[sess__host_process_id] = s.host_process_id,
				[sess__client_version] = s.client_version,
				[sess__client_interface_name] = s.client_interface_name,
				[sess__login_name] = s.login_name,

				[sess__status_code] = CASE LOWER(s.[status]) 
										WHEN N'running'		THEN CONVERT(TINYINT,0)
										WHEN N'sleeping'	THEN CONVERT(TINYINT,1)
										WHEN N'dormant'		THEN CONVERT(TINYINT,2)
										WHEN N'preconnect'	THEN CONVERT(TINYINT,3)
										ELSE CONVERT(TINYINT,255)
										END,			
				[sess__cpu_time] = s.cpu_time,
				[sess__memory_usage] = s.memory_usage,
				[sess__total_scheduled_time] = s.total_scheduled_time,
				[sess__total_elapsed_time] = s.total_elapsed_time,
				[sess__endpoint_id] = s.endpoint_id,
				[sess__last_request_start_time] = s.last_request_start_time,
				[sess__last_request_end_time] = s.last_request_end_time,
				[sess__reads] = s.reads,
				[sess__writes] = s.writes,
				[sess__logical_reads] = s.logical_reads,
				[sess__is_user_process] = s.is_user_process,
				[sess__transaction_isolation_level] = s.transaction_isolation_level,
				[sess__lock_timeout] = s.[lock_timeout],
				[sess__deadlock_priority] = s.[deadlock_priority],
				[sess__row_count] = s.[row_count],
				[sess__original_login_name] = s.original_login_name,
				[sess__open_transaction_count] = sysproc.open_tran,					--s.open_transaction_count,
				[sess__group_id] = s.group_id,
				[sess__database_id] = sysproc.[dbid],								--2012 and later: s.database_id,

				--Connection info
				[conn__connect_time] = c.connect_time,
				[conn__net_transport] = c.net_transport,
				[conn__protocol_type] = c.protocol_type,
				[conn__protocol_version] = c.protocol_version,
				[conn__endpoint_id] = c.endpoint_id,
				[conn__encrypt_option] = c.encrypt_option,
				[conn__auth_scheme] = c.auth_scheme,
				[conn__node_affinity] = c.node_affinity,
				[conn__net_packet_size] = c.net_packet_size,
				[conn__client_net_address] = c.client_net_address,
				[conn__client_tcp_port] = c.client_tcp_port,
				[conn__local_net_address] = c.local_net_address,
				[conn__local_tcp_port] = c.local_tcp_port,

				--TempDB utilization
				[tempdb__sess_user_objects_alloc_page_count] = ssu.user_objects_alloc_page_count,
				[tempdb__sess_user_objects_dealloc_page_count] = ssu.user_objects_dealloc_page_count,
				[tempdb__sess_internal_objects_alloc_page_count] = ssu.internal_objects_alloc_page_count,
				[tempdb__sess_internal_objects_dealloc_page_count] = ssu.internal_objects_dealloc_page_count,
				[tempdb__CalculatedCurrentTempDBUsage_pages] = (
						CASE WHEN (ISNULL(ssu.user_objects_alloc_page_count,0) - ISNULL(ssu.user_objects_dealloc_page_count,0)) < 0 THEN 0
							ELSE (ISNULL(ssu.user_objects_alloc_page_count,0) - ISNULL(ssu.user_objects_dealloc_page_count,0))
							END + 
						CASE WHEN (ISNULL(ssu.internal_objects_alloc_page_count,0) - ISNULL(ssu.internal_objects_dealloc_page_count,0)) < 0 THEN 0
							ELSE (ISNULL(ssu.internal_objects_alloc_page_count,0) - ISNULL(ssu.internal_objects_dealloc_page_count,0))
							END
					),

				--this is a display-relevent field, but we calc it now to save on calc time @ presentation time
				[calc__record_priority] = (CASE WHEN s.is_user_process = 0 THEN CONVERT(TINYINT,5) ELSE CONVERT(TINYINT,10) END),

				-- A duration is positive if the spid is active (request start_time is not null), and negative if the spid is idle (duration based off
				-- of session.last_request_end_time). Note that this logic has to be tricky because of the risk of data type overflows. Our duration
				-- is stored in milliseconds, but a system spid on a server that hasn't been rebooted in a while will overflow the DATEDIFF function.
				-- Therefore, the below logic first evaluates on a DATEDIFF(SECOND... calculation before branching into a calculation that will produce
				-- the appropriate difference in milliseconds.
				-- Note that (rarely) a request start time can be 1900-01-01, and we also defend against NULL values. We use the TempDB creation time
				-- as a fallback value in these cases.
				[calc__duration_ms] = (	--r.request_id IS null, idle spid. Do a similar calculation but on last_request_end_time
							CASE WHEN DATEDIFF(second, ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime), @lv__SPIDCaptureTime) > 300 
									THEN CONVERT(BIGINT,
													DATEDIFF(SECOND, 
																ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime), 
																@lv__SPIDCaptureTime
															)
												)*CONVERT(BIGINT,1000)
									ELSE CONVERT(BIGINT,DATEDIFF(MILLISECOND,ISNULL(NULLIF(s.last_request_end_time,'1900-01-01'),@TempDBCreateTime), @lv__SPIDCaptureTime))
								END),
				[calc__return_to_user] = 5,		--5 is the code for "brought in as a missing blocker"
				[calc__is_blocker]  = 1,
				[calc__block_relevant] = 1,
				[calc__sysspid_isinteresting] = 0, 
				[calc__threshold_ignore] = CASE WHEN threshignore.FilterID IS NOT NULL THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END, 
				[rqst__FKDimCommand] = 1		--all of these are by definition idle, and thus get the pre-defined "1" code.
			FROM @FilterTable threshignore
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca
				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa

				RIGHT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln
					RIGHT OUTER hash JOIN --#3
					--We pull data from sysprocesses for a couple of reasons:
					--		1. it has the # of trans open for a SPID
					--		2. It has the database context that the SPID is executing in (the DMVs do not have this info until SQL 2012)
						(SELECT spid, [dbid], open_tran 
							FROM master.dbo.sysprocesses
							WHERE ecid = 0		--for parallel queries, it appears that this view will have open_tran = 1 for the parent, and = 0 for the children
						) sysproc
			
						RIGHT OUTER hash JOIN --#4
							sys.dm_db_session_space_usage ssu 
		
							RIGHT OUTER hash JOIN --#5
								sys.dm_exec_connections c

								RIGHT OUTER hash JOIN --#6
									(SELECT DISTINCT blockedspid.calc__blocking_session_id
									FROM #sessions_and_requests blockedspid
										LEFT OUTER hash JOIN #sessions_and_requests blockernotcaptured
											ON blockedspid.calc__blocking_session_id = blockernotcaptured.sess__session_id
									WHERE blockedspid.calc__blocking_session_id > 0
									AND blockernotcaptured.sess__session_id IS NULL		--the blocker isn't present at all in #sar
									) missblockers
									INNER hash JOIN	--#7
									sys.dm_exec_sessions s
										RIGHT OUTER hash JOIN 
											@@CHIRHO_SCHEMA@@.AutoWho_CollectorOptFakeout cof
											ON cof.ZeroOrOne = s.is_user_process
										ON s.session_id = missblockers.calc__blocking_session_id		--#7
									ON s.session_id = c.session_id		--ON for #6
									AND c.parent_connection_id IS NULL	--MARS connections will have multiple rows in the view that we really do not care about
									AND c.session_id >= 0		--another dummy clause for the optimizer to affect cardinality estimates

							ON s.session_id = ssu.session_id	--ON for #5
							AND ssu.database_id = 2
							AND ssu.session_id >= 0		--another dummy clause for the optimizer
						ON s.session_id = sysproc.spid		--ON for #4
						AND sysproc.spid >= 0	--The optimizer tends to way-overestimate the resulting cardinality of this join. 
											--(since SQL does not have stats on the data (b/c it is a DMV, of course)
											--Thus, we throw in a functionally-redundant filter to help calm its estimates down. 
											-- The same approach has been used several other times in this query.

				ON dln.login_name = s.login_name					--BOL: NOT nullable
				AND dln.original_login_name = s.original_login_name	--BOL: NOT nullable

				ON dsa.endpoint_id = s.endpoint_id			--BOL: NOT nullable
				AND dsa.transaction_isolation_level = s.transaction_isolation_level		--BOL: NOT nullable
				AND dsa.[deadlock_priority] = s.deadlock_priority		--BOL: NOT nullable
				AND dsa.group_id = s.group_id				--BOL: NOT nullable
				AND dsa.[host_name] = ISNULL(s.host_name,@lv__nullstring)			--BOL: null for internal sessions
				AND dsa.[program_name] = ISNULL(s.program_name,@lv__nullstring)		--BOL: null for internal sessions
				AND dsa.client_version = ISNULL(s.client_version,@lv__nullint)	--BOL: null for internal sessions
				AND dsa.client_interface_name = ISNULL(s.client_interface_name,@lv__nullstring)		--BOL: null for internal sessions

				ON dca.net_transport = c.net_transport					--BOL: NOT nullable
				AND dca.node_affinity = c.node_affinity					--BOL: NOT nullable
				AND dca.encrypt_option = c.encrypt_option				--BOL: NOT nullable
				AND dca.auth_scheme = c.auth_scheme						--BOL: NOT nullable
				AND dca.protocol_type = ISNULL(c.protocol_type,@lv__nullstring)				--BOL: yes, NULLABLE
				AND dca.protocol_version = ISNULL(c.protocol_version,@lv__nullint)			--BOL: yes, NULLABLE
				AND dca.endpoint_id = ISNULL(c.endpoint_id,@lv__nullint)					--BOL: yes, NULLABLE
				AND dca.net_packet_size = ISNULL(c.net_packet_size,@lv__nullint)			--BOL: yes, NULLABLE

				ON dna.client_net_address = c.client_net_address		--BOL: yes, is NULLABLE
				AND dna.local_net_address = ISNULL(c.local_net_address,@lv__nullstring)			--BOL: yes, is NULLABLE
				AND dna.local_tcp_port = ISNULL(c.local_tcp_port,@lv__nullint)				--BOL: yes, is NULLABLE

			ON threshignore.FilterID = s.session_id
			AND threshignore.FilterType = CONVERT(TINYINT,128)
		) withdims
		OPTION(MAXDOP 1, KEEPFIXED PLAN, FORCE ORDER);

		SET @scratch__int = @@ROWCOUNT;

		SET @lv__SAR_numrecords = @lv__SAR_numrecords + ISNULL(@scratch__int,0);

		--print '#recs after missblocker: ' + isnull(convert(varchar(20), @lv__SAR_numrecords),'<null>');

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'MissBlk:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	--set our OUTPUT variable (tells the caller how many spids were pulled, so the caller can consider when to RECOMPILE
	SET @NumSPIDs = @lv__SAR_numrecords;

	--select * from #sessions_and_requests order by sess__session_id asc;

	SET @errorloc = N'Check Thresholds SAR';
	--run a scan over the sar table to profile the info... this info will affect some of the auxiliary branches 
	-- that we execute below
	SELECT 
		@thresh__OpenTransExist = MAX(transExist),
		@thresh__maxActiveDuration = MAX(maxActiveDuration),
		@thresh__maxIdleWOTranDuration = MAX(maxIdleWOTranDuration),
		@thresh__maxIdleWithTranDuration = MAX(maxIdleWithTranDuration),
		@thresh__QueryPlansNeeded = MAX(queryPlanNeeded),
		@thresh__GhostCleanupIsRunning = MAX(ghostCleanupIsRunning), 
		@NewDims__Command = MAX(NewDim__Command),
		@NewDims__ConnectionAttribute = MAX(NewDim__ConnectionAttribute),
		@NewDims__LoginName = MAX(ss2.NewDim__LoginName),
		@NewDims__NetAddress = MAX(ss2.NewDim__NetAddress),
		@NewDims__SessionAttribute = MAX(ss2.NewDim__SessionAttribute),
		@NewDims__WaitType_sar = MAX(ss2.NewDim__WaitType)
	FROM (
		SELECT 
			sess__session_id,
			rqst__request_id, 
			transExist = MAX(CASE WHEN istfx = CONVERT(BIT,0) THEN transExist ELSE 0 END),
			queryPlanNeeded = MAX(queryPlanNeeded),
			ghostCleanupIsRunning = MAX(ghostCleanupIsRunning),
			maxActiveDuration = MAX(CASE WHEN istfx = CONVERT(BIT,0) THEN ActiveDuration ELSE 0 END),
			maxIdleWOTranDuration = MAX(CASE WHEN istfx = CONVERT(BIT,0) THEN IdleWOTranDuration ELSE 0 END),
			maxIdleWithTranDuration = MAX(CASE WHEN istfx = CONVERT(BIT,0) THEN IdleWithTranDuration ELSE 0 END),
			NewDim__Command = MAX(EmptyDim__Command),
			NewDim__ConnectionAttribute = MAX(EmptyDim__ConnectionAttribute),
			NewDim__LoginName = MAX(EmptyDim__LoginName),
			NewDim__NetAddress = MAX(EmptyDim__NetAddress),
			NewDim__SessionAttribute = MAX(EmptyDim__SessionAttribute),
			NewDim__WaitType = MAX(EmptyDim__WaitType)
		FROM (
			SELECT 
				sar.sess__session_id,
				sar.rqst__request_id, 
				--are we excluding this SPID from the threshold calcs?
				istfx = CASE WHEN tfx.FilterID IS NOT NULL AND ISNULL(sar.calc__block_relevant,0) = 0		--if one of these spids WAS blocked/blocking, we definitely want its info
																											--to trigger auxiliary captures
							THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END,
				transExist = CASE WHEN sess__open_transaction_count > 0 OR rqst__open_transaction_count > 0
									OR ISNULL(rqst__transaction_isolation_level,127) IN (0,3,4)
									OR (	--if spid is active, and has a RR or serializable iso level, it is holding locks.
										ISNULL(sess__transaction_isolation_level,127) IN (0,3,4) 
										AND rqst__request_id <> @lv__nullsmallint)
								THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END,
				queryPlanNeeded = CASE 
						WHEN rqst__request_id = @lv__nullsmallint or sess__is_user_process = 0 THEN 0
						ELSE (CASE	--we know it is a user spid that is actively running
								WHEN calc__block_relevant = 1 AND calc__duration_ms >= @QueryPlanThresholdBlockRel THEN 1 
								WHEN (tfx.FilterID IS NOT NULL AND rqst__FKDimWaitType <> 2)	--2 is the code for WAITFOR
									OR (tfx.FilterID IS NULL AND calc__duration_ms >= @QueryPlanThreshold) THEN 1
								ELSE 0 END)
						END,
				ghostCleanupIsRunning = CASE WHEN sar.rqst__FKDimCommand = 2 THEN 1 ELSE 0 END,
				ActiveDuration = CASE WHEN sess__is_user_process = 1 AND sar.rqst__request_id <> @lv__nullsmallint THEN sar.calc__duration_ms ELSE NULL END,
				IdleWOTranDuration = CASE WHEN sess__is_user_process = 1 AND sar.rqst__request_id = @lv__nullsmallint AND sar.sess__open_transaction_count = 0 
											THEN sar.calc__duration_ms ELSE NULL END,
				IdleWithTranDuration = CASE WHEN sess__is_user_process = 1 AND sar.rqst__request_id = @lv__nullsmallint AND sar.sess__open_transaction_count > 0 
												THEN sar.calc__duration_ms ELSE NULL END,

				EmptyDim__Command = CASE WHEN sar.rqst__FKDimCommand IS NULL THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END,
				EmptyDim__ConnectionAttribute = CASE WHEN sar.conn__FKDimConnectionAttribute IS NULL THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END,
				EmptyDim__LoginName = CASE WHEN sar.sess__FKDimLoginName IS NULL THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END,
				EmptyDim__NetAddress = CASE WHEN sar.conn__FKDimNetAddress IS NULL THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END,
				EmptyDim__SessionAttribute = CASE WHEN sar.sess__FKDimSessionAttribute IS NULL THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END,
				EmptyDim__WaitType = CASE WHEN sar.rqst__FKDimWaitType IS NULL THEN CONVERT(TINYINT,1) ELSE CONVERT(TINYINT,0) END
			FROM (SELECT f.FilterID
				  FROM @FilterTable f
				  WHERE f.FilterType = 128	--threshold filter type
					) tfx
				RIGHT OUTER hash JOIN #sessions_and_requests sar
					ON sar.sess__session_id = tfx.FilterID
			WHERE sar.calc__return_to_user > 0
		) ss1
		GROUP BY sess__session_id, rqst__request_id
	) ss2
	OPTION(MAXDOP 1, KEEPFIXED PLAN, FORCE ORDER);

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'SARthres:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END

	--Do a scan over #taw. We want to learn the following: 
	--		1. are there any THREADPOOL waits? (i.e. do we need a -998 spid?)
	--		2. are there any PAGE/PAGEIO latch waits?
	--		3. are there any wait types that are not in DimWaitType yet?
	--		4. the maximum wait-length of a task that is blocked behind another spid

	--NOTE: Its ok that we're doing #taw (and potentially, its insert of -998) after our scan of #sar.
	-- we are NOT going to populate any wait-related field in #sar, so the -998 row isn't relevant to our
	-- @NewDims logic
	SET @errorloc = N'Check thresholds TAW';

	SELECT 
		@thresh__THREADPOOLpresent = MAX(isThreadpool),
		@thresh__PAGELATCHpresent = MAX(isPageLatch),
		@NewDims__WaitType_taw = MAX(missingWaits),
		@thresh__maxWaitLength_BlockedSPID = MAX(blockedWaitTime)
	FROM (
		SELECT 
			isThreadpool = CASE WHEN taw.session_id = -998 AND taw.wait_type = N'THREADPOOL' THEN 1 ELSE 0 END,
			isPageLatch = CASE WHEN taw.wait_special_category IN (@enum__waitspecial__pgblocked, @enum__waitspecial__pgio, @enum__waitspecial__pg) THEN 1 ELSE 0 END,
			missingWaits = CASE WHEN dwt.DimWaitTypeID IS NULL THEN 1 ELSE 0 END,
			blockedWaitTime = CASE WHEN taw.blocking_session_id IS NOT NULL		--remember, we've already set this field to NULL if it = session_id (CXP waits)
									AND taw.task_priority = 1			--the wait has to be the spid's longest wait, otherwise the Bchain will hold the wrong info
								THEN wait_duration_ms ELSE 0 END
		FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
			RIGHT OUTER hash JOIN (
				--we only want TAW records that are tied to sar records that are going to be returned,
				-- or are not tied to a spid at all

				--Note that we don't need to reference the threshold filter exclusion table at all, since the 
				-- a "threshold filter exclusion" spid can't be in a threadpool wait, of course,
				-- if it has page latches we want to know about them, and if it has a missing wait type we 
				-- want to add that to the dim. And if it is blocked, we DO want to consider it for our auxiliary captures
				SELECT taw.*
				FROM #sessions_and_requests sar
					RIGHT OUTER hash JOIN #tasks_and_waits taw
						ON sar.sess__session_id = taw.session_id
						AND sar.rqst__request_id = taw.request_id
				WHERE (taw.session_id = -998
					OR (taw.session_id > 0 AND sar.calc__return_to_user > 0))
				) taw
				ON taw.wait_type = dwt.wait_type
				AND taw.wait_latch_subtype = dwt.latch_subtype
	) ss
	OPTION(FORCE ORDER, KEEPFIXED PLAN, MAXDOP 1)
	;

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'TAWthresh:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END

	IF @thresh__THREADPOOLpresent > 0
	BEGIN
		--we have THREADPOOL waits, therefore load a -998 record into #sessions_and_requests
		SET @errorloc = N'Insert Threadpool row';
		INSERT INTO #sessions_and_requests (
			sess__session_id,
			rqst__request_id,
			TimeIdentifier,
			calc__record_priority,
			calc__block_relevant,
			tempdb__CalculatedNumberOfTasks,		--holds the # of tasks that are in THREADPOOL wait
			calc__duration_ms,				--for this special row, we are repurposing this field to hold the avg duration of threadpool waits
			calc__return_to_user
		)
		SELECT session_id,
			request_id,
			@lv__nulldatetime,
			calc__record_priority,
			calc__block_relevant,
			tpools.NumTasks,
			tpools.avg_wait_time_ms,
			calc__return_to_user 
		FROM (
			SELECT 
				session_id = CONVERT(SMALLINT,-998),
				request_id = @lv__nullsmallint,
				calc__record_priority = CONVERT(TINYINT,4),
				calc__block_relevant = CONVERT(TINYINT,1),
				calc__return_to_user = CONVERT(SMALLINT,128)
			) onerow
			CROSS JOIN (
				SELECT COUNT(*) as NumTasks, AVG(ISNULL(taw.wait_duration_ms,0)) as avg_wait_time_ms
				FROM #tasks_and_waits taw
				WHERE taw.wait_type = N'THREADPOOL'
			) tpools
		OPTION(MAXDOP 1, KEEPFIXED PLAN);
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'ThrPool:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END




--The order chosen for the following steps is intentional:
-- 1. If desired (parameter) and appropriate (threshold), construct the BChains. This lets us know whether we need to get input buffers even if the user didn't specify to get input buffers.
-- 2. Go and get input buffers if necessary, whether because user asked for them, BChains require them, or both
-- 3. Do other stuff.
-- The reason we prioritize input buffer code over, say, the statement & batch loops is because those are more likely to stick around for a few 
-- seconds, due to the way the procedure/plan cache works. However, a short-lived spid (or one that is quickly reset via connection pooling) will
-- not give us an input buffer (or the right input buffer) if we wait too long, so we want to grab that information as soon as we can.
/*
   ****   *       ****       ***   *   *  *****  *   *   ****     *****  ****   ****  ****
   *   *  *      *    *     *      *  *     *    **  *  *           *    *   *  *     *
   ****   *     *      *   *       ***      *    * * *  *  ***      *    ****   ****  ****
   *   *  *      *    *     *      *  *     *    *  **  *    *      *    *  *   *     *
   ****   *****   ****       ***   *   *  *****  *   *   ****       *    *   *  ****  ****
*/

	IF @BlockingChainDepth > 0 AND @thresh__maxWaitLength_BlockedSPID >= @BlockingChainThreshold
	BEGIN
		SET @errorloc = N'Construct BChain';
		;WITH ConstructBlockingChain AS (
			SELECT sar.sess__session_id, sar.rqst__request_id, sar.calc__blocking_session_id, 
					sar.rqst__sql_handle, sar.rqst__statement_start_offset, sar.rqst__statement_end_offset,
				0 as levelindc, 
				[block_group] = sar.sess__session_id,
				[sort_value] = CONVERT(NVARCHAR(400),CONVERT(NVARCHAR(20), sar.sess__session_id))
			FROM #sessions_and_requests sar
			WHERE sar.calc__is_blocker = 1						--spids that are blockers but not blocked are "root blockers"
			AND ISNULL(sar.calc__blocking_session_id,0) = 0		-- we build a chain off of these, but only
			AND sar.calc__return_to_user > 0					--if they are in scope.

			UNION ALL 

			SELECT sar.sess__session_id, sar.rqst__request_id, sar.calc__blocking_session_id, 
				sar.rqst__sql_handle, sar.rqst__statement_start_offset, sar.rqst__statement_end_offset,
				c.levelindc + 1 AS levelindc,
				c.block_group,
				CONVERT(NVARCHAR(400),(RTRIM(c.sort_value)+N'| '+CONVERT(NVARCHAR(20), sar.sess__session_id)))
			FROM #sessions_and_requests sar 
				INNER JOIN ConstructBlockingChain c
					ON sar.calc__blocking_session_id = c.sess__session_id
			WHERE c.levelindc < @BlockingChainDepth				-- note that we don't restrict to in-scope for the intermediate
																-- and child-nodes of the tree/chain. 
		)

		INSERT INTO #BChain (
			session_id, request_id, exec_context_id,
			calc__blocking_session_id, wait_type, wait_duration_ms, 
			resource_description, [sql_handle], statement_start_offset, statement_end_offset,
			sort_value, block_group, levelindc, rn
		)
		SELECT ss0.sess__session_id, ss0.rqst__request_id, ss0.exec_context_id,
				ss0.calc__blocking_session_id, ss0.wait_type, ss0.wait_duration_ms, 
				ss0.resource_description, ss0.rqst__sql_handle, ss0.rqst__statement_start_offset, ss0.rqst__statement_end_offset,
				ss0.sort_value, ss0.block_group, ss0.levelindc, ss0.rn
		FROM 
			(SELECT cte1.sess__session_id, cte1.rqst__request_id, 
					cte1.calc__blocking_session_id, cte1.rqst__sql_handle,
				cte1.levelindc, cte1.sort_value, cte1.block_group,
				cte1.rqst__statement_start_offset, cte1.rqst__statement_end_offset, 
				[rn] = ROW_NUMBER() OVER (PARTITION BY calc__blocking_session_id ORDER BY taw.wait_duration_ms DESC)
				,taw.wait_type, taw.wait_duration_ms, 
				resource_description = CONVERT(nvarchar(500),taw.resource_description), taw.exec_context_id
			FROM ConstructBlockingChain cte1
				LEFT OUTER JOIN #tasks_and_waits taw
					ON taw.session_id = cte1.sess__session_id
					AND taw.request_id = cte1.rqst__request_id
					AND taw.task_priority = 1			--this comment duplicated from the statement that populates #tasks_and_waits: 
														--"This field is for the blocking tree functionality. 
														-- We want "1" to represent the very top row... the wait record
														-- that we'll display when we construct the blocking tree text"
			) ss0

		WHERE ss0.rn <= @BlockingChainDepth
		ORDER BY block_group, sort_value 
		OPTION(MAXDOP 1, KEEPFIXED PLAN, MAXRECURSION 100);

		SET @scratch__int = @@ROWCOUNT;

		IF ISNULL(@scratch__int,0) > 0
		BEGIN
			SET @lv__BChainRecsExist = 1;
		END

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'BChain:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END	--IF @BlockingChainDepth > 0 AND @thresh__maxWaitLength_BlockedSPID >= @BlockingChainThreshold

	/***************************************************************************************************************************
											End Of "Blocking Tree" section
	***************************************************************************************************************************/

	DECLARE @lv__scopeIdent INT, 
			@lv__numIBsCollected INT,
			@lv__IBThresh_ms BIGINT;
	SET @lv__numIBsCollected = 0;	--our loop counter below
	SET @lv__IBThresh_ms = @InputBufferThreshold;

	--If appropriate, go and get input buffers. We get IBs under 3 circumstances:
	--	1. There are Bchain records -- we need to find the IB for root blockers that are idle
	--	2. we have spids whose active-or-idle-with-tran duration is >= our Input Buffer threshold
	--	3. the user has told us he/she wants to see completely idle spids, and we have a duration >= the IB threshold
	IF @lv__BChainRecsExist = 1 
		OR @thresh__maxActiveDuration >= @lv__IBThresh_ms
		OR @thresh__maxIdleWithTranDuration >= @lv__IBThresh_ms
		OR @thresh__maxIdleWOTranDuration >= @lv__IBThresh_ms
		--OLD logic: OR (@IncludeIdleWithoutTran = N'Y' AND @thresh__maxIdleWOTranDuration >= @InputBufferThreshold)
		--  we omit the check on @IncludeIdleWithoutTran here because if the threshold has been triggered for an idle wo tran spid, then 
		-- then even if the user doesn't want those spids included there is a good reason to capture an input buffer for it.
	BEGIN
		SET @lv__SmallDynSQL = N'DBCC INPUTBUFFER(@spid) WITH NO_INFOMSGS';

		SET @errorloc = N'IB capture cursor pop';

		DECLARE getInputBufferCursor CURSOR LOCAL FAST_FORWARD FOR 
		SELECT bc.session_id 
		FROM #BChain bc
		WHERE @lv__BChainRecsExist = 1					--should give us a startup filter so that we don't touch the #BChain table
															--at all unless there are actually records
		AND ISNULL(bc.calc__blocking_session_id,0) = 0		--no blocker, so is the root
		AND bc.request_id = @lv__nullsmallint				--only need the input buffer for idle spids

		UNION

		SELECT session_id = sar.sess__session_id
		FROM #sessions_and_requests sar
		WHERE sar.sess__is_user_process = 1				--system SPIDs do not have an input buffer... don't waste loop iterations on them
		AND sar.calc__return_to_user > 0				--only do stuff we're going to display
		AND (
			--should give us a startup filter so that we don't touch the #sar table at all if our threshold scan found nothing over
				@thresh__maxActiveDuration >= @lv__IBThresh_ms
				OR @thresh__maxIdleWithTranDuration >= @lv__IBThresh_ms
				OR @thresh__maxIdleWOTranDuration >= @lv__IBThresh_ms
			)
		AND sar.calc__duration_ms >= @lv__IBThresh_ms
		OPTION(MAXDOP 1, KEEPFIXED PLAN);

		OPEN getInputBufferCursor;
		FETCH getInputBufferCursor INTO @lv__CursorCurrentSPID;

		SET @errorloc = N'IB capture loop';

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @lv__numIBsCollected = @lv__numIBsCollected + 1;
			SET @lv__scopeIdent = NULL;

			--DBCC INPUTBUFFER can fail if the SPID no longer exists
			BEGIN TRY
				INSERT INTO #t__ib (EventType,Parameters,InputBuffer)
					EXEC sp_executesql @lv__SmallDynSQL, N'@spid INT', @lv__CursorCurrentSPID;

				SET @lv__scopeIdent = SCOPE_IDENTITY();
			END TRY
			BEGIN CATCH
				INSERT INTO #t__ib (session_id, EventType, Parameters, InputBuffer)
					SELECT @lv__CursorCurrentSPID, '', '', 'Unable to obtain Input Buffer; SPID may no longer exist';
			END CATCH

			IF @lv__scopeIdent IS NOT NULL
			BEGIN	--we captured the input buffer; now remove any Unicode 0 characters (they cause problems when
					-- trying to convert to the input buffer text to XML) and match up the session_id with our main
					-- sessions temp table and apply the update
				SET @errorloc = N'IB capture TT update';
				; WITH cte1 as (
					SELECT 
						session_id,
						InputBuffer,
						aw_buffer_hash,
						spid = @lv__CursorCurrentSPID, 
						ib = REPLACE(
									CONVERT
									(
										NVARCHAR(MAX),
										N'--' + NCHAR(13) + NCHAR(10) + 
										REPLACE(ISNULL(t.InputBuffer,'<Unexpected Null InputBuffer Value>'),
														'<?','~Q') +	--the Input Buffer for SPIDs that call sp_spidmon or its cousins may have <? characters in them!
																		-- this won't work for converting to XML, so replace them with something harmless
										NCHAR(13) + NCHAR(10) + 
										N'--' 
									) COLLATE Latin1_General_Bin2,
									NCHAR(0),N'')
					FROM #t__ib t
					WHERE idcol = @lv__scopeIdent
				)
				UPDATE t
				SET t.session_id = spid,
					InputBuffer = ib,
					aw_buffer_hash = HASHBYTES('MD5', ib)
				FROM cte1 t 
				OPTION(MAXDOP 1, KEEPFIXED PLAN);
			END

			FETCH getInputBufferCursor INTO @lv__CursorCurrentSPID;
		END

		CLOSE getInputBufferCursor;
		DEALLOCATE getInputBufferCursor;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'IBcap:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END	--test to determine whether to do input buffer code or not

	/***************************************************************************************************************************
												End Of "input buffer" section
	***************************************************************************************************************************/
	
	--Capturing transaction details is usually pretty quick since the below query is not expensive normally. We do this before
	-- the sql/plan cache stuff because that cache stuff isn't likely to disappear in the next second or two, whereas transaction
	-- details could change slightly.
	IF @thresh__OpenTransExist > 0
		OR @thresh__maxActiveDuration >= @TranDetailsThreshold
		OR @thresh__maxIdleWithTranDuration >= @TranDetailsThreshold
	BEGIN
		SET @errorloc = N'Tran capture query';

		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails (
			CollectionInitiatorID,			--1
			UTCCaptureTime,
			SPIDCaptureTime,		
			session_id, 
			TimeIdentifier,					--5
			dtat_transaction_id,
			dtat_name,
			dtat_transaction_begin_time, 
			dtat_transaction_type, 
			dtat_transaction_uow,			--10
			dtat_transaction_state,
			dtat_dtc_state,	
			dtst_enlist_count, 
			dtst_is_user_transaction, 
			dtst_is_local,					--15
			dtst_is_enlisted,
			dtst_is_bound,
			dtdt_database_id, 
			dtdt_database_transaction_begin_time, 
			dtdt_database_transaction_type,		--20
			dtdt_database_transaction_state,
			dtdt_database_transaction_log_record_count,
			dtdt_database_transaction_log_bytes_used, 
			dtdt_database_transaction_log_bytes_reserved, 
			dtdt_database_transaction_log_bytes_used_system, --25
			dtdt_database_transaction_log_bytes_reserved_system,
			dtasdt_tran_exists,
			dtasdt_transaction_sequence_num,
			dtasdt_commit_sequence_num,
			dtasdt_is_snapshot,				--30
			dtasdt_first_snapshot_sequence_num,
			dtasdt_max_version_chain_traversed,
			dtasdt_average_version_chain_traversed,
			dtasdt_elapsed_time_seconds	--34
			)
		SELECT
			CollectionInitiatorID = @CollectionInitiatorID,		--1
			UTCCaptureTime = @lv__UTCCaptureTime,
			SPIDCaptureTime = @lv__SPIDCaptureTime,		
			sar.sess__session_id,
			TimeIdentifier = sar.TimeIdentifier,				--5
			[dtat_transaction_id] = dtat.transaction_id,
			[dtat_name] = dtat.name,
			[dtat_transaction_begin_time] = dtat.transaction_begin_time,
			[dtat_transaction_type] = dtat.transaction_type,
			[dtat_transaction_uow] = dtat.transaction_uow,		--10
			[dtat_transaction_state] = dtat.transaction_state,
			[dtat_dtc_state] = dtat.dtc_state,

			[dtst_enlist_count] = dtst.enlist_count, 
			[dtst_is_user_transaction] = dtst.is_user_transaction, 
			[dtst_is_local] = dtst.is_local,					--15
			[dtst_is_enlisted] = dtst.is_enlisted,
			[dtst_is_bound] = dtst.is_bound,

			[dtdt.database_id] = dtdt.database_id, 
			[dtdt_database_transaction_begin_time] = dtdt.database_transaction_begin_time, 
			[dtdt_database_transaction_type] = dtdt.database_transaction_type,	--20
			[dtdt_database_transaction_state] = dtdt.database_transaction_state,
			[dtdt_database_transaction_log_record_count] = dtdt.database_transaction_log_record_count,
			[dtdt_database_transaction_log_bytes_used] = dtdt.database_transaction_log_bytes_used, 
			[dtdt_database_transaction_log_bytes_reserved] = dtdt.database_transaction_log_bytes_reserved, 
			[dtdt_database_transaction_log_bytes_used_system] = dtdt.database_transaction_log_bytes_used_system, --25
			[dtdt_database_transaction_log_bytes_reserved_system] = dtdt.database_transaction_log_bytes_reserved_system,

			[dtasdt_tran_exists] = CASE WHEN dtasdt.transaction_id IS NULL THEN 0 ELSE 1 END,
			[dtasdt_transaction_sequence_num] = dtasdt.transaction_sequence_num,
			[dtasdt_commit_sequence_num] = dtasdt.commit_sequence_num, 
			[dtasdt_is_snapshot] = dtasdt.is_snapshot,		--30
			[dtasdt_first_snapshot_sequence_num] = dtasdt.first_snapshot_sequence_num,
			[dtasdt_max_version_chain_traversed] = dtasdt.max_version_chain_traversed,
			[dtasdt_average_version_chain_traversed] = dtasdt.average_version_chain_traversed,
			[dtasdt_elapsed_time_seconds] = dtasdt.elapsed_time_seconds							--34
		FROM  (
			--need to handle the possibility of MARS
				SELECT 
					sess__session_id,
					TimeIdentifier,
					rn = ROW_NUMBER() OVER (PARTITION BY sess__session_id ORDER BY TimeIdentifier ASC) --oldest first
				FROM (
					SELECT sar.sess__session_id, 
						sar.TimeIdentifier
					FROM #sessions_and_requests sar
					WHERE sar.calc__return_to_user > 0
					AND (sar.sess__open_transaction_count > 0
						OR sar.rqst__open_transaction_count > 0
						OR ISNULL(sess__transaction_isolation_level,127) IN (0,3,4)
						OR ISNULL(rqst__transaction_isolation_level,127) IN (0,3,4)
						OR sar.calc__duration_ms >= @TranDetailsThreshold
						)
				) ss
			) sar
			--Note that the below join criteria will eliminate any transactions not tied to a session
			INNER hash JOIN sys.dm_tran_session_transactions dtst
				ON sar.sess__session_id = dtst.session_id
			INNER hash JOIN sys.dm_tran_active_transactions dtat
				ON dtat.transaction_id = dtst.transaction_id
			LEFT OUTER hash JOIN sys.dm_tran_database_transactions dtdt
				ON dtat.transaction_id = dtdt.transaction_id
			LEFT OUTER hash JOIN sys.dm_tran_active_snapshot_database_transactions dtasdt
				ON dtat.transaction_id = dtasdt.transaction_id
		WHERE sar.rn = 1 --only grab each session once.

		--TODO: may re-eval later whether or not we want to see these system trans
		--AND dtat.name NOT IN ('worktable','LobStorageProviderSession','WorkFileGroup_fake_worktable','workfile','sort_init','sort_fake_worktable')
		AND dtat.name NOT IN ('LobStorageProviderSession')	--for now, just exclude the one that can produce MANY records in these views

		--for an "interesting" spid (has open tran and active/idle duration is > our threshold, we want to see all trans.
		--I may revisit this logic if we are collecting too much data
		--AND (
		--	dtat.transaction_state IN (7,8)	--tran in rollback
		--	OR dtdt.database_transaction_state = 11	--ditto
		--	OR dtdt.database_transaction_log_bytes_reserved >= (1*1024*1024)	--1 MB
		--	OR dtdt.database_transaction_log_bytes_reserved_system > (1*1024*1024)   --1 MB
		--	OR dtat.transaction_begin_time < DATEADD(SECOND, 0-@TranDetailsThreshold*1000, @lv__SPIDCaptureTime)
		--	OR dtat.dtc_state IN (4, 5)	--4=aborted, 5=recovered
		--	--OR dtst.enlist_count > 1
		--	--OR dtst.is_enlisted = 1
		--	--OR dtst.is_bound = 1
		--)
		
		--Going to skip this "avoid chatty-ness" logic for now.
		--AND NOT EXISTS (
		--	SELECT *
		--	FROM dbo.AutoWho_TransactionDetails td2
		--	WHERE td2.session_id = sar.sess__session_id
		--	AND td2.TimeIdentifier = sar.TimeIdentifier

		--	--logically what we mean: AND DATEDIFF(second,td2.SPIDCaptureTime, @lv__SPIDCaptureTime) < @TranDetailsThreshold*1000
		--	--but coded this way for performance: 
		--	AND td2.SPIDCaptureTime > DATEADD(second, 0-@TranDetailsThreshold*1000, @lv__SPIDCaptureTime)
		--		--@TranDetailsThreshold does not just identify which SPIDs that we captured will have tran detail obtained,
		--		-- but it also identifies how long to wait before capturing that same info again. Thus, if the threshold
		--		-- is 300 seconds, then we make sure there are no other session_id/TimeIdentifier records in the table 
		--		-- with a spid capture time of < 300 seconds
		--)
		OPTION(MAXDOP 1, FORCE ORDER, KEEPFIXED PLAN);
		
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'TranCap:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END		--IF threshold variables indicate we should pull transaction data

	
	/*
		  ****     ***    *        *****  ****  *   *  *****
		 *        *   *   *          *    *      * *     *
		  ****   *     *  *          *    ****    *      *
			  *   *   *   *          *    *      * *     *
		  ****     ***    *****      *    ****  *   *    *
					  **
	*/

	SET @lv__beforedt = GETUTCDATE();

	--2016-04-19: Removed the AWStmtHash and AWBatchHash from the SQL store tables. This means that sql_handle & the offsets
	-- are our lookup values for obtaining a PK value, and we already possess those. Thus, we can update #sar right now
	-- (with stuff that already exists in the store tables) without pulling the sql text yet, and then only afterwards do the 
	-- loop that obtains sql text from the cache (for sql_handles we haven't pulled before, or that failed last time we pulled them). 
	UPDATE targ 
	SET targ.calc__FKSQLStmtStoreID = sss.PKSQLStmtStoreID
	FROM #sessions_and_requests targ 
		INNER loop JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore sss
			ON targ.rqst__sql_handle = sss.[sql_handle]
			AND targ.rqst__statement_start_offset = sss.statement_start_offset
			AND targ.rqst__statement_end_offset = sss.statement_end_offset
			AND sss.fail_to_obtain = CONVERT(BIT,0)		--at this point in the proc, we don't accept a failed attempt (i.e. we'll let this
														-- #sar row pass down to the loop for another attempt to obtain the text)
	WHERE targ.calc__return_to_user > 0
	AND targ.sess__is_user_process = 1
	AND targ.rqst__sql_handle IS NOT NULL
	AND targ.rqst__sql_handle <> 0x00
	OPTION(MAXDOP 1, FORCE ORDER);

	--if we are pulling the batch text, use the same approach
	IF @ObtainBatchText = N'Y'
	BEGIN
		UPDATE targ 
		SET targ.calc__FKSQLBatchStoreID = sbs.PKSQLBatchStoreID
		FROM #sessions_and_requests targ 
			INNER loop JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore sbs
				ON targ.rqst__sql_handle = sbs.[sql_handle]
				AND sbs.fail_to_obtain = CONVERT(BIT,0)		--don't accept a failed attempt. let this #sar row pass down to the loop for another attempt
		WHERE targ.calc__return_to_user > 0
		AND targ.sess__is_user_process = 1
		AND targ.rqst__sql_handle IS NOT NULL
		AND targ.rqst__sql_handle <> 0x00
		OPTION(MAXDOP 1, FORCE ORDER);
	END


	--Busy systems can have large #'s of SPIDs. It can be time-consuming to go through the sql_handle for each SPID,
	-- especially if a system has 100's of them actively running queries at a time. We can take advantage of the fact that
	-- many applications typically have just a few queries/batches/procs/etc that are called extremely frequently, and 
	-- save ourselves some work by constructing a DISTINCT list of sql_handles that need to be pulled. We then 
	-- iterate these sql handles and attempt to grab the batch/stmt SQL text info
	-- note that since these text objects can be locked, and grabbing the sql_handle is considered not urgent enough 
	-- to block the whole execution, we set a very short lock timeout value of 20 ms
	SET LOCK_TIMEOUT 20;

	IF @ObtainBatchText = N'Y'
	BEGIN
		SET @errorloc = N'Batch capture cursor pop';
		DECLARE getDistinctBatch CURSOR LOCAL FAST_FORWARD FOR 
			SELECT DISTINCT s.rqst__sql_handle 
			FROM #sessions_and_requests s 
			WHERE s.calc__return_to_user > 0
			AND s.sess__is_user_process = 1 
			AND s.rqst__sql_handle IS NOT NULL
			AND s.rqst__sql_handle <> 0x00
			AND s.calc__FKSQLBatchStoreID IS NULL		--above query didn't populate this field; thus, batch store
														--doesn't have the sql text yet (or previous attempts were bad)
		OPTION(MAXDOP 1, KEEPFIXED PLAN);

		OPEN getDistinctBatch;
		FETCH getDistinctBatch INTO @lv__curHandle;

		SET @errorloc = N'Batch capture loop';
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @lv__BatchesPulled = CONVERT(BIT,1);

			BEGIN TRY
				INSERT INTO #t__batch (
					[sql_handle], 
					[dbid], 
					objectid, 
					batch_text,
					fail_to_obtain)
				SELECT 
					[sql_handle] = @lv__curHandle, 
					[dbid] = ISNULL(txt.dbid,@lv__nullsmallint), 
					[objectid] = ISNULL(txt.objectid,@lv__nullint), 
					[batch_text] = ISNULL(txt.text, 'SQL batch info was NULL'), 
					[fail_to_obtain] = CASE WHEN txt.text IS NULL THEN 1 ELSE 0 END
				FROM sys.dm_exec_sql_text(@lv__curHandle) txt;
			END TRY
			BEGIN CATCH
				INSERT INTO #t__batch (sql_handle, dbid, objectid, batch_text, fail_to_obtain)
				SELECT @lv__curHandle, @lv__nullsmallint, @lv__nullint, 
					[batch_text] = 'Error obtaining Complete SQL Batch: ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + '; ' + ERROR_MESSAGE(), 
					[fail_to_obtain] = 1;
			END CATCH

			FETCH getDistinctBatch INTO @lv__curHandle;
		END

		CLOSE getDistinctBatch;
		DEALLOCATE getDistinctBatch;

		/* 2016-04-19 now that we're no longer hashing things ourselves (relying instead on sql_handle being both unique over time 
			and representative of a value that does not change (unlike plan_handle), we expect a greater % of our sql_handle resolution
			to come from the above UPDATE. Thus, to keep things simpler, we don't pull the statement/offset text from our
			batch text anymore, we just let the remaing NULL rows fall through to the next cursor.

		--Now, populate the #DistinctSQLStmt table using the statement offsets
		SET @errorloc = N'Batch capture stmt extract';
		INSERT INTO #t__stmt
			(sql_handle, 
			statement_start_offset, 
			statement_end_offset, 
			dbid, 
			objectid, 
			fail_to_obtain, 
			datalen_batch,
			stmt_text
			)	
			SELECT 
				rqst__sql_handle,
				rqst__statement_start_offset,
				rqst__statement_end_offset,
				dbid,
				objectid,
				fail_to_obtain,
				datalen_batch,
				stmt_text
			FROM (
				SELECT 
					ds.rqst__sql_handle, 
					ds.rqst__statement_start_offset, 
					ds.rqst__statement_end_offset, 
					t.dbid, 
					t.objectid, 
					t.fail_to_obtain,
					t.datalen_batch,
					CASE WHEN t.fail_to_obtain = 1 THEN t.batch_text		--in failure cases, t.batch_text contains the reason why
						ELSE (CASE 
								WHEN ds.rqst__statement_start_offset = 0 THEN 
									CASE WHEN ds.rqst__statement_end_offset IN (0,-1)
										THEN t.batch_text 
										ELSE SUBSTRING(t.batch_text, 1, ds.rqst__statement_end_offset/2 + 1) 
									END 
								WHEN datalen_batch = 0 THEN SUBSTRING(t.batch_text, (ds.rqst__statement_start_offset/2)+1, 4000)
								ELSE SUBSTRING(t.batch_text, 
												(ds.rqst__statement_start_offset/2)+1, 
												(CASE ds.rqst__statement_end_offset
													WHEN -1 THEN datalen_batch 
													ELSE ds.rqst__statement_end_offset
													END - ds.rqst__statement_start_offset
												)/2 + 1
											) 
								END 
							) END AS stmt_text
				
				FROM ( SELECT DISTINCT 
						s.rqst__sql_handle, 
						s.rqst__statement_start_offset, 
						s.rqst__statement_end_offset
					FROM #sessions_and_requests s 
					WHERE s.calc__return_to_user > 0
					AND s.sess__is_user_process = 1 
					AND s.rqst__sql_handle IS NOT NULL
					AND s.rqst__sql_handle <> 0x00
				) ds
					LEFT OUTER hash JOIN 
						(SELECT 
							sql_handle, 
							dbid, 
							objectid, 
							batch_text, 
							fail_to_obtain, 
							DATALENGTH(batch_text) as datalen_batch 
						FROM #t__batch
						) t
						ON ds.rqst__sql_handle = t.sql_handle
			) outerquery
			OPTION(FORCE ORDER, MAXDOP 1, KEEPFIXED PLAN);
		*/

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'BatchTxt:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END 


	--Get the statement text for any #sar records that weren't already resolved by the above UPDATE.
	SET @errorloc = N'Stmt capture cursor pop';
	DECLARE getDistinctText CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT s.rqst__sql_handle, s.rqst__statement_start_offset, s.rqst__statement_end_offset 
		FROM #sessions_and_requests s 
		WHERE s.calc__return_to_user > 0 
		AND s.sess__is_user_process = 1 
		AND s.rqst__sql_handle IS NOT NULL
		AND s.rqst__sql_handle <> 0x00
		AND s.calc__FKSQLStmtStoreID IS NULL
	OPTION(MAXDOP 1, KEEPFIXED PLAN);

	OPEN getDistinctText;
	FETCH getDistinctText INTO @lv__curHandle, @lv__curStatementOffsetStart, @lv__curStatementOffsetEnd;

	SET @errorloc = N'Stmt capture loop';
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @lv__StatementsPulled = CONVERT(BIT,1);

		BEGIN TRY
			INSERT INTO #t__stmt (
				sql_handle, 
				statement_start_offset, 
				statement_end_offset, 
				dbid, 
				objectid, 
				fail_to_obtain, 
				datalen_batch,
				stmt_text
			)
			SELECT curhandle,
				curoffsetstart,
				curoffsetend,
				dbid, 
				objectid,
				fail_to_obtain,
				datalen_batch,
				stmt_text
			FROM (
				SELECT curhandle = @lv__curHandle, 
					curoffsetstart = @lv__curStatementOffsetStart, 
					curoffsetend = @lv__curStatementOffsetEnd, 
					ss.dbid, 
					ss.objectid, 
					ss.fail_to_obtain,
					datalen_batch,
					[stmt_text] = CASE WHEN ss.fail_to_obtain = 1 THEN ss.stmt_text		--in failure cases, ss.stmt_text contains the reason why
						ELSE (
							CASE WHEN @lv__curStatementOffsetStart = 0 THEN 
									CASE 
										WHEN @lv__curStatementOffsetEnd IN (0,-1) 
											THEN ss.stmt_text 
										ELSE SUBSTRING(ss.stmt_text, 1, @lv__curStatementOffsetEnd/2 + 1) 
									END 
								WHEN datalen_batch = 0 THEN SUBSTRING(ss.stmt_text, (@lv__curStatementOffsetStart/2)+1, 4000)
								WHEN datalen_batch <= @lv__curStatementOffsetStart 
									THEN SUBSTRING(ss.stmt_text, 1, 4000)
								WHEN datalen_batch < @lv__curStatementOffsetEnd 
									THEN SUBSTRING(ss.stmt_text, 
												1,
												(CASE @lv__curStatementOffsetEnd
													WHEN -1 THEN datalen_batch 
													ELSE @lv__curStatementOffsetEnd
													END - @lv__curStatementOffsetStart
												)/2 + 1
											) 
								ELSE SUBSTRING(ss.stmt_text, 
												(@lv__curStatementOffsetStart/2)+1, 
												(CASE @lv__curStatementOffsetEnd
													WHEN -1 THEN datalen_batch 
													ELSE @lv__curStatementOffsetEnd
													END - @lv__curStatementOffsetStart
												)/2 + 1
											) 
									END 
							) END
				FROM 
				(SELECT [dbid] = ISNULL(txt.dbid,@lv__nullsmallint), 
						[objectid] = ISNULL(txt.objectid,@lv__nullint), 
						[stmt_text] = ISNULL(txt.text, 'SQL batch info was NULL'), 
						[fail_to_obtain] = CASE WHEN txt.text IS NULL THEN 1 ELSE 0 END,
						[datalen_batch] = DATALENGTH(txt.text)
				FROM sys.dm_exec_sql_text(@lv__curHandle) txt) ss
			) outerquery
			;
		END TRY
		BEGIN CATCH
			INSERT INTO #t__stmt (
				sql_handle, 
				statement_start_offset, 
				statement_end_offset, 
				dbid, 
				objectid, 
				fail_to_obtain, 
				datalen_batch,
				stmt_text
			)	
			SELECT @lv__curHandle, 
				@lv__curStatementOffsetStart, 
				@lv__curStatementOffsetEnd, 
				@lv__nullsmallint, 
				@lv__nullint, 
				1, 
				0, 
				'Error getting SQL statement text: ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + '; ' + ERROR_MESSAGE()
		END CATCH

		FETCH getDistinctText INTO @lv__curHandle, @lv__curStatementOffsetStart, @lv__curStatementOffsetEnd;
	END

	CLOSE getDistinctText;
	DEALLOCATE getDistinctText;

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'StmtTxt:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END


	--Go and get Query Plans.
	--NOTE: notice that we don't check whether @thresh__maxActiveDuration is >= either of the
	-- query plan threshold values. If we had done that check, we could end up with the query plan
	-- not being captured for the threshold-ignore spids if there were no other spids above the 
	-- query plan thresholds. This is a contentious choice, I suppose... if we want to ignore those spids
	-- (e.g. because they run all day), then do we really want their query plan being pulled every time?
	-- I'm still considering how best to handle threshold-ignore spids.
	IF @ObtainQueryPlanForBatch = N'Y' AND @thresh__QueryPlansNeeded > 0
	BEGIN
		SET @errorloc = N'PlanBatch capture cursor pop';
		DECLARE getDistinctPlanHandles1 CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT s.rqst__plan_handle
		FROM #sessions_and_requests s 
		WHERE s.calc__return_to_user > 0 
		AND s.rqst__request_id <> @lv__nullsmallint
		AND s.sess__is_user_process = 1 
		AND s.rqst__plan_handle IS NOT NULL
		AND s.rqst__plan_handle <> 0x0
		AND (
			(s.calc__block_relevant = 1 AND s.calc__duration_ms >= @QueryPlanThresholdBlockRel)
			OR 
			(s.calc__threshold_ignore = 1 AND s.rqst__FKDimWaitType <> 2 )
			OR
			(isnull(s.calc__threshold_ignore,0) = 0 AND s.calc__duration_ms >= @QueryPlanThreshold)
			)
		OPTION(MAXDOP 1, KEEPFIXED PLAN);

		OPEN getDistinctPlanHandles1;
		FETCH getDistinctPlanHandles1 INTO @lv__curHandle;

		SET @errorloc = N'PlanBatch capture loop';
		WHILE @@FETCH_STATUS = 0
		BEGIN
			BEGIN TRY
				INSERT INTO #t__batchqp (
					[plan_handle], 
					[dbid],
					[objectid],
					[fail_to_obtain], 
					[query_plan],
					[aw_batchplan_hash]
				)
				SELECT 
					curHandle,
					[dbid],
					objectid,
					fail_to_obtain,
					[query_plan],
					[aw_batchplan_hash] = HASHBYTES('MD5',
						(SUBSTRING(query_plan,1,3940) +
						CONVERT(NVARCHAR(40),CHECKSUM(query_plan)))
					)
					--HASHBYTES('MD5',qp.query_plan),		--HASHBYTES only takes 8000 chars of input
															--so replaced this code with a HASHBYTES call
															-- that operates on the first 3940 chars of
															-- the plan + a CHECKSUM() of the whole plan
				FROM (
					SELECT @lv__curHandle as curHandle, 
						[dbid] = ISNULL(s2.dbid,@lv__nullsmallint),
						[objectid] = ISNULL(s2.objectid,@lv__nullint),
						CASE WHEN query_plan IS NULL THEN 1 ELSE 0 END as fail_to_obtain,

						[query_plan] = 
							CASE 
								WHEN s2.row_exists IS NULL 
									THEN '<?PlanError -- ' + CHAR(13) + CHAR(10) + 'Query Plan DMV did not return a row' + CHAR(13) + CHAR(10) + '-- ?>'
								WHEN s2.row_exists IS NOT NULL AND s2.query_plan IS NULL 
									THEN '<?PlanError -- ' + CHAR(13) + CHAR(10) + 'Batch Query Plan is NULL' + CHAR(13) + CHAR(10) + '-- ?>'
								ELSE s2.query_plan
							END
					FROM
						(SELECT 0 AS col1) s
						LEFT OUTER JOIN 
						(SELECT 1 AS row_exists, t.dbid, t.objectid, t.query_plan
						FROM sys.dm_exec_text_query_plan(@lv__curHandle, 0, -1) t) s2
							ON 1=1
				) s3;

			END TRY
			BEGIN CATCH
				INSERT INTO #t__batchqp (
					[plan_handle], 
					[dbid],
					[objectid],
					[fail_to_obtain], 
					[query_plan],
					[aw_batchplan_hash]
				)
				SELECT @lv__curHandle, @lv__nullsmallint, @lv__nullint, 
					1 as fail_to_obtain, 
					N'<?PlanError -- ' + NCHAR(13) + NCHAR(10) + N'Error obtaining Batch Query Plan: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()),N'<null>') + N'; ' + ISNULL(ERROR_MESSAGE(),N'<null>') + NCHAR(13) + NCHAR(10) + N'-- ?>',
					HASHBYTES('MD5', 
						N'<?PlanError -- ' + NCHAR(13) + NCHAR(10) + N'Error obtaining Batch Query Plan: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()),N'<null>') + N'; ' + ISNULL(ERROR_MESSAGE(),N'<null>') + CHAR(13) + CHAR(10) + N'-- ?>'
						)
					;
			END CATCH 
			FETCH getDistinctPlanHandles1 INTO @lv__curHandle;
		END 

		CLOSE getDistinctPlanHandles1;
		DEALLOCATE getDistinctPlanHandles1;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'PlanBatch:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END


	--NOTE: notice that we don't check whether @thresh__maxActiveDuration is >= either of the
	-- query plan threshold values. If we had done that check, we could end up with the query plan
	-- not being captured for the threshold-ignore spids if there were no other spids above the 
	-- query plan thresholds. This is a contentious choice, I suppose... if we want to ignore those spids
	-- (e.g. because they run all day), then do we really want their query plan being pulled every time?
	-- I'm still considering how best to handle threshold-ignore spids.
	IF @ObtainQueryPlanForStatement = N'Y' AND @thresh__QueryPlansNeeded > 0
	BEGIN
		SET @errorloc = N'PlanStmt cursor pop';
		DECLARE getDistinctPlanHandles2 CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT s.rqst__plan_handle, s.rqst__statement_start_offset, s.rqst__statement_end_offset
		FROM #sessions_and_requests s 
		WHERE s.calc__return_to_user > 0 
		AND s.rqst__request_id <> @lv__nullsmallint
		AND s.sess__is_user_process = 1 
		AND s.rqst__plan_handle IS NOT NULL
		AND s.rqst__plan_handle <> 0x0
		AND (
			(s.calc__block_relevant = 1 AND s.calc__duration_ms >= @QueryPlanThresholdBlockRel)
			OR 
			(s.calc__threshold_ignore = 1 AND s.rqst__FKDimWaitType <> 2 )
			OR
			(ISNULL(s.calc__threshold_ignore,0) = 0 AND s.calc__duration_ms >= @QueryPlanThreshold)
			)
		OPTION(MAXDOP 1, KEEPFIXED PLAN);

		OPEN getDistinctPlanHandles2;
		FETCH getDistinctPlanHandles2 INTO @lv__curHandle, @lv__curStatementOffsetStart, @lv__curStatementOffsetEnd;

		SET @errorloc = N'PlanStmt cursor loop';
		WHILE @@FETCH_STATUS = 0
		BEGIN
			--since I've seen cases where the statement_start_offset and statement_end_offset are a little funky, 
			-- do a bit of edge-case handling (where we'll just get the full plan instead)
			IF @lv__curStatementOffsetStart = 0 
			BEGIN
				IF @lv__curStatementOffsetEnd IN (0,-1)
				BEGIN
					SET @lv__usedStartOffset = 0;
					SET @lv__usedEndOffset = -1;
				END
				ELSE
				BEGIN
					SET @lv__usedStartOffset = 0;
					SET @lv__usedEndOffset = @lv__curStatementOffsetEnd;
				END
			END
			ELSE
			BEGIN
				SET @lv__usedStartOffset = @lv__curStatementOffsetStart;
				SET @lv__usedEndOffset = @lv__curStatementOffsetEnd;
			END

			BEGIN TRY
				INSERT INTO #t__stmtqp (
					[plan_handle],
					[statement_start_offset],
					[statement_end_offset],
					[dbid],
					[objectid],
					[fail_to_obtain],
					[query_plan],
					[aw_stmtplan_hash]
				)
				SELECT 
					curHandle,
					curstartoffset,
					curendoffset,
					[dbid], 
					objectid,
					fail_to_obtain,
					query_plan,
					aw_stmtplan_hash = HASHBYTES('MD5',
						(SUBSTRING(query_plan,1,3940) +
						CONVERT(nvarchar(40),CHECKSUM(query_plan)))
						)
				FROM (
					SELECT 
						curHandle = @lv__curHandle, 
						--Note that we store the offsets we were given, not the ones we actually used
						-- (@lv__usedStartOffset/EndOffset). This makes troubleshooting this code & resulting plans easier
						curstartoffset = @lv__curStatementOffsetStart, 
						curendoffset = @lv__curStatementOffsetEnd,
						[dbid] = ISNULL(dbid,@lv__nullsmallint),
						[objectid] = ISNULL(objectid,@lv__nullint),
						[fail_to_obtain] = CASE WHEN query_plan IS NULL THEN 1 ELSE 0 END, 
						[query_plan] = 
							CASE 
								WHEN s2.row_exists IS NULL 
									THEN '<?PlanError -- ' + CHAR(13) + CHAR(10) + 'Query Plan DMV did not return a row' + CHAR(13) + CHAR(10) + '-- ?>'
								WHEN s2.row_exists IS NOT NULL AND s2.query_plan IS NULL 
									THEN '<?PlanError -- ' + CHAR(13) + CHAR(10) + 'Statement Query Plan is NULL' + CHAR(13) + CHAR(10) + '-- ?>'
								ELSE s2.query_plan
							END
					FROM
						(SELECT 0 as col1) s
						LEFT OUTER JOIN 
						(SELECT 1 as row_exists, t.dbid, t.objectid, t.query_plan
							FROM sys.dm_exec_text_query_plan(@lv__curHandle, @lv__usedStartOffset, @lv__usedEndOffset) t) s2
							ON 1=1
				) s3;
			END TRY
			BEGIN CATCH
				INSERT INTO #t__stmtqp (
					[plan_handle],
					[statement_start_offset],
					[statement_end_offset],
					[dbid],
					[objectid],
					[fail_to_obtain],
					[query_plan],
					[aw_stmtplan_hash]
				)
				SELECT curHandle = @lv__curHandle,
					curstartoffset = @lv__curStatementOffsetStart,
					curendoffset = @lv__curStatementOffsetEnd,
					@lv__nullsmallint,
					@lv__nullint,
					1 as fail_to_obtain, 
					--'Error obtaining Statement Query Plan: ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + '; ' + ERROR_MESSAGE()
					N'<?PlanError -- ' + NCHAR(13) + NCHAR(10) + N'Error obtaining Statement Query Plan: ' + isnull(CONVERT(NVARCHAR(20),ERROR_NUMBER()),N'<null>') + N'; ' + isnull(ERROR_MESSAGE(),N'<null>') + NCHAR(13) + NCHAR(10) + N'-- ?>',
					HASHBYTES('MD5', 
						N'<?PlanError -- ' + NCHAR(13) + NCHAR(10) + N'Error obtaining Statement Query Plan: ' + isnull(CONVERT(NVARCHAR(20),ERROR_NUMBER()),N'<null>') + N'; ' + isnull(ERROR_MESSAGE(),N'<null>') + NCHAR(13) + NCHAR(10) + N'-- ?>'
						);
			END CATCH 
			FETCH getDistinctPlanHandles2 INTO @lv__curHandle, @lv__curStatementOffsetStart, @lv__curStatementOffsetEnd;
		END 

		CLOSE getDistinctPlanHandles2;
		DEALLOCATE getDistinctPlanHandles2;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'PlanStmt:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	SET LOCK_TIMEOUT -1;

	/***************************************************************************************************************************
												End Of "SQL Text" section
	***************************************************************************************************************************/


	--The Lock Info auxiliary capture is saved for last since it can be very time-consuming. It isn't possible to 
	-- capture ALL of the DMV info that we want in such a way as for it to represent the exact same point in time. 
	-- (In fact, even the initial #sar population statement represents slightly different points in time for each of the DMVs,
	-- or even rows, that are captured). Thus, we are presenting the "illusion" of a point-in-time capture. However, the
	-- closer in time each capture is to each other, the closer this illusion is to reality. Thus, we save the potentially-expensive
	-- lock info capture until last, and the only items after it are "persists" of data we already captured above.
	IF @thresh__maxWaitLength_BlockedSPID >= @ObtainLocksForBlockRelevantThreshold
	BEGIN
		SET @errorloc = N'Lock capture query';

		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_LockDetails (
			CollectionInitiatorID,
			UTCCaptureTime,
			SPIDCaptureTime, 
			request_session_id, 
			request_request_id, 
			TimeIdentifier, 
			request_exec_context_id, 
			request_owner_type, 
			request_owner_id, 
			request_owner_guid, 
			resource_type, 
			resource_subtype, 
			resource_database_id, 
			resource_description, 
			resource_associated_entity_id, 
			resource_lock_partition, 
			request_mode, 
			request_type, 
			request_status, 
			RecordCount 
		)
		SELECT 
			@CollectionInitiatorID,
			UTCCaptureTime,
			SPIDCaptureTime,
			request_session_id,
			request_request_id,
			TimeIdentifier,
			request_exec_context_id,
			request_owner_type,
			request_owner_id, 
			request_owner_guid,
			resource_type,
			resource_subtype,
			resource_database_id,
			resource_description,
			resource_associated_entity_id,
			resource_lock_partition,
			request_mode,
			request_type,
			request_status,
			COUNT(*)
		FROM (
			SELECT
				UTCCaptureTime = @lv__UTCCaptureTime,
				SPIDCaptureTime = @lv__SPIDCaptureTime,
				l.request_session_id,		--BOL: The owning session ID can change for distributed and bound transactions. A value of -2 indicates that the request 
											-- belongs to an orphaned distributed transaction. A value of -3 indicates that the request belongs to a deferred recovery 
											-- transaction, such as, a transaction for which a rollback has been deferred at recovery because the rollback could not be 
											-- completed successfully.
				l.request_request_id,
				sar.TimeIdentifier,
				l.request_exec_context_id,

				request_owner_type = CASE l.request_owner_type
										WHEN N'TRANSACTION' THEN CONVERT(TINYINT,0)
										WHEN N'CURSOR' THEN CONVERT(TINYINT,1)
										WHEN N'SESSION' THEN CONVERT(TINYINT,2)
										WHEN N'SHARED_TRANSACTION_WORKSPACE' THEN CONVERT(TINYINT,3)
										WHEN N'EXCLUSIVE_TRANSACTION_WORKSPACE' THEN CONVERT(TINYINT,4)
										WHEN N'NOTIFICATION_OBJECT' THEN CONVERT(TINYINT,5)
										ELSE CONVERT(TINYINT,250)
									END ,
											--Aaron: I have put tinyint codes to the left of each label below. Use a view to manage the translation?
											--Entity type that owns the request. Lock manager requests can be owned by a variety of entities. Possible values are:
											-- 0 TRANSACTION = The request is owned by a transaction.
											-- 1 CURSOR = The request is owned by a cursor.
											-- 2 SESSION = The request is owned by a user session.
											-- 3 SHARED_TRANSACTION_WORKSPACE = The request is owned by the shared part of the transaction workspace.
											-- 4 EXCLUSIVE_TRANSACTION_WORKSPACE = The request is owned by the exclusive part of the transaction workspace.
											-- 5 NOTIFICATION_OBJECT = The request is owned by an internal SQL Server component. This component has requested the 
											--		lock manager to notify it when another component is waiting to take the lock. The FileTable feature is a 
											--		component that uses this value.

											-- (Work spaces are used internally to hold locks for enlisted sessions.)

				l.request_owner_id,			--When a transaction is the owner of the request, this value contains the transaction ID.
											-- When a FileTable is the owner of the request, request_owner_id has one of the following values:
											--		-4  --> A FileTable has taken a database lock.
											--		-3  --> A FileTable has taken a table lock.
											--	Other value --> The value represents a file handle. This value also appears as fcb_id 
											--					in the dynamic management view sys.dm_filestream_non_transacted_handles (Transact-SQL).
											--Aaron: DB "S" locks (usually? always?) have "0" for this column

				request_owner_guid = CASE WHEN l.request_owner_guid = '00000000-0000-0000-0000-000000000000' THEN ''
										ELSE CONVERT(VARCHAR(36), l.request_owner_guid) END,
											--This value is only used by a distributed transaction where the value corresponds to the MS DTC GUID for that transaction.
											--Aaron: since it is often "00000000-0000-0000-0000-000000000000", convert to varchar and only store empty strings for 
											--that value to save space

				--do not capture l.request_owner_lockspace_id,	--Identified for informational purposes only. Not supported. Future compatibility is not guaranteed. 
												-- This value represents the lockspace ID of the requestor. The lockspace ID determines whether two requestors are 
												-- compatible with each other and can be granted locks in modes that would otherwise conflict with one another.

				--do not capture l.lock_owner_address,		--Memory address of the internal data structure that is used to track this request. This column can be joined the with 
											-- the resource_address column in sys.dm_os_waiting_tasks.

				l.resource_type,		--BOL: The value can be one of the following: DATABASE, FILE, OBJECT, PAGE, KEY, EXTENT, RID, APPLICATION, METADATA, HOBT, or ALLOCATION_UNIT.

				l.resource_subtype,		--BOL: Represents a subtype of resource_type. Acquiring a subtype lock without holding a nonsubtyped lock of the parent type is technically 
										-- valid. Different subtypes do not conflict with each other or with the nonsubtyped parent type. Not all resource types have subtypes.
				l.resource_database_id, 
				resource_description = CASE WHEN l.resource_type IN (N'PAGE',N'EXTENT',N'KEY',N'RID') THEN N''
											ELSE l.resource_description
										END,
				l.resource_associated_entity_id,		--BOL: This can be an object ID, Hobt ID, or an Allocation Unit ID, depending on the resource type.
				l.resource_lock_partition,
				l.request_mode,				--BOL: Mode of the request. For granted requests, this is the granted mode; for waiting requests, this is the mode being requested.
				l.request_type,				--BOL: Request type. The value is LOCK.
				l.request_status			--BOL: Possible values are GRANTED, CONVERT, WAIT, LOW_PRIORITY_CONVERT, LOW_PRIORITY_WAIT, or ABORT_BLOCKERS
				--l.request_reference_count	--BOL: Returns an approximate number of times the same requestor has requested this resource.
				--l.request_lifetime,			--BOL: Identified for informational purposes only. Not supported. Future compatibility is not guaranteed.

			FROM (
				--a) grab list of spids that are blocked, and their blocked duration is >= our threshold
				--b) grab list of spids that are blockers of a)
				SELECT sess__session_id, rqst__request_id, TimeIdentifier
				FROM (
					SELECT sar.sess__session_id, 
					--This DMV has a quirk, where even if a spid is IDLE, it will have a request_request_id value of 0 instead of NULL.
					-- Thus, we need to replace our "special null value" in the SAR table with 0 to ensure that we get a match on the join
					-- criteria below.
						rqst__request_id = ISNULL(NULLIF(sar.rqst__request_id,@lv__nullsmallint),0),
						sar.TimeIdentifier
					FROM #tasks_and_waits taw
						INNER hash JOIN 
						#sessions_and_requests sar 
							ON taw.session_id = sar.sess__session_id
							AND taw.request_id = sar.rqst__request_id
					WHERE sar.calc__return_to_user > 0
					AND sar.calc__block_relevant = 1
					AND taw.task_priority = 1		--only consider the longest wait for a request
					AND taw.blocking_session_id IS NOT NULL  --remember, we have already set this field to NULL if it = session_id (CXP waits)
					AND taw.wait_duration_ms >= @ObtainLocksForBlockRelevantThreshold
				) blocked

				UNION 

				SELECT sess__session_id, rqst__request_id, TimeIdentifier
				FROM (
					SELECT sar2.sess__session_id, 
					--This DMV has a quirk, where even if a spid is IDLE, it will have a request_request_id value of 0 instead of NULL.
					-- Thus, we need to replace our "special null value" in the SAR table with 0 to ensure that we get a match on the join
					-- criteria below.
						rqst__request_id = ISNULL(NULLIF(sar2.rqst__request_id,@lv__nullsmallint),0),
						sar2.TimeIdentifier
					FROM #tasks_and_waits taw
						INNER hash JOIN 
						#sessions_and_requests sar 
							ON taw.session_id = sar.sess__session_id
							AND taw.request_id = sar.rqst__request_id
						INNER hash JOIN #sessions_and_requests sar2
							ON sar.calc__blocking_session_id = sar2.sess__session_id
					WHERE sar.calc__return_to_user > 0
					AND sar.calc__block_relevant = 1
					AND taw.task_priority = 1		--only consider the longest wait for a request
					AND taw.blocking_session_id IS NOT NULL  --remember, we have already set this field to NULL if it = session_id (CXP waits)
					AND taw.wait_duration_ms >= @ObtainLocksForBlockRelevantThreshold
				) blockers
			) sar
			INNER hash JOIN sys.dm_tran_locks l
				ON sar.sess__session_id = l.request_session_id
				AND sar.rqst__request_id = l.request_request_id
		) ss
		GROUP BY 
			UTCCaptureTime,
			SPIDCaptureTime,
			request_session_id,
			request_request_id,
			TimeIdentifier,
			request_exec_context_id,
			request_owner_type,
			request_owner_id, 
			request_owner_guid,
			resource_type,
			resource_subtype,
			resource_database_id,
			resource_description,
			resource_associated_entity_id,
			resource_lock_partition,
			request_mode,
			request_type,
			request_status
		OPTION(MAXDOP 1, FORCE ORDER, KEEPFIXED PLAN);

		IF @@ROWCOUNT > 0 
		BEGIN
			SET @errorloc = N'Lock capture special row';
			INSERT INTO #sessions_and_requests (
				sess__session_id,
				rqst__request_id,
				TimeIdentifier,
				calc__record_priority,
				calc__block_relevant,
				calc__return_to_user
			)
			SELECT 
				session_id = CONVERT(SMALLINT,-996),
				request_id = @lv__nullsmallint,
				TimeIdentifier = @lv__nulldatetime,
				calc__record_priority = CONVERT(TINYINT,4),
				calc__block_relevant = CONVERT(TINYINT,1),
				calc__return_to_user = CONVERT(SMALLINT,130)
			;
		END

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'LockCap:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END		--IF @thresh__maxWaitLength_BlockedSPID >= @ObtainLocksForBlockRelevantThreshold


	--If we have a Bchain, insert a -997 record
	IF @lv__BChainRecsExist = 1
	BEGIN
		SET @errorloc = N'BChain special row';
		INSERT INTO #sessions_and_requests (
			sess__session_id,
			rqst__request_id,
			TimeIdentifier,
			calc__record_priority,
			calc__block_relevant,
			calc__return_to_user
		)
		SELECT 
			session_id = CONVERT(SMALLINT,-997),
			request_id = @lv__nullsmallint,
			TimeIdentifier = @lv__nulldatetime,
			calc__record_priority = CONVERT(TINYINT,3),
			calc__block_relevant = CONVERT(TINYINT,1),
			calc__return_to_user = CONVERT(SMALLINT,129)
		;
	END


	-- Update dimensions, if necessary
	IF @NewDims__Command > 0
	BEGIN
		SET @errorloc = N'DimCommand population';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimCommand 
		(command, TimeAdded, TimeAddedUTC)
		SELECT rqst__command, @lv__SPIDCaptureTime, @lv__UTCCaptureTime
		FROM (
			SELECT DISTINCT sar.rqst__command
			FROM #sessions_and_requests sar
			WHERE sar.rqst__FKDimCommand IS NULL
			AND sar.sess__session_id > 0			--negative spids are our "special" spids, and don't have this field
			AND sar.calc__return_to_user > 0
		) ss
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
		WHERE NOT EXISTS (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimCommand dc2
			WHERE dc2.command = ss.rqst__Command
		)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopCommand:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @NewDims__ConnectionAttribute > 0
	BEGIN
		SET @errorloc = N'DimConnectionAttribute population';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute
		(net_transport, protocol_type, protocol_version, endpoint_id,
			node_affinity, net_packet_size, encrypt_option, auth_scheme, TimeAdded, TimeAddedUTC)
		SELECT
			conn__net_transport, conn__protocol_type, 
			conn__protocol_version, conn__endpoint_id, conn__node_affinity,
			conn__net_packet_size, conn__encrypt_option, conn__auth_scheme, @lv__SPIDCaptureTime, @lv__UTCCaptureTime
		FROM (
			SELECT DISTINCT sar.conn__net_transport, sar.conn__protocol_type, 
				sar.conn__protocol_version, sar.conn__endpoint_id, sar.conn__node_affinity,
				sar.conn__net_packet_size, sar.conn__encrypt_option, sar.conn__auth_scheme
			FROM #sessions_and_requests sar
			WHERE sar.conn__FKDimConnectionAttribute IS NULL
			AND sar.sess__session_id > 0			--negative spids are our "special" spids, and don't have this field
			AND sar.calc__return_to_user > 0
		) ss
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
		WHERE NOT EXISTS (
			SELECT * 
			FROM @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca2
			WHERE ss.conn__net_transport = dca2.net_transport
			AND ss.conn__protocol_type = dca2.protocol_type
			AND ss.conn__protocol_version = dca2.protocol_version
			AND ss.conn__endpoint_id = dca2.endpoint_id
			AND ss.conn__node_affinity = dca2.node_affinity
			AND ss.conn__net_packet_size = dca2.net_packet_size
			AND ss.conn__encrypt_option = dca2.encrypt_option
			AND ss.conn__auth_scheme = dca2.auth_scheme
		)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopConnAttr:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @NewDims__LoginName > 0
	BEGIN
		SET @errorloc = N'DimLoginName population';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName
		(login_name, original_login_name, TimeAdded, TimeAddedUTC)
		SELECT sess__login_name, sess__original_login_name, @lv__SPIDCaptureTime, @lv__UTCCaptureTime
		FROM (
			SELECT DISTINCT sess__login_name, sess__original_login_name
			FROM #sessions_and_requests sar
			WHERE sar.sess__FKDimLoginName IS NULL
			AND sar.sess__session_id > 0			--negative spids are our "special" spids, and don't have this field
			AND sar.calc__return_to_user > 0
		) ss
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
		WHERE NOT EXISTS (
			SELECT *
			FROM @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln2
			WHERE ss.sess__login_name = dln2.login_name
			AND ss.sess__original_login_name = dln2.original_login_name
		)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopLogin:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @NewDims__NetAddress > 0
	BEGIN
		SET @errorloc = N'DimNetAddress population';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress
		(client_net_address, local_net_address, local_tcp_port, TimeAdded, TimeAddedUTC)
		SELECT conn__client_net_address, conn__local_net_address, conn__local_tcp_port, @lv__SPIDCaptureTime, @lv__UTCCaptureTime
		FROM (
			SELECT DISTINCT sar.conn__client_net_address, sar.conn__local_net_address, sar.conn__local_tcp_port
			FROM #sessions_and_requests sar
			WHERE sar.conn__FKDimNetAddress IS NULL
			AND sar.sess__session_id > 0			--negative spids are our "special" spids, and don't have this field
			AND sar.calc__return_to_user > 0
		) ss
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
		WHERE NOT EXISTS (
			SELECT *
			FROM @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna2
			WHERE ss.conn__client_net_address = dna2.client_net_address
			AND ss.conn__local_net_address = dna2.local_net_address
			AND ss.conn__local_tcp_port = dna2.local_tcp_port
		)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopNetAddr:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @NewDims__SessionAttribute > 0
	BEGIN
		SET @errorloc = N'DimSessionAttribute';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute
		([host_name], [program_name], client_version, client_interface_name, endpoint_id, 
			transaction_isolation_level, [deadlock_priority], group_id, TimeAdded, TimeAddedUTC)
		SELECT 
			sess__host_name, sess__program_name, sess__client_version, sess__client_interface_name, sess__endpoint_id,
			sess__transaction_isolation_level, sess__deadlock_priority, sess__group_id, @lv__SPIDCaptureTime, @lv__UTCCaptureTime
		FROM (
			SELECT DISTINCT sar.sess__host_name, sar.sess__program_name, sar.sess__client_version,
				sar.sess__client_interface_name, sar.sess__endpoint_id, 
				sar.sess__transaction_isolation_level, sar.sess__deadlock_priority, sar.sess__group_id
			FROM #sessions_and_requests sar
			WHERE sar.sess__FKDimSessionAttribute IS NULL
			AND sar.sess__session_id > 0			--negative spids are our "special" spids, and don't have this field
			AND sar.calc__return_to_user > 0
		) ss
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
		WHERE NOT EXISTS (
			SELECT *
			FROM @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa2
			WHERE ss.sess__host_name = dsa2.host_name
			AND ss.sess__program_name = dsa2.program_name
			AND ss.sess__client_version = dsa2.client_version
			AND ss.sess__client_interface_name = dsa2.client_interface_name
			AND ss.sess__endpoint_id = dsa2.endpoint_id
			AND ss.sess__transaction_isolation_level = dsa2.transaction_isolation_level
			AND ss.sess__deadlock_priority = dsa2.deadlock_priority
			AND ss.sess__group_id = dsa2.group_id
		)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopSessAttr:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @NewDims__WaitType_sar > 0
	BEGIN
		SET @errorloc = N'DimWaitType population SAR';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType
		(wait_type, wait_type_short, latch_subtype, TimeAdded, TimeAddedUTC)
		SELECT 
			rqst__wait_type,
			wait_type_short,
			rqst__wait_latch_subtype,
			@lv__SPIDCaptureTime,
			@lv__UTCCaptureTime
		FROM (
			SELECT 
				rqst__wait_type, 
				[wait_type_short] = 
				REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				REPLACE(REPLACE(REPLACE(
					rqst__wait_type,
					'SLEEP_TASK','SlpTsk'),
					'PAGEIOLATCH','PgIO'),
					'PAGELATCH','Pg'),
					'CXPACKET','CXP'),
					'THREADPOOL','ThrPool'),				--5
					'ASYNC_IO_COMPLETION', 'AsyncIOComp'),
					'ASYNC_NETWORK_IO', 'AsyncNetIO'),
					'BACKUPBUFFER','BkpBuf'),
					'BACKUPIO', 'BkpIO'),
					'BACKUPTHREAD', 'BkpThrd'),				--10
					'IO_COMPLETION', 'IOcomp'),
					'LOGBUFFER', 'LogBuf'),
					'RESOURCE_SEMAPHORE', 'RsrcSem'),
					'RESOURCE_SEMAPHORE_QUERY_COMPILE', 'RsrcSemQryComp'),
					'TRACEWRITE', 'TrcWri'),				--15
					'WRITE_COMPLETION', 'WriComp'),
					'WRITELOG', 'WriLog'),
					'PREEMPTIVE', 'PREm'),					--18
				rqst__wait_latch_subtype
			FROM (
				SELECT DISTINCT sar.rqst__wait_type, sar.rqst__wait_latch_subtype
				FROM #sessions_and_requests sar
				WHERE sar.rqst__FKDimWaitType IS NULL
				AND sar.rqst__wait_type IS NOT NULL
				AND sar.sess__session_id > 0			--negative spids are our "special" spids, and don't have this field
			) ss
		) ss2
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
		WHERE NOT EXISTS (
			SELECT *
			FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt2
			WHERE dwt2.wait_type = ss2.rqst__wait_type
			AND dwt2.wait_type_short = ss2.wait_type_short
			AND dwt2.latch_subtype = ss2.rqst__wait_latch_subtype
		)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopSARDWT:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @NewDims__WaitType_taw > 0
	BEGIN
		SET @errorloc = N'DimWaitType population TAW';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType 
		(wait_type, wait_type_short, latch_subtype, TimeAdded, TimeAddedUTC)
		SELECT 
			ss2.wait_type,
			ss2.wait_type_short, 
			ss2.wait_latch_subtype,
			@lv__SPIDCaptureTime,
			@lv__UTCCaptureTime
		FROM (
			SELECT 
				taw.wait_type,
				[wait_type_short] = 
				REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				REPLACE(REPLACE(REPLACE(
					taw.wait_type,
					'SLEEP_TASK','SlpTsk'),
					'PAGEIOLATCH','PgIO'),
					'PAGELATCH','Pg'),
					'CXPACKET','CXP'),
					'THREADPOOL','ThrPool'),				--5
					'ASYNC_IO_COMPLETION', 'AsyncIOComp'),
					'ASYNC_NETWORK_IO', 'AsyncNetIO'),
					'BACKUPBUFFER','BkpBuf'),
					'BACKUPIO', 'BkpIO'),
					'BACKUPTHREAD', 'BkpThrd'),				--10
					'IO_COMPLETION', 'IOcomp'),
					'LOGBUFFER', 'LogBuf'),
					'RESOURCE_SEMAPHORE', 'RsrcSem'),
					'RESOURCE_SEMAPHORE_QUERY_COMPILE', 'RsrcSemQryComp'),
					'TRACEWRITE', 'TrcWri'),				--15
					'WRITE_COMPLETION', 'WriComp'),
					'WRITELOG', 'WriLog'),
					'PREEMPTIVE', 'PREm'),					--18
					wait_latch_subtype
			FROM 
				(SELECT DISTINCT wait_type, t.wait_latch_subtype
				FROM #tasks_and_waits t
				WHERE t.wait_type IS NOT NULL
				) taw
		) ss2
		--We used to not need this (when the Collector proc only ever ran once, through the Executor and
		-- protected by app locks). Now, we need to protect against race conditions when the Collector
		-- is running both through the Executor and by an end user
			LEFT OUTER hash JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
				ON ss2.wait_type = dwt.wait_type
				AND ss2.wait_type_short = dwt.wait_type_short
				AND ss2.wait_latch_subtype = dwt.latch_subtype
		WHERE dwt.wait_type IS NULL
		OPTION(FORCE ORDER, MAXDOP 1, KEEPFIXED PLAN)
		;
		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimPopTAWDWT:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END


	--IF any of our #sar @NewDims values were > 0, we need to update the #sar table with the new surrogate key values
	-- Let's do this as dynamic SQL so that we only pass over the #sar table once
	IF @NewDims__Command > 0 OR @NewDims__ConnectionAttribute > 0 OR @NewDims__LoginName > 0 
		OR @NewDims__NetAddress > 0 OR @NewDims__SessionAttribute > 0 OR @NewDims__WaitType_sar > 0
	BEGIN
		SET @errorloc = N'DimUpdate DynSQL';

		SET @lv__BigNvar = N'
			UPDATE sar 
			SET ' + CASE WHEN @NewDims__Command > 0 THEN '
			sar.rqst__FKDimCommand = ISNULL(sar.rqst__FKDimCommand,dco.DimCommandID), ' ELSE '' END +
				CASE WHEN @NewDims__ConnectionAttribute > 0 THEN '
			sar.conn__FKDimConnectionAttribute = ISNULL(sar.conn__FKDimConnectionAttribute,dca.DimConnectionAttributeID), ' ELSE '' END + 
				CASE WHEN @NewDims__LoginName > 0 THEN '
			sar.sess__FKDimLoginName = ISNULL(sar.sess__FKDimLoginName,dln.DimLoginNameID), ' ELSE '' END +
				CASE WHEN @NewDims__NetAddress > 0 THEN '
			sar.conn__FKDimNetAddress = ISNULL(sar.conn__FKDimNetAddress,dna.DimNetAddressID), ' ELSE '' END + 
				CASE WHEN @NewDims__SessionAttribute > 0 THEN '
			sar.sess__FKDimSessionAttribute = ISNULL(sar.sess__FKDimSessionAttribute,dsa.DimSessionAttributeID), ' ELSE '' END + 
				CASE WHEN @NewDims__WaitType_sar > 0 THEN '
			sar.rqst__FKDimWaitType = ISNULL(sar.rqst__FKDimWaitType,dwt.DimWaitTypeID), ' ELSE '' END +

			' calc__return_to_user = calc__return_to_user
			FROM ';

		IF @NewDims__Command > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' @@CHIRHO_SCHEMA@@.AutoWho_DimCommand dco RIGHT OUTER hash JOIN
			';
		END

		IF @NewDims__ConnectionAttribute > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca RIGHT OUTER hash JOIN
			';
		END

		IF @NewDims__LoginName > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln RIGHT OUTER hash JOIN
			';
		END

		IF @NewDims__NetAddress > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna RIGHT OUTER hash JOIN
			';
		END

		IF @NewDims__SessionAttribute > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa RIGHT OUTER hash JOIN
			';
		END

		IF @NewDims__WaitType_sar > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt RIGHT OUTER hash JOIN
			';
		END

		--
		SET @lv__BigNvar = @lv__BigNvar + N' #sessions_and_requests sar
		';
		--

		IF @NewDims__WaitType_sar > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' 
				ON dwt.wait_type = sar.rqst__wait_type
				AND dwt.latch_subtype = sar.rqst__wait_latch_subtype
			';
		END

		IF @NewDims__SessionAttribute > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' 
				ON dsa.host_name = sar.sess__host_name
				AND dsa.program_name = sar.sess__program_name
				AND dsa.client_version = sar.sess__client_version
				AND dsa.client_interface_name = sar.sess__client_interface_name
				AND dsa.endpoint_id = sar.sess__endpoint_id
				AND dsa.transaction_isolation_level = sar.sess__transaction_isolation_level
				AND dsa.deadlock_priority = sar.sess__deadlock_priority
				AND dsa.group_id = sar.sess__group_id
			';
		END

		IF @NewDims__NetAddress > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' 
				ON dna.client_net_address = sar.conn__client_net_address
				AND dna.local_net_address = sar.conn__local_net_address
				AND dna.local_tcp_port = sar.conn__local_tcp_port
			';
		END

		IF @NewDims__LoginName > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' 
				ON dln.login_name = sar.sess__login_name
				AND dln.original_login_name = sar.sess__original_login_name
			';
		END

		IF @NewDims__ConnectionAttribute > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' 
			ON dca.net_transport = sar.conn__net_transport
			AND dca.protocol_type = sar.conn__protocol_type
			AND dca.protocol_version = sar.conn__protocol_version
			AND dca.endpoint_id = sar.conn__endpoint_id
			AND dca.node_affinity = sar.conn__node_affinity
			AND dca.net_packet_size = sar.conn__net_packet_size
			AND dca.encrypt_option = sar.conn__encrypt_option
			AND dca.auth_scheme = sar.conn__auth_scheme
			';
		END

		IF @NewDims__Command > 0
		BEGIN
			SET @lv__BigNvar = @lv__BigNvar + N' 
			ON dco.command = sar.rqst__command
			';
		END

		SET @lv__BigNvar = @lv__BigNvar + N'
		WHERE sar.calc__return_to_user > 0
		AND sar.sess__session_id > 0
		AND (sar.sess__FKDimLoginName IS NULL
			OR sar.sess__FKDimSessionAttribute IS NULL
			OR sar.conn__FKDimNetAddress IS NULL
			OR sar.conn__FKDimConnectionAttribute IS NULL
			OR sar.rqst__FKDimCommand IS NULL
			OR sar.rqst__FKDimWaitType IS NULL)
		OPTION(FORCE ORDER, MAXDOP 1, KEEPFIXED PLAN);
		';

		--print @lv__BigNvar;
		SET @errorloc = N'DimUpdate SQLExec';
		EXEC sp_executesql @lv__BigNvar;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'DimReapply:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	--We (potentially) just re-applied dimension values to the sar table; i.e. if any records in sar have NULL values
	-- for their Dimension FKs, then we have a bug in our logic. If requested, we save these records off into a "quarantine sink table"
	-- so that we can analyze them later.
	IF @SaveBadDims = N'Y'
	BEGIN
		SET @errorloc = N'BadDim INSERT';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_SARException(
			SPIDCaptureTime, UTCCaptureTime, sess__session_id, rqst__request_id, TimeIdentifier, sess__login_time, sess__host_name, 
			sess__program_name, sess__host_process_id, sess__client_version, sess__client_interface_name, sess__login_name, 
			sess__status_code, sess__cpu_time, sess__memory_usage, sess__total_scheduled_time, sess__total_elapsed_time, 
			sess__endpoint_id, sess__last_request_start_time, sess__last_request_end_time, sess__reads, sess__writes, 
			sess__logical_reads, sess__is_user_process, sess__transaction_isolation_level, sess__lock_timeout, 
			sess__deadlock_priority, sess__row_count, sess__original_login_name, sess__open_transaction_count, 
			sess__group_id, sess__database_id, sess__FKDimLoginName, sess__FKDimSessionAttribute, conn__connect_time, 
			conn__net_transport, conn__protocol_type, conn__protocol_version, conn__endpoint_id, conn__encrypt_option, 
			conn__auth_scheme, conn__node_affinity, conn__net_packet_size, conn__client_net_address, conn__client_tcp_port, 
			conn__local_net_address, conn__local_tcp_port, conn__FKDimNetAddress, conn__FKDimConnectionAttribute, 
			rqst__start_time, rqst__status_code, rqst__command, rqst__sql_handle, rqst__statement_start_offset, 
			rqst__statement_end_offset, rqst__plan_handle, rqst__blocking_session_id, rqst__wait_type, rqst__wait_latch_subtype, 
			rqst__wait_time, rqst__wait_resource, rqst__open_transaction_count, rqst__open_resultset_count, rqst__percent_complete, 
			rqst__cpu_time, rqst__total_elapsed_time, rqst__scheduler_id, rqst__reads, rqst__writes, rqst__logical_reads, 
			rqst__transaction_isolation_level, rqst__lock_timeout, rqst__deadlock_priority, rqst__row_count, rqst__granted_query_memory, 
			rqst__executing_managed_code, rqst__group_id, rqst__query_hash, rqst__query_plan_hash, rqst__FKDimCommand, rqst__FKDimWaitType, 
			tempdb__sess_user_objects_alloc_page_count, tempdb__sess_user_objects_dealloc_page_count, tempdb__sess_internal_objects_alloc_page_count, 
			tempdb__sess_internal_objects_dealloc_page_count, tempdb__task_user_objects_alloc_page_count, 
			tempdb__task_user_objects_dealloc_page_count, tempdb__task_internal_objects_alloc_page_count, 
			tempdb__task_internal_objects_dealloc_page_count, tempdb__CalculatedNumberOfTasks, 
			tempdb__CalculatedCurrentTempDBUsage_pages, mgrant__request_time, mgrant__grant_time, mgrant__requested_memory_kb, 
			mgrant__required_memory_kb, mgrant__granted_memory_kb, mgrant__used_memory_kb, mgrant__max_used_memory_kb, mgrant__dop, 
			calc__record_priority, calc__is_compiling, calc__duration_ms, calc__blocking_session_id, calc__block_relevant, 
			calc__return_to_user, calc__is_blocker, calc__sysspid_isinteresting, calc__tmr_wait, calc__threshold_ignore, RecordReason
		)
		SELECT @lv__SPIDCaptureTime, @lv__UTCCaptureTime, sess__session_id, rqst__request_id, TimeIdentifier, sess__login_time, sess__host_name, 
			sess__program_name, sess__host_process_id, sess__client_version, sess__client_interface_name, sess__login_name, 
			sess__status_code, sess__cpu_time, sess__memory_usage, sess__total_scheduled_time, sess__total_elapsed_time, 
			sess__endpoint_id, sess__last_request_start_time, sess__last_request_end_time, sess__reads, sess__writes, 
			sess__logical_reads, sess__is_user_process, sess__transaction_isolation_level, sess__lock_timeout, 
			sess__deadlock_priority, sess__row_count, sess__original_login_name, sess__open_transaction_count, 
			sess__group_id, sess__database_id, sess__FKDimLoginName, sess__FKDimSessionAttribute, conn__connect_time, 
			conn__net_transport, conn__protocol_type, conn__protocol_version, conn__endpoint_id, conn__encrypt_option, 
			conn__auth_scheme, conn__node_affinity, conn__net_packet_size, conn__client_net_address, conn__client_tcp_port, 
			conn__local_net_address, conn__local_tcp_port, conn__FKDimNetAddress, conn__FKDimConnectionAttribute, 
			rqst__start_time, rqst__status_code, rqst__command, rqst__sql_handle, rqst__statement_start_offset, 
			rqst__statement_end_offset, rqst__plan_handle, rqst__blocking_session_id, rqst__wait_type, rqst__wait_latch_subtype, 
			rqst__wait_time, rqst__wait_resource, rqst__open_transaction_count, rqst__open_resultset_count, rqst__percent_complete, 
			rqst__cpu_time, rqst__total_elapsed_time, rqst__scheduler_id, rqst__reads, rqst__writes, rqst__logical_reads, 
			rqst__transaction_isolation_level, rqst__lock_timeout, rqst__deadlock_priority, rqst__row_count, rqst__granted_query_memory, 
			rqst__executing_managed_code, rqst__group_id, rqst__query_hash, rqst__query_plan_hash, rqst__FKDimCommand, rqst__FKDimWaitType, 
			tempdb__sess_user_objects_alloc_page_count, tempdb__sess_user_objects_dealloc_page_count, tempdb__sess_internal_objects_alloc_page_count, 
			tempdb__sess_internal_objects_dealloc_page_count, tempdb__task_user_objects_alloc_page_count, 
			tempdb__task_user_objects_dealloc_page_count, tempdb__task_internal_objects_alloc_page_count, 
			tempdb__task_internal_objects_dealloc_page_count, tempdb__CalculatedNumberOfTasks, 
			tempdb__CalculatedCurrentTempDBUsage_pages, mgrant__request_time, mgrant__grant_time, mgrant__requested_memory_kb, 
			mgrant__required_memory_kb, mgrant__granted_memory_kb, mgrant__used_memory_kb, mgrant__max_used_memory_kb, mgrant__dop, 
			calc__record_priority, calc__is_compiling, calc__duration_ms, calc__blocking_session_id, calc__block_relevant, 
			calc__return_to_user, calc__is_blocker, calc__sysspid_isinteresting, calc__tmr_wait, calc__threshold_ignore, 1 
		FROM #sessions_and_requests sar
		WHERE sar.sess__session_id > 0
		AND sar.calc__return_to_user > 0
		AND (sar.conn__FKDimConnectionAttribute IS NULL
			OR sar.conn__FKDimNetAddress IS NULL
			OR sar.rqst__FKDimCommand IS NULL
			OR sar.rqst__FKDimWaitType IS NULL
			OR sar.sess__FKDimLoginName IS NULL
			OR sar.sess__FKDimSessionAttribute IS NULL
		);

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'BadDims:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END


	--Now, update our "store" tables, if we have any updates to make
	IF @lv__StatementsPulled = CONVERT(BIT,1)
	BEGIN
		--if we pulled statement text, we pulled it for 1 of 2 reasons:
		-- 1. the sql_handle/offsets unique combo didn't exist at all in the store
		-- 2. the combo exists, but with fail_to_obtain = 1 and thus our pull was essentially a "retry"
		-- the MERGE logic below will cover our needs for both cases

		SET @errorloc = N'StmtStore MERGE';
		MERGE @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore perm
			USING #t__stmt t
				ON perm.sql_handle = t.sql_handle
				AND perm.statement_start_offset = t.statement_start_offset
				AND perm.statement_end_offset = t.statement_end_offset
		WHEN MATCHED THEN UPDATE 
			-- fail_to_obtain must have been 1. Update all of the attributes.
			SET perm.dbid = t.dbid, 
				perm.objectid = t.objectid,
				perm.fail_to_obtain = t.fail_to_obtain,
				perm.datalen_batch = t.datalen_batch,
				perm.stmt_text = t.stmt_text,
				perm.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		WHEN NOT MATCHED BY TARGET THEN 
			--new entry
			INSERT (sql_handle, statement_start_offset, statement_end_offset, 
				dbid, objectid, fail_to_obtain, datalen_batch, stmt_text, 
				InsertedBy_UTCCaptureTime, LastTouchedBy_UTCCaptureTime)
			VALUES (t.sql_handle, t.statement_start_offset, t.statement_end_offset,
				t.dbid, t.objectid, t.fail_to_obtain, t.datalen_batch, t.stmt_text, 
				@lv__UTCCaptureTime, @lv__UTCCaptureTime)
		;

		SET @errorloc = N'StmtStore UPDATE';
		UPDATE sar 
		SET sar.calc__FKSQLStmtStoreID = sss.PKSQLStmtStoreID
		FROM #sessions_and_requests sar
			INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore sss
				ON sss.sql_handle = sar.rqst__sql_handle
				AND sss.statement_start_offset = sar.rqst__statement_start_offset
				AND sss.statement_end_offset = sar.rqst__statement_end_offset
		WHERE sar.calc__FKSQLStmtStoreID IS NULL
			--this lets us IxSeek quickly to the rows in SQLStmtStore that we just pulled
		AND sss.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		OPTION(FORCE ORDER, MAXDOP 1);
	END		--IF @lv__StatementsPulled = CONVERT(BIT,1)


	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'StmtStore:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END

	--Update the batch store if we pulled any SQL batches
	IF @ObtainBatchText = N'Y' AND @lv__BatchesPulled = CONVERT(BIT,1)
	BEGIN
		SET @errorloc = N'BatchStore MERGE';
		MERGE @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore perm
			USING #t__batch t
				ON perm.sql_handle = t.sql_handle
		WHEN MATCHED THEN UPDATE
			SET perm.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime,
				perm.dbid = t.dbid,
				perm.objectid = t.objectid,
				perm.fail_to_obtain = t.fail_to_obtain,
				perm.batch_text = t.batch_text
		WHEN NOT MATCHED BY TARGET THEN
			INSERT (sql_handle, dbid, objectid, fail_to_obtain, batch_text, 
				InsertedBy_UTCCaptureTime, LastTouchedBy_UTCCaptureTime)
			VALUES (t.sql_handle, t.dbid, t.objectid, t.fail_to_obtain, t.batch_text, 
				@lv__UTCCaptureTime, @lv__UTCCaptureTime)
		;

		SET @errorloc = N'BatchStore UPDATE';
		UPDATE sar
		SET sar.calc__FKSQLBatchStoreID = bs.PKSQLBatchStoreID
		FROM #sessions_and_requests sar
			INNER hash JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore bs
				ON bs.sql_handle = sar.rqst__sql_handle
		WHERE bs.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		AND sar.calc__FKSQLBatchStoreID IS NULL
		OPTION(FORCE ORDER, MAXDOP 1);

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'BatchStore:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	--Update the InputBuffer Store if we pulled any IBs
	IF @lv__numIBsCollected > 0
	BEGIN
		--logic from before LastTouched column was added and logic converted to MERGE
		--INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore
		--(AWBufferHash, InputBuffer, InsertedBy_UTCCaptureTime)
		--SELECT t.aw_buffer_hash, t.InputBuffer, @lv__SPIDCaptureTime
		--FROM #t__ib t
		--WHERE NOT EXISTS (
		--	SELECT *
		--	FROM @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore ib2
		--	WHERE ib2.AWBufferHash = t.aw_buffer_hash
		--	AND ib2.InputBuffer = t.InputBuffer
		--);

		SET @errorloc = N'IB MERGE';
		MERGE @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore perm
			--We need to use a distinct here because multiple spids could have identical input buffers, which would then hash
			-- to the same value. 
			USING (SELECT DISTINCT aw_buffer_hash, InputBuffer
					FROM #t__ib t
					--Got a strange (and seemingly impossible) exception once about a NULL aw_buffer_hash value:
					WHERE aw_buffer_hash IS NOT NULL
					) t
				ON perm.AWBufferHash = t.aw_buffer_hash
				AND perm.InputBuffer = t.InputBuffer
		WHEN MATCHED THEN UPDATE
			SET perm.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		WHEN NOT MATCHED BY TARGET THEN 
			INSERT (AWBufferHash, InputBuffer, InsertedBy_UTCCaptureTime, LastTouchedBy_UTCCaptureTime)
			VALUES (t.aw_buffer_hash, t.InputBuffer, @lv__UTCCaptureTime, @lv__UTCCaptureTime)
		;

		SET @errorloc = N'IB UPDATE';
		UPDATE t 
		SET t.PKInputBufferStoreID = s.PKInputBufferStoreID
		FROM #t__ib t
			INNER JOIN @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore s
				ON t.aw_buffer_hash = s.AWBufferHash
				AND t.InputBuffer = s.InputBuffer
		WHERE s.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'IBStore:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	--Update the plan stores
	IF @ObtainQueryPlanForBatch = N'Y' AND @thresh__QueryPlansNeeded > 0
	BEGIN
		--logic before the LastTouched column was added and the logic converted to MERGE
		--INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore
		--(AWBatchPlanHash, plan_handle, dbid, objectid, fail_to_obtain, query_plan, InsertedBy_UTCCaptureTime)
		--SELECT 
		--	t.aw_batchplan_hash, t.plan_handle, t.dbid, t.objectid, t.fail_to_obtain, t.query_plan, @lv__SPIDCaptureTime
		--FROM #t__batchqp t
		--WHERE NOT EXISTS (
		--	SELECT *
		--	FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore bs2
		--	WHERE bs2.AWBatchPlanHash = t.aw_batchplan_hash
		--	AND bs2.plan_handle = t.plan_handle
		--	AND bs2.dbid = t.dbid
		--	AND bs2.objectid = t.objectid
		--);
		
		SET @errorloc = N'PlanBatch MERGE';
		MERGE @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore perm
			USING #t__batchqp t
				ON perm.AWBatchPlanHash = t.aw_batchplan_hash
				AND perm.plan_handle = t.plan_handle
		WHEN MATCHED THEN UPDATE
			SET perm.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime,
				perm.dbid = t.dbid,
				perm.objectid = t.objectid
		WHEN NOT MATCHED BY TARGET THEN
			INSERT (AWBatchPlanHash, plan_handle, dbid, objectid, fail_to_obtain, query_plan, 
				InsertedBy_UTCCaptureTime, LastTouchedBy_UTCCaptureTime)
			VALUES (t.aw_batchplan_hash, t.plan_handle, t.dbid, t.objectid, t.fail_to_obtain, t.query_plan, 
				@lv__UTCCaptureTime, @lv__UTCCaptureTime)
		;

		SET @errorloc = N'PlanBatch UPDATE';
		UPDATE t
		SET t.PKQueryPlanBatchStoreID = bs.PKQueryPlanBatchStoreID
		FROM #t__batchqp t
			INNER JOIN @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore bs
				ON bs.AWBatchPlanHash = t.aw_batchplan_hash
				AND bs.plan_handle = t.plan_handle
		WHERE bs.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'PlanBatchStore:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	IF @ObtainQueryPlanForStatement = N'Y' AND @thresh__QueryPlansNeeded > 0
	BEGIN
		--logic before we added the LastTouched column and converted the logic to MERGE
		--INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore 
		--(AWStmtPlanHash, plan_handle, statement_start_offset, statement_end_offset, 
		--	dbid, objectid, fail_to_obtain, query_plan, InsertedBy_UTCCaptureTime)
		--SELECT t.aw_stmtplan_hash, t.plan_handle, t.statement_start_offset, t.statement_end_offset,
		--	t.dbid, t.objectid, t.fail_to_obtain, t.query_plan, @lv__SPIDCaptureTime
		--FROM #t__stmtqp t
		--WHERE NOT EXISTS (
		--	SELECT * 
		--	FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore qps
		--	WHERE qps.AWStmtPlanHash = t.aw_stmtplan_hash
		--	AND qps.plan_handle = t.plan_handle
		--	AND qps.statement_start_offset = t.statement_start_offset
		--	AND qps.statement_end_offset = t.statement_end_offset
		--	AND qps.dbid = t.dbid
		--	AND qps.objectid = t.objectid
		--);
		
		SET @errorloc = N'PlanStmt MERGE';
		MERGE @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore perm
			USING #t__stmtqp t
				ON perm.AWStmtPlanHash = t.aw_stmtplan_hash
				AND perm.plan_handle = t.plan_handle
				AND perm.statement_start_offset = t.statement_start_offset
				AND perm.statement_end_offset = t.statement_end_offset
		WHEN MATCHED THEN UPDATE
			--We overwrite dbid/objectid b/c I don't have 100% certainty that a plan_handle/offset combo, with
			-- the plan hash, will ALWAYS have the same dbid/objectid (though it seems mathematically almost 
			-- impossible to have a collision here).
			SET perm.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime,
				perm.dbid = t.dbid,
				perm.objectid = t.objectid
		WHEN NOT MATCHED THEN
			INSERT (AWStmtPlanHash, plan_handle, statement_start_offset, statement_end_offset, 
				dbid, objectid, fail_to_obtain, query_plan, 
				InsertedBy_UTCCaptureTime, LastTouchedBy_UTCCaptureTime)
			VALUES (t.aw_stmtplan_hash, t.plan_handle, t.statement_start_offset, t.statement_end_offset,
				t.dbid, t.objectid, t.fail_to_obtain, t.query_plan, 
				@lv__UTCCaptureTime, @lv__UTCCaptureTime)
		;

		SET @errorloc = N'PlanStmt UPDATE';
		/* Aaron 2016-05-04: TODO: it might be more efficient to update the #sar table directly
			instead of the #t__stmtqp table, though it would require adding an 8 byte BIGINT column
			to #sar, and many SPIDs don't need their query plans obtained. (So would often be NULL).
			In the Intervals collection proc, I have an UPDATE statement that updates the 
			#TopObjects_StmtStats table directly, and would be a model for making the change here.
			(If I do this, remember to remove the clause in the dynamic SQL below for the join!)
		*/
		UPDATE t
		SET t.PKQueryPlanStmtStoreID = qps.PKQueryPlanStmtStoreID
		FROM #t__stmtqp t
			INNER JOIN @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore qps
				ON qps.AWStmtPlanHash = t.aw_stmtplan_hash
				AND qps.plan_handle = t.plan_handle
				AND qps.statement_start_offset = t.statement_start_offset
				AND qps.statement_end_offset = t.statement_end_offset
		WHERE qps.LastTouchedBy_UTCCaptureTime = @lv__UTCCaptureTime
		;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'PlanStmtStore:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	--UTCCaptureTime is at the bottom of the col list b/c I didn't want to renumber everything
	SET @errorloc = N'SAR permanence DynSQL';
	SET @lv__BigNvar = N'
	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests 
	(	CollectionInitiatorID,			--1
		UTCCaptureTime,
		SPIDCaptureTime,
		session_id, 
		request_id, 
		TimeIdentifier,
		sess__login_time,
		sess__host_process_id, 
		sess__status_code, 
		sess__cpu_time,					--10
		sess__memory_usage,
		sess__total_scheduled_time,
		sess__total_elapsed_time, 
		sess__last_request_start_time, 
		sess__last_request_end_time,
		sess__reads,
		sess__writes,
		sess__logical_reads,
		sess__is_user_process, 
		sess__lock_timeout,				--20
		sess__row_count,
		sess__open_transaction_count,
		sess__database_id,
		sess__FKDimLoginName, 
		sess__FKDimSessionAttribute, 
		conn__connect_time,
		conn__client_tcp_port,
		conn__FKDimNetAddress,
		conn__FKDimConnectionAttribute,
		rqst__start_time,				--30
		rqst__status_code,
		rqst__blocking_session_id,
		rqst__wait_time,
		rqst__wait_resource,
		rqst__open_transaction_count, 
		rqst__open_resultset_count,
		rqst__percent_complete,	
		rqst__cpu_time,
		rqst__total_elapsed_time,
		rqst__scheduler_id,				--40
		rqst__reads,
		rqst__writes,
		rqst__logical_reads,
		rqst__transaction_isolation_level,
		rqst__lock_timeout,
		rqst__deadlock_priority,
		rqst__row_count,
		rqst__granted_query_memory,
		rqst__executing_managed_code,
		rqst__group_id,					--50
		rqst__query_hash,
		rqst__query_plan_hash,
		rqst__FKDimCommand,
		rqst__FKDimWaitType,
		tempdb__sess_user_objects_alloc_page_count,
		tempdb__sess_user_objects_dealloc_page_count,
		tempdb__sess_internal_objects_alloc_page_count,
		tempdb__sess_internal_objects_dealloc_page_count,
		tempdb__task_user_objects_alloc_page_count,
		tempdb__task_user_objects_dealloc_page_count,		--60
		tempdb__task_internal_objects_alloc_page_count,
		tempdb__task_internal_objects_dealloc_page_count,
		tempdb__CalculatedNumberOfTasks,
		mgrant__request_time,
		mgrant__grant_time,	
		mgrant__requested_memory_kb,
		mgrant__required_memory_kb,
		mgrant__granted_memory_kb,
		mgrant__used_memory_kb,
		mgrant__max_used_memory_kb,					--70
		mgrant__dop,
		calc__record_priority, 
		calc__is_compiling,
		calc__duration_ms,
		calc__blocking_session_id,
		calc__block_relevant,
		calc__return_to_user, 
		calc__is_blocker,
		calc__sysspid_isinteresting,
		calc__tmr_wait,								--80
		calc__threshold_ignore,
		calc__node_info,
		calc__status_info,
		FKSQLStmtStoreID,
		FKSQLBatchStoreID,
		FKInputBufferStoreID,
		FKQueryPlanBatchStoreID,
		FKQueryPlanStmtStoreID						--88
	)
	';

	SET @lv__BigNvar = @lv__BigNvar + N'
	SELECT 
		@CollectionInitiatorID,				--1
		@lv__UTCCaptureTime,
		@lv__SPIDCaptureTime,
		sar.sess__session_id,
		request_id = sar.rqst__request_id,
		sar.TimeIdentifier,
		sar.sess__login_time,
		sar.sess__host_process_id,
		sar.sess__status_code,
		sar.sess__cpu_time,					--10
		sar.sess__memory_usage,
		sar.sess__total_scheduled_time,
		sar.sess__total_elapsed_time,
		sar.sess__last_request_start_time,
		sar.sess__last_request_end_time,
		sar.sess__reads,
		sar.sess__writes,
		sar.sess__logical_reads,
		sar.sess__is_user_process,
		sar.sess__lock_timeout,				--20
		sar.sess__row_count,
		sar.sess__open_transaction_count,
		sar.sess__database_id,
		sar.sess__FKDimLoginName,
		sar.sess__FKDimSessionAttribute,
		sar.conn__connect_time,
		sar.conn__client_tcp_port,
		sar.conn__FKDimNetAddress,
		sar.conn__FKDimConnectionAttribute,
		sar.rqst__start_time,				--30
		sar.rqst__status_code,
		sar.rqst__blocking_session_id,
		sar.rqst__wait_time,
		sar.rqst__wait_resource,
		sar.rqst__open_transaction_count,
		sar.rqst__open_resultset_count,
		sar.rqst__percent_complete,
		sar.rqst__cpu_time,	
		sar.rqst__total_elapsed_time,
		sar.rqst__scheduler_id,				--40
		sar.rqst__reads,
		sar.rqst__writes,
		sar.rqst__logical_reads,
		sar.rqst__transaction_isolation_level,
		sar.rqst__lock_timeout,
		sar.rqst__deadlock_priority,
		sar.rqst__row_count,
		sar.rqst__granted_query_memory,
		sar.rqst__executing_managed_code,
		sar.rqst__group_id,					--50
		sar.rqst__query_hash,
		sar.rqst__query_plan_hash,
		sar.rqst__FKDimCommand,
		sar.rqst__FKDimWaitType,
		sar.tempdb__sess_user_objects_alloc_page_count,
		sar.tempdb__sess_user_objects_dealloc_page_count,
		sar.tempdb__sess_internal_objects_alloc_page_count,
		sar.tempdb__sess_internal_objects_dealloc_page_count,
		sar.tempdb__task_user_objects_alloc_page_count,
		sar.tempdb__task_user_objects_dealloc_page_count,		--60
		sar.tempdb__task_internal_objects_alloc_page_count,
		sar.tempdb__task_internal_objects_dealloc_page_count,
		sar.tempdb__CalculatedNumberOfTasks,
		sar.mgrant__request_time,
		sar.mgrant__grant_time,
		sar.mgrant__requested_memory_kb,
		sar.mgrant__required_memory_kb, 
		sar.mgrant__granted_memory_kb,
		sar.mgrant__used_memory_kb,
		sar.mgrant__max_used_memory_kb,					--70
		sar.mgrant__dop,
		sar.calc__record_priority, 
		sar.calc__is_compiling,
		sar.calc__duration_ms,
		sar.calc__blocking_session_id,
		sar.calc__block_relevant,
		sar.calc__return_to_user,
		sar.calc__is_blocker,
		sar.calc__sysspid_isinteresting,
		sar.calc__tmr_wait,								--80
		sar.calc__threshold_ignore,
		calc__node_info = N''<placeholder>'',
		calc__status_info = N''<placeholder>'',
		sar.calc__FKSQLStmtStoreID,
		sar.calc__FKSQLBatchStoreID,
		' + 
		--the N'<placeholder>' above is to avoid page splits when we update this data from the master (every 15 min) proc

		CASE WHEN @lv__numIBsCollected > 0 THEN N'
		ib.PKInputBufferStoreID,' ELSE N'
		NULL,' END + 

		CASE WHEN @ObtainQueryPlanForBatch = N'Y' THEN N'
		batchqp.PKQueryPlanBatchStoreID,' ELSE N'
		NULL,' END + 
		
		CASE WHEN @ObtainQueryPlanForStatement = N'Y' THEN N'
		stmtqp.PKQueryPlanStmtStoreID' ELSE N'
		NULL' END;

	SET @lv__BigNvar = @lv__BigNvar + N'
	FROM #sessions_and_requests sar 
	' +
		--Aaron: the SQL stmt and batch text joins used to be here, but
		-- we eliminated the need for them in our changes above. (Removing the hashing of sql text
		-- and grabbing the store PK values directly from the store)

		CASE WHEN @lv__numIBsCollected > 0 THEN N'
		LEFT OUTER JOIN #t__ib ib
			ON sar.sess__session_id = ib.session_id
		' ELSE N'' END + 

		CASE WHEN @ObtainQueryPlanForBatch = N'Y' THEN N'
		LEFT OUTER JOIN #t__batchqp batchqp
			ON sar.rqst__plan_handle = batchqp.plan_handle
		' ELSE N'' END +

		CASE WHEN @ObtainQueryPlanForStatement = N'Y' THEN N'
		LEFT OUTER JOIN #t__stmtqp stmtqp
			ON sar.rqst__plan_handle = stmtqp.plan_handle
			AND sar.rqst__statement_start_offset = stmtqp.statement_start_offset
			AND sar.rqst__statement_end_offset = stmtqp.statement_end_offset
		' ELSE N'' END + 
		
		N'
	WHERE sar.calc__return_to_user > 0;
		';

	SET @errorloc = N'SAR permanence SQLExec';
	EXEC sp_executesql @lv__BigNvar, N'@CollectionInitiatorID TINYINT, @lv__UTCCaptureTime DATETIME, @lv__SPIDCaptureTime DATETIME, @lv__nullsmallint SMALLINT', 
		@CollectionInitiatorID, @lv__UTCCaptureTime, @lv__SPIDCaptureTime, @lv__nullsmallint;

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'SARPerm:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END


	SET @errorloc = N'TAW permanence';
	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits (
		CollectionInitiatorID,
		UTCCaptureTime,
		SPIDCaptureTime, 
		task_address, 
		parent_task_address, 
		session_id, 
		request_id, 
		exec_context_id, 
		tstate,
		scheduler_id, 
		context_switches_count, 
		FKDimWaitType, 
		wait_duration_ms, 
		wait_special_category, 
		wait_order_category, 
		wait_special_number, 
		wait_special_tag, 
		task_priority, 
		blocking_task_address, 
		blocking_session_id, 
		blocking_exec_context_id, 
		resource_description, 
		resource_dbid, 
		resource_associatedobjid, 
		cxp_wait_direction,
		resolution_successful
	)
	SELECT 
		@CollectionInitiatorID,
		[UTCCaptureTime] = @lv__UTCCaptureTime,
		[SPIDCaptureTime] = @lv__SPIDCaptureTime,
		task_address,
		parent_task_address,
		session_id,
		request_id,
		exec_context_id,
		tstate,
		scheduler_id,
		context_switches_count,
		dwt.DimWaitTypeID,
		wait_duration_ms,
		wait_special_category,
		wait_order_category,
		wait_special_number,
		wait_special_tag,
		task_priority,
		blocking_task_address,
		blocking_session_id,
		blocking_exec_context_id,
		resource_description,
		resource_dbid,
		resource_associatedobjid,
		cxpwaitdirection,
		CONVERT(BIT,0)				--as of 5/9/2016, resolution always happens via a separate procedure
	FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
		RIGHT OUTER hash JOIN (
			SELECT 
				taw.task_address,
				taw.parent_task_address,
				taw.session_id,
				taw.request_id,
				taw.exec_context_id,
				taw.tstate,
				taw.scheduler_id,
				taw.context_switches_count,
				taw.wait_type,
				taw.wait_latch_subtype,
				taw.wait_duration_ms,
				taw.wait_special_category,
				taw.wait_order_category,
				wait_special_number = ISNULL(taw.wait_special_number,@lv__nullint),
				taw.wait_special_tag,
				taw.task_priority,
				taw.blocking_task_address,
				blocking_session_id = ISNULL(taw.blocking_session_id, @lv__nullsmallint),
				blocking_exec_context_id = ISNULL(taw.blocking_exec_context_id,@lv__nullsmallint),
				taw.resource_description,
				taw.resource_dbid,
				taw.resource_associatedobjid,
				[cxpwaitdirection] = CASE WHEN wait_special_category = @enum__waitspecial__cxp THEN 
							(CASE WHEN resource_description LIKE N'%newrow%' THEN CONVERT(TINYINT,2)
								ELSE CONVERT(TINYINT,1)
							END)
							ELSE CONVERT(TINYINT,0) END
			FROM #tasks_and_waits taw 
				LEFT OUTER JOIN #sessions_and_requests sar
					ON taw.session_id = sar.sess__session_id
					AND taw.request_id = sar.rqst__request_id
					AND sar.calc__return_to_user > 0
			WHERE (taw.session_id = -998					--For "tasks without spids"
				AND ISNULL(taw.wait_type,@lv__nullstring) <> @lv__nullstring		--we only want them if they are waiting, not running
				AND ISNULL(taw.wait_type,'') NOT IN (
					--avoid some wait types that are very common for the "tasks without spids", but are not interesting to us
					'CLR_AUTO_EVENT',
					'DISPATCHER_QUEUE_SEMAPHORE',
					'FT_IFTS_SCHEDULER_IDLE_WAIT'
					)
				)
			OR (
				sar.sess__session_id IS NOT NULL		--spid is active
				AND (
					taw.task_priority = 1		--we always save the "top task" for active spids
					OR sar.calc__duration_ms >= @ParallelWaitsThreshold		--for active spids with multiple tasks, we only
																			--save "non-top tasks" (task_priority > 1) if the
					)														-- duration of the active spid's batch is >= a threshold
				)
		) basedata
		ON basedata.wait_type = dwt.wait_type
		AND basedata.wait_latch_subtype = dwt.latch_subtype
	OPTION(MAXDOP 1, FORCE ORDER, KEEPFIXED PLAN)
	;

	IF @DebugSpeed = N'Y'
	BEGIN
		SET @lv__stmtdurations = @lv__stmtdurations +  N'TAWperm:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
		SET @lv__beforedt = GETUTCDATE();
	END


	IF @lv__BChainRecsExist = 1
	BEGIN
		SET @errorloc = N'BChain permanence';
		INSERT INTO AutoWho.BlockingGraphs (
			CollectionInitiatorID,
			UTCCaptureTime,
			SPIDCaptureTime, 
			session_id, 
			request_id, 
			exec_context_id, 
			calc__blocking_session_Id, 
			wait_type, 
			wait_duration_ms, 
			resource_description, 
			FKInputBufferStoreID, 
			FKSQLStmtStoreID,
			sort_value, 
			block_group, 
			levelindc, 
			rn)
		SELECT 
			@CollectionInitiatorID,
			@lv__UTCCaptureTime,
			@lv__SPIDCaptureTime, 
			b.session_id, 
			b.request_id, 
			b.exec_context_id,
			b.calc__blocking_session_id, 
			b.wait_type, 
			b.wait_duration_ms,
			b.resource_description, 
			ib.PKInputBufferStoreID, 
			sar.calc__FKSQLStmtStoreID,
			b.sort_value, 
			b.block_group, 
			b.levelindc, 
			b.rn
		FROM #BChain b
			LEFT OUTER JOIN #t__ib ib
				ON b.session_id = ib.session_id
			LEFT OUTER JOIN #sessions_and_requests sar
				ON b.session_id = sar.sess__session_id
				AND b.request_id = sar.rqst__request_id
		;

		IF @DebugSpeed = N'Y'
		BEGIN
			SET @lv__stmtdurations = @lv__stmtdurations +  N'BChainPerm:'+CONVERT(NVARCHAR(20),DATEDIFF(MILLISECOND, @lv__beforedt, GETUTCDATE())) + N',';
			SET @lv__beforedt = GETUTCDATE();
		END
	END

	--And then I am done!
	SET @errorloc = N'CaptureTime INSERT';
	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes (
		[CollectionInitiatorID],
		[SPIDCaptureTime],
		[UTCCaptureTime],
		[RunWasSuccessful],
		[SpidsCaptured],
		[PostProcessed_StmtStats],
		[PostProcessed_Latch],
		[PostProcessed_Lock],
		[PostProcessed_NodeStatus],
		[ExtractedForDW],
		[CaptureSummaryPopulated],
		[CaptureSummaryDeltaPopulated],
		[AutoWhoDuration_ms],
		[DurationBreakdown]
	)
	SELECT 
		[CollectionInitiatorID] = @CollectionInitiatorID,
		[SPIDCaptureTime] = @lv__SPIDCaptureTime, 
		[UTCCaptureTime] = @lv__UTCCaptureTime,
		[RunWasSuccessful] = 1, 
		[SpidsCaptured] = @NumSPIDs, 
		[PostProcessed_StmtStats] = 0,
		[PostProcessed_Latch] = 0,
		[PostProcessed_Lock] = 0,
		[PostProcessed_NodeStatus] = 0,
		[ExtractedForDW] = 0,
		[CaptureSummaryPopulated] = 0,
		[CaptureSummaryDeltaPopulated] = 0,
		[AutoWhoDuration_ms] = DATEDIFF(MILLISECOND, @lv__procstartdt, GETUTCDATE()), 
		[DurationBreakdown] = @lv__stmtdurations;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @err__ErrorSeverity = ERROR_SEVERITY();
	SET @err__ErrorState = ERROR_STATE();
	SET @err__ErrorText = N'Unexpected exception occurred at location "' + ISNULL(@errorloc,N'<null>') + '". Error #: ' + 
		CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
		CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

	--Write the SAR table to its exception cousin so we have some data to debug the exception
	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_SARException(
		SPIDCaptureTime, UTCCaptureTime, sess__session_id, rqst__request_id, TimeIdentifier, sess__login_time, sess__host_name, 
		sess__program_name, sess__host_process_id, sess__client_version, sess__client_interface_name, sess__login_name, 
		sess__status_code, sess__cpu_time, sess__memory_usage, sess__total_scheduled_time, sess__total_elapsed_time, 
		sess__endpoint_id, sess__last_request_start_time, sess__last_request_end_time, sess__reads, sess__writes, 
		sess__logical_reads, sess__is_user_process, sess__transaction_isolation_level, sess__lock_timeout, 
		sess__deadlock_priority, sess__row_count, sess__original_login_name, sess__open_transaction_count, 
		sess__group_id, sess__database_id, sess__FKDimLoginName, sess__FKDimSessionAttribute, conn__connect_time, 
		conn__net_transport, conn__protocol_type, conn__protocol_version, conn__endpoint_id, conn__encrypt_option, 
		conn__auth_scheme, conn__node_affinity, conn__net_packet_size, conn__client_net_address, conn__client_tcp_port, 
		conn__local_net_address, conn__local_tcp_port, conn__FKDimNetAddress, conn__FKDimConnectionAttribute, 
		rqst__start_time, rqst__status_code, rqst__command, rqst__sql_handle, rqst__statement_start_offset, 
		rqst__statement_end_offset, rqst__plan_handle, rqst__blocking_session_id, rqst__wait_type, rqst__wait_latch_subtype, 
		rqst__wait_time, rqst__wait_resource, rqst__open_transaction_count, rqst__open_resultset_count, rqst__percent_complete, 
		rqst__cpu_time, rqst__total_elapsed_time, rqst__scheduler_id, rqst__reads, rqst__writes, rqst__logical_reads, 
		rqst__transaction_isolation_level, rqst__lock_timeout, rqst__deadlock_priority, rqst__row_count, rqst__granted_query_memory, 
		rqst__executing_managed_code, rqst__group_id, rqst__query_hash, rqst__query_plan_hash,
		rqst__FKDimCommand, rqst__FKDimWaitType, tempdb__sess_user_objects_alloc_page_count, 
		tempdb__sess_user_objects_dealloc_page_count, tempdb__sess_internal_objects_alloc_page_count, 
		tempdb__sess_internal_objects_dealloc_page_count, tempdb__task_user_objects_alloc_page_count, 
		tempdb__task_user_objects_dealloc_page_count, tempdb__task_internal_objects_alloc_page_count, 
		tempdb__task_internal_objects_dealloc_page_count, tempdb__CalculatedNumberOfTasks, 
		tempdb__CalculatedCurrentTempDBUsage_pages, mgrant__request_time, mgrant__grant_time, mgrant__requested_memory_kb, 
		mgrant__required_memory_kb, mgrant__granted_memory_kb, mgrant__used_memory_kb, mgrant__max_used_memory_kb, mgrant__dop, 
		calc__record_priority, calc__is_compiling, calc__duration_ms, calc__blocking_session_id, calc__block_relevant, 
		calc__return_to_user, calc__is_blocker, calc__sysspid_isinteresting, calc__tmr_wait, calc__threshold_ignore, 
		calc__FKSQLStmtStoreID, calc__FKSQLBatchStoreID, RecordReason
	)
	SELECT @lv__SPIDCaptureTime, @lv__UTCCaptureTime, sess__session_id, rqst__request_id, TimeIdentifier, sess__login_time, sess__host_name, 
		sess__program_name, sess__host_process_id, sess__client_version, sess__client_interface_name, sess__login_name, 
		sess__status_code, sess__cpu_time, sess__memory_usage, sess__total_scheduled_time, sess__total_elapsed_time, 
		sess__endpoint_id, sess__last_request_start_time, sess__last_request_end_time, sess__reads, sess__writes, 
		sess__logical_reads, sess__is_user_process, sess__transaction_isolation_level, sess__lock_timeout, 
		sess__deadlock_priority, sess__row_count, sess__original_login_name, sess__open_transaction_count, 
		sess__group_id, sess__database_id, sess__FKDimLoginName, sess__FKDimSessionAttribute, conn__connect_time, 
		conn__net_transport, conn__protocol_type, conn__protocol_version, conn__endpoint_id, conn__encrypt_option, 
		conn__auth_scheme, conn__node_affinity, conn__net_packet_size, conn__client_net_address, conn__client_tcp_port, 
		conn__local_net_address, conn__local_tcp_port, conn__FKDimNetAddress, conn__FKDimConnectionAttribute, 
		rqst__start_time, rqst__status_code, rqst__command, rqst__sql_handle, rqst__statement_start_offset, 
		rqst__statement_end_offset, rqst__plan_handle, rqst__blocking_session_id, rqst__wait_type, rqst__wait_latch_subtype, 
		rqst__wait_time, rqst__wait_resource, rqst__open_transaction_count, rqst__open_resultset_count, rqst__percent_complete, 
		rqst__cpu_time, rqst__total_elapsed_time, rqst__scheduler_id, rqst__reads, rqst__writes, rqst__logical_reads, 
		rqst__transaction_isolation_level, rqst__lock_timeout, rqst__deadlock_priority, rqst__row_count, rqst__granted_query_memory, 
		rqst__executing_managed_code, rqst__group_id, rqst__query_hash, rqst__query_plan_hash,
		rqst__FKDimCommand, rqst__FKDimWaitType, tempdb__sess_user_objects_alloc_page_count, 
		tempdb__sess_user_objects_dealloc_page_count, tempdb__sess_internal_objects_alloc_page_count, 
		tempdb__sess_internal_objects_dealloc_page_count, tempdb__task_user_objects_alloc_page_count, 
		tempdb__task_user_objects_dealloc_page_count, tempdb__task_internal_objects_alloc_page_count, 
		tempdb__task_internal_objects_dealloc_page_count, tempdb__CalculatedNumberOfTasks, 
		tempdb__CalculatedCurrentTempDBUsage_pages, mgrant__request_time, mgrant__grant_time, mgrant__requested_memory_kb, 
		mgrant__required_memory_kb, mgrant__granted_memory_kb, mgrant__used_memory_kb, mgrant__max_used_memory_kb, mgrant__dop, 
		calc__record_priority, calc__is_compiling, calc__duration_ms, calc__blocking_session_id, calc__block_relevant, 
		calc__return_to_user, calc__is_blocker, calc__sysspid_isinteresting, calc__tmr_wait, calc__threshold_ignore, 
		calc__FKSQLStmtStoreID, calc__FKSQLBatchStoreID, 2 
	FROM #sessions_and_requests sar;

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_TAWException (
		SPIDCaptureTime, UTCCaptureTime, task_address, parent_task_address, session_id, request_id, exec_context_id, 
		tstate, scheduler_id, context_switches_count, wait_type, wait_latch_subtype, wait_duration_ms, 
		wait_special_category, wait_order_category, wait_special_number, wait_special_tag, task_priority, 
		blocking_task_address, blocking_session_id, blocking_exec_context_id, resource_description, 
		resource_dbid, resource_associatedobjid, RecordReason)
	SELECT @lv__SPIDCaptureTime, @lv__UTCCaptureTime, task_address, parent_task_address, session_id, request_id, exec_context_id, 
		taw.tstate, taw.scheduler_id, context_switches_count, wait_type, wait_latch_subtype, wait_duration_ms, 
		wait_special_category, wait_order_category, wait_special_number, wait_special_tag, task_priority, 
		blocking_task_address, blocking_session_id, blocking_exec_context_id, resource_description, 
		resource_dbid, resource_associatedobjid, 2
	FROM #tasks_and_waits taw;

	RAISERROR(@err__ErrorText, @err__ErrorSeverity, @err__ErrorState);
	RETURN -1;
END CATCH

	RETURN 0;
END
GO