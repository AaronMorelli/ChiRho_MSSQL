SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_ViewFrequentQueries
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

	FILE NAME: AutoWho_ViewFrequentQueries.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ViewFrequentQueries

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Called by the sp_XR_FrequentQueries user-facing procedure. 
		The logic below pulls data from the various AutoWho tables, based on parameter values, and combines
		and formats the data as appropriate. 


	FORMATTING: There are 3 types of "output groups". See the large "Identifying Rows" comment below.

		idle spid, input buffer
			Always just 1 row. Relevant stats are tran-related, tempdb-related, session-related

		active spid, query hash
			The top row has data is aggregated for *ALL* unique requests that have this query hash
			Then, in "sub-rows", 
			we show up to 5 unique StmtStoreID/PlanStoreID combos that are representative for this query hash
			Those "up-to-5" should be the *most* expensive in terms of duration or resources (not sure which yet, prob duration)

		active spid, based on an individual StmtStoreID for an object statement or ad-hoc-with-NULL-query-hash
			The top row has data is aggregated for *ALL* unique plan IDs that have this stmt store ID

			If there is only 1 unique combo of StmtStoreID/PlanID, there is only 1 row.

			Then, in "sub-rows", we show the most expensive 5 unique PlanIDs with their individual stats.


	METRIC NOTES: 

	FUTURE ENHANCEMENTS: 

To Execute
------------------------

*/
(
	@init		TINYINT,
	@start		DATETIME,	--start/end are local time
	@end		DATETIME,
	@minocc		INT,
	@spids		NVARCHAR(128)=N'',
	@xspids		NVARCHAR(128)=N'',
	@dbs		NVARCHAR(512)=N'',
	@xdbs		NVARCHAR(512)=N'',
	@attr		NCHAR(1),
	@plan		NCHAR(1),
	@context	NCHAR(1),
	@units		NVARCHAR(20)
)
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET XACT_ABORT ON;
	SET ANSI_WARNINGS ON;

	/* Definition of our "Identifying rows" logic

		1. Obtain "identifying rows". Here are the possible identifiers. (a, b, c)
			The sub-cases are *NOT* identifying rows, though they will affect the output rows and how data is displayed

			a. Idle spid, FKInputBufferID

			b. Active spid, ad-hoc query (no object id in stmt store), non-null Query Hash ID

				i. only 1 StmtStore/PlanID representative  (take @plan variable into account here)

				ii. more than 1 StmtStore/PlanID representative (take @plan variable into account here)

			c. Active spid, object query (object id in stmt store) or null query hash ID

				i. only 1 PlanID (always the case if @plan='n')

				ii. more than 1 PlanID 

			d. if @context='y', then we add session_database_id as a grouping column for each of the above scenarios.

		2. We calculate input buffer stats and place into #InputBufferStats table. These are a bit more straightforward 
			since there's only 1 output row per Input Buffer

		3. We put "identifying rows" into the #TopIdentifiers table. If possible (TODO, find out), we also calculate
			the number of "representatives" (for "b" above) and number of plans (for "c" above) as attributes on
			this table. I think we can also calculate FirstSeen, LastSeen, Number of Unique requests, and TimesSeen.
			
		

	*/


	/****************************************************************************************************
	**********							Variables and Temp Tables							   **********
	*****************************************************************************************************/

	DECLARE 
		--stmt store
		@PKSQLStmtStoreID			BIGINT, 
		@sql_handle					VARBINARY(64),
		@dbid						INT,
		@objectid					INT,
		@stmt_text					NVARCHAR(MAX),
		@stmt_xml					XML,
		@dbname						NVARCHAR(128),
		@schname					NVARCHAR(128),
		@objectname					NVARCHAR(128),

		--QueryPlan Stmt/Batch store
		@PKQueryPlanStmtStoreID		BIGINT,
		@PKQueryPlanBatchStoreID	BIGINT,
		@plan_handle				VARBINARY(64),
		@query_plan_text			NVARCHAR(MAX),
		@query_plan_xml				XML,

		--input buffer store
		@PKInputBufferStore			BIGINT,
		@ibuf_text					NVARCHAR(4000),
		@ibuf_xml					XML,

		--General variables
		@DBInclusionsExist			INT,
		@DBExclusionsExist			INT,
		@SPIDInclusionsExist		INT,
		@SPIDExclusionsExist		INT,
		@cxpacketwaitid				SMALLINT,

		--Enums
		@enum__waitorder__none				TINYINT,
		@enum__waitorder__lck				TINYINT,
		@enum__waitorder__latchblock		TINYINT,
		@enum__waitorder_pglatch			TINYINT,
		@enum__waitorder__cxp				TINYINT,
		@enum__waitorder__other				TINYINT
		;

	DECLARE 
		--misc control-flow helpers
		@lv__scratchint				INT,
		@lv__msg					NVARCHAR(MAX),
		@lv__errsev					INT,
		@lv__errstate				INT,
		@lv__errorloc				NVARCHAR(100),
		@lv__nullstring				NVARCHAR(8),
		@lv__nullint				INT,
		@lv__nullsmallint			SMALLINT,
		@lv__DynSQL					NVARCHAR(MAX),
		@lv__DynSQL_base			NVARCHAR(MAX);

	DECLARE 
		@lv__NumQueryHash		INT,
		@lv__NumIB				INT,
		@lv__NumStmtStore		INT;

BEGIN TRY
	/********************************************************************************************************************************
						 SSSS    EEEE   TTTTT   U    U    PPPP  
						S        E        T     U    U    P   P
						 SSSS    EEEE     T     U    U    PPPP
							 S   E        T     U    U    P
						 SSSS    EEEE     T      UUUU     P

	********************************************************************************************************************************/
	SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" would collide with a DMV value
	SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
	SET @lv__nullsmallint = -929;			-- overlapping with some special system value

	SET @enum__waitorder__none =			CONVERT(TINYINT, 250);		--a. we typically want a "not waiting" task to sort near the end 
	SET @enum__waitorder__lck =				CONVERT(TINYINT, 5);		--b. lock waits should be at the top (so that blocking data is correct)
	SET @enum__waitorder__latchblock =		CONVERT(TINYINT, 10);		--c. sometimes latch waits can have a blocking spid, so those sort next, after lock waits.
																		--	these can be any type of latch (pg, pgio, a memory object, etc); 
	SET @enum__waitorder_pglatch =			CONVERT(TINYINT, 15);		-- Page and PageIO latches are fairly common, and in parallel plans we want them
																		-- to sort higher than other latches, e.g. the fairly common ACCESS_METHODS_DATASET_PARENT
	SET @enum__waitorder__cxp =				CONVERT(TINYINT, 200);		--d. parallel sorts near the end, since a parallel wait doesn't mean the spid is completely halted
	SET @enum__waitorder__other =			CONVERT(TINYINT, 20);		--e. catch-all bucket

	SELECT @cxpacketwaitid = dwt.DimWaitTypeID
	FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
	WHERE dwt.wait_type = N'CXPACKET';

	SET @lv__errorloc = N'Declare #TT';
	CREATE TABLE #FilterTab
	(
		FilterType	TINYINT NOT NULL, 
			--0 DB inclusion
			--1 DB exclusion
			--2 SPID inclusion
			--3 SPID exclusion
		FilterID	INT NOT NULL, 
		FilterName	NVARCHAR(255)
	); --TODO: need to implement this logic.

	CREATE TABLE #CaptureTimes (
		SPIDCaptureTime		DATETIME NOT NULL,
		UTCCaptureTime		DATETIME NOT NULL,
		PrevUTCCaptureTime	DATETIME,
		diffMS				INT		--diff in milliseconds between cap time and PrevCaptureTime
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #CaptureTimes (UTCCaptureTime);

	CREATE TABLE #IBHeaders (
		PKInputBufferStoreID	BIGINT NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		UniqueOccurrences		INT NOT NULL,
		NumCaptureRows			INT NOT NULL,
		FirstSeenUTC			DATETIME NOT NULL,	--we calculate these,
		LastSeenUTC				DATETIME NOT NULL,
		FirstSeen				DATETIME NULL,	--but we display these to the user
		LastSeen				DATETIME NULL,
		DisplayOrder			INT NULL
	);

	CREATE TABLE #IBInstances (
		session_id				SMALLINT NOT NULL,
		TimeIdentifier			DATETIME NOT NULL,

		PKInputBufferStoreID	BIGINT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator
		NumCaptureRows			INT NOT NULL,
		FirstSeenUTC			DATETIME NOT NULL,	--we calculate these,
		LastSeenUTC				DATETIME NOT NULL,
		FirstSeen				DATETIME NULL,	--but we display these to the user
		LastSeen				DATETIME NULL
	);

	--Cache the most important data that we need
	CREATE TABLE #IBRawStats (
		--identifier fields
		session_id				SMALLINT,
		TimeIdentifier			DATETIME NOT NULL,

		PKInputBufferStoreID	BIGINT NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		--Attributes. Each of these values is from the last time the idle spid (spid/TimeIdentifier) was seen
		sess__cpu_time			INT NULL,
		sess__reads				BIGINT NULL,
		sess__writes			BIGINT NULL,
		sess__logical_reads		BIGINT NULL,
		sess__open_transaction_count	INT NULL,
		calc__duration_ms		BIGINT NULL,
		TempDBAlloc_pages		BIGINT,
		TempDBUsed_pages		BIGINT,
		LongestTranLength_ms	BIGINT,
		NumLogRecords			BIGINT,
		LogUsed_bytes			BIGINT,
		LogReserved_bytes		BIGINT,
		HasSnapshotTran			TINYINT
	);


	CREATE TABLE #QHHeaders (
		query_hash				BINARY(8) NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		UniqueOccurrences		INT NOT NULL,
		NumCaptureRows			INT NOT NULL,
		FirstSeenUTC			DATETIME NOT NULL,	--we calculate these,
		LastSeenUTC				DATETIME NOT NULL,
		FirstSeen				DATETIME NULL,	--but we display these to the user
		LastSeen				DATETIME NULL,
		DisplayOrder			INT NULL,

		cpu_time				BIGINT NULL
	);

	CREATE TABLE #QHSubHeaders (
		query_hash				BINARY(8) NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		PKSQLStmtStoreID		[bigint] NOT NULL,
		PKQueryPlanStmtStoreID	[bigint] NOT NULL,

		UniqueOccurrences		INT NOT NULL,
		NumCaptureRows			INT NOT NULL,
		FirstSeenUTC			DATETIME NOT NULL,	--we calculate these,
		LastSeenUTC				DATETIME NOT NULL,
		FirstSeen				DATETIME NULL,	--but we display these to the user
		LastSeen				DATETIME NULL,
		DisplayOrder			INT NULL,			--this is across statements within a single query_hash/DBID group

		cpu_time				BIGINT NULL
	);

	CREATE TABLE #QHInstances (
		--These are the identifying columns. The granularity of this table is a statement
		session_id				SMALLINT NOT NULL,
		request_id				SMALLINT NOT NULL,
		TimeIdentifier			DATETIME NOT NULL,
		StatementFirstCaptureUTC DATETIME NOT NULL,
		StatementLastCaptureUTC	DATETIME NOT NULL,
		PreviousCaptureTimeUTC	DATETIME NULL,		--we store this just for the first cap of a new statement. It allows us to get the final cap of the prev
													--stmt (if one exists) so we can do a delta of the stats

		query_hash				BINARY(8) NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		PKSQLStmtStoreID		[bigint] NOT NULL,
		PKQueryPlanStmtStoreID	[bigint] NOT NULL,

		NumCaptureRows			INT NOT NULL
	);


	CREATE TABLE #ObjStmtHeaders (
		PKSQLStmtStoreID		[bigint] NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		UniqueOccurrences		INT NOT NULL,
		NumCaptureRows			INT NOT NULL,
		FirstSeenUTC			DATETIME NOT NULL,
		LastSeenUTC				DATETIME NOT NULL,
		FirstSeen				DATETIME NULL,
		LastSeen				DATETIME NULL,
		DisplayOrder			INT NULL,

		cpu_time				BIGINT NULL
	);

	CREATE TABLE #ObjStmtSubHeaders (
		PKSQLStmtStoreID		[bigint] NOT NULL,
		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		PKQueryPlanStmtStoreID	[bigint] NOT NULL,

		UniqueOccurrences		INT NOT NULL,
		NumCaptureRows			INT NOT NULL,
		FirstSeenUTC			DATETIME NOT NULL,
		LastSeenUTC				DATETIME NOT NULL,
		FirstSeen				DATETIME NOT NULL,
		LastSeen				DATETIME NOT NULL,
		DisplayOrder			INT NULL,			--this is across statements within a single PKSQLStmtStoreID/DBID group

		cpu_time				BIGINT NULL
	);

	CREATE TABLE #ObjStmtInstances (
		--These are the identifying columns. The granularity of this table is a statement
		session_id				SMALLINT NOT NULL,
		request_id				SMALLINT NOT NULL,
		TimeIdentifier			DATETIME NOT NULL,
		StatementFirstCaptureUTC DATETIME NOT NULL,

		StatementLastCaptureUTC	DATETIME NOT NULL,
		PreviousCaptureTimeUTC	DATETIME NULL,	--we store this just for the first cap of a new statement. It allows us to get the final cap of the prev
												--stmt (if one exists) so we can do a delta of the stats												

		sess__database_id		SMALLINT NULL,		--If @context=N'N', then we leave this NULL so that it is not a differentiator
													--If @context=N'Y', then we pull it and group by it, so that it IS a differentiator

		PKSQLStmtStoreID		[bigint] NOT NULL,
		PKQueryPlanStmtStoreID	[bigint] NOT NULL,

		NumCaptureRows			INT NOT NULL
	);


	-- There is also the possibility that conversion to XML will fail, so we don't want to wait until the final join.
	-- This temp table is our workspace for that resolution/conversion work.
	CREATE TABLE #InputBufferStore (
		PKInputBufferStoreID	BIGINT NOT NULL,
		inputbuffer				NVARCHAR(4000) NOT NULL,
		inputbuffer_xml			XML
	);

	--Ditto, Stmt Store conversions to XML can fail.
	CREATE TABLE #SQLStmtStore (
		PKSQLStmtStoreID		BIGINT NOT NULL,
		[sql_handle]			VARBINARY(64) NOT NULL,
		statement_start_offset	INT NOT NULL,
		statement_end_offset	INT NOT NULL, 
		[dbid]					SMALLINT NOT NULL,
		[objectid]				INT NOT NULL,
		datalen_batch			INT NOT NULL,
		stmt_text				NVARCHAR(MAX) NOT NULL,
		stmt_xml				XML,
		dbname					NVARCHAR(128),
		schname					NVARCHAR(128),
		objname					NVARCHAR(128)
	);

	--Ditto, QP conversions to XML can fail.
	CREATE TABLE #QueryPlanStmtStore (
		PKQueryPlanStmtStoreID		BIGINT NOT NULL,
		[plan_handle]				VARBINARY(64) NOT NULL,
		--statement_start_offset		INT NOT NULL,
		--statement_end_offset		INT NOT NULL,
		--[dbid]						SMALLINT NOT NULL,
		--[objectid]					INT NOT NULL,
		query_plan_text				NVARCHAR(MAX) NOT NULL,
		query_plan_xml				XML
	);


	SET @lv__errorloc = N'Obtain #TimeMinus1';
	IF @init = 255
	BEGIN
		INSERT INTO #CaptureTimes (
			UTCCaptureTime,
			SPIDCaptureTime,
			PrevUTCCaptureTime,
			diffMS
		)
		SELECT 
			ct.UTCCaptureTime,
			ct.SPIDCaptureTime, 
			[PrevUTCCaptureTime] = prevCap.UTCCaptureTime,
			[diffMS] = CASE WHEN prevCap.UTCCaptureTime IS NULL THEN NULL 
				ELSE DATEDIFF(MILLISECOND, prevCap.UTCCaptureTime, ct.UTCCaptureTime)
				END
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
			OUTER APPLY (
				SELECT TOP 1
					ct2.UTCCaptureTime
				FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct2
				WHERE ct2.UTCCaptureTime < ct.UTCCaptureTime
				AND ct2.RunWasSuccessful = 1
				--Only pull the prev time if it was fairly close to the current row
				AND ct2.UTCCaptureTime > DATEADD(MINUTE, -2, ct.UTCCaptureTime)
				ORDER BY ct2.UTCCaptureTime DESC
			) prevCap
		WHERE ct.SPIDCaptureTime BETWEEN @start AND @end	--we search by local, but our logic heavily depends on UTC
		AND ct.RunWasSuccessful = 1;
	END
	ELSE
	BEGIN
		INSERT INTO #CaptureTimes (
			UTCCaptureTime,
			SPIDCaptureTime,
			PrevUTCCaptureTime,
			diffMS
		)
		SELECT 
			ct.UTCCaptureTime,
			ct.SPIDCaptureTime, 
			[PrevUTCCaptureTime] = prevCap.UTCCaptureTime,
			[diffMS] = CASE WHEN prevCap.UTCCaptureTime IS NULL THEN NULL 
				ELSE DATEDIFF(MILLISECOND, prevCap.UTCCaptureTime, ct.UTCCaptureTime)
				END
		FROM @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionTimes ct
			OUTER APPLY (
				SELECT TOP 1
					ct2.UTCCaptureTime
				FROM @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionTimes ct2
				WHERE ct2.UTCCaptureTime < ct.UTCCaptureTime
				AND ct2.UTCCaptureTime > DATEADD(MINUTE, -2, ct.UTCCaptureTime)
				ORDER BY ct2.UTCCaptureTime DESC
			) prevCap
		WHERE ct.SPIDCaptureTime BETWEEN @start AND @end;	--we search by local, but our logic heavily depends on UTC
	END

	DECLARE @EffectiveStartUTC	DATETIME,
			@EffectiveEndUTC	DATETIME;
			--@EffectiveStart		DATETIME,
			--@EffectiveEnd		DATETIME;

	SELECT 
		@EffectiveStartUTC = MIN(ct.UTCCaptureTime),
		@EffectiveEndUTC = MAX(ct.UTCCaptureTime)
	FROM #CaptureTimes ct;

	/*
	SELECT @EffectiveStart = ct.SPIDCaptureTime
	FROM #CaptureTimes ct
	WHERE ct.UTCCaptureTime = @EffectiveStartUTC;

	SELECT @EffectiveEnd = ct.SPIDCaptureTime
	FROM #CaptureTimes ct
	WHERE ct.UTCCaptureTime = @EffectiveEndUTC;
	*/
	/*******************************************************************************************************************************
											End of setup
	********************************************************************************************************************************/

	/********************************************************************************************************************************
						 IIIII   N   N   PPPP   U    U   TTTTT      BBBB    U    U   FFFF   SSSS 
						   I     NN  N   P   P  U    U 	   T        B   B   U    U   F	   S     
						   I     N N N   PPPP	U    U 	   T        BBBB    U    U   FFFF   SSSS 
						   I     N  NN   P		U    U 	   T        B   B   U    U   F	   	    S
					     IIIII   N   N   P		 UUUU  	   T        BBBB     UUUU    F	    SSSS 

	********************************************************************************************************************************/
	SET @lv__errorloc = N'Populate #IBInstances';
	INSERT INTO #IBInstances (
		session_id,
		TimeIdentifier,

		PKInputBufferStoreID,
		sess__database_id,

		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC
	)
	SELECT 
		session_id,
		TimeIdentifier,

		PKInputBufferStoreID,
		sess__database_id,

		[NumCaptureRows] = SUM(1),
		[FirstSeenUTC] = MIN(UTCCaptureTime),	--Note: we'll update the local times further down,
		[LastSeenUTC] = MAX(UTCCaptureTime)		--using the translation in #CaptureTimes
	FROM (
		SELECT 
			session_id,
			TimeIdentifier,		--this is the start time of the SAR record, i.e. the idle start time

			[PKInputBufferStoreID] = sar.FKInputBufferStoreID,
			[sess__database_id] = CASE WHEN @context = N'N' THEN NULL ELSE sar.sess__database_id END,

			ct.UTCCaptureTime
		FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
			INNER JOIN #CaptureTimes ct		--So that we don't include unsuccessful runs
				ON ct.UTCCaptureTime = sar.UTCCaptureTime
		WHERE sar.CollectionInitiatorID = @init
		AND sar.UTCCaptureTime BETWEEN @EffectiveStartUTC AND @EffectiveEndUTC
		AND sar.sess__is_user_process = 1
		AND sar.calc__threshold_ignore = 0
		AND sar.request_id = @lv__nullsmallint 
		AND sar.FKInputBufferStoreID IS NOT NULL
		--Idle spid with an input buffer. (Idle spids w/durations shorter than our IB capture threshold won't be captured)
	) ss
	GROUP BY session_id, 
		TimeIdentifier, 
		PKInputBufferStoreID, 
		sess__database_id;

	SET @lv__errorloc = N'Populate #IBHeaders';
	INSERT INTO #IBHeaders (
		PKInputBufferStoreID,
		sess__database_id,

		UniqueOccurrences,
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder
	)
	SELECT 
		PKInputBufferStoreID,
		sess__database_id,
		UniqueOccurrences,
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder = ROW_NUMBER() OVER (ORDER BY UniqueOccurrences DESC)
	FROM (
		SELECT 
			ib.PKInputBufferStoreID,
			ib.sess__database_id,

			UniqueOccurrences = SUM(1),
			NumCaptureRows = SUM(NumCaptureRows),
			FirstSeenUTC = MIN(FirstSeenUTC),
			LastSeenUTC = MAX(LastSeenUTC)
		FROM #IBInstances ib
		GROUP BY ib.PKInputBufferStoreID,
				ib.sess__database_id
	) ss;

	--Do the UTC->local translation
	UPDATE targ 
	SET FirstSeen = ct1.SPIDCaptureTime,
		LastSeen = ct2.SPIDCaptureTime
	FROM #IBHeaders targ 
		INNER JOIN #CaptureTimes ct1
			ON targ.FirstSeenUTC = ct1.UTCCaptureTime
		INNER JOIN #CaptureTimes ct2
			ON targ.LastSeenUTC = ct2.UTCCaptureTime;

	UPDATE targ 
	SET FirstSeen = ct1.SPIDCaptureTime,
		LastSeen = ct2.SPIDCaptureTime
	FROM #IBInstances targ 
		INNER JOIN #CaptureTimes ct1
			ON targ.FirstSeenUTC = ct1.UTCCaptureTime
		INNER JOIN #CaptureTimes ct2
			ON targ.LastSeenUTC = ct2.UTCCaptureTime;

	SET @lv__errorloc = N'Populate #IBRawStats';
	INSERT INTO #IBRawStats (
		--identifier fields
		session_id,
		TimeIdentifier,

		PKInputBufferStoreID,
		sess__database_id,

		--Attributes. Each of these values is from the last time the idle spid (spid/TimeIdentifier) was seen
		sess__cpu_time,
		sess__reads,
		sess__writes,
		sess__logical_reads,
		sess__open_transaction_count,
		calc__duration_ms,
		TempDBAlloc_pages,
		TempDBUsed_pages,
		LongestTranLength_ms,
		NumLogRecords,
		LogUsed_bytes,
		LogReserved_bytes,
		HasSnapshotTran
	)
	SELECT 
		ibi.session_id,
		ibi.TimeIdentifier,

		ibi.PKInputBufferStoreID,
		ibi.sess__database_id,
		sar.sess__cpu_time,
		sar.sess__reads,
		sar.sess__writes,
		sar.sess__logical_reads,
		sar.sess__open_transaction_count,
		sar.calc__duration_ms,
		TempDBAlloc_pages = (
				ISNULL(tempdb__sess_user_objects_alloc_page_count,0) + ISNULL(tempdb__sess_internal_objects_alloc_page_count,0) + 
				ISNULL(tempdb__task_user_objects_alloc_page_count,0) + ISNULL(tempdb__task_internal_objects_alloc_page_count,0)),
		TempDBUsed_pages = (
				CASE WHEN (ISNULL(sar.tempdb__sess_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_user_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__sess_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_user_objects_dealloc_page_count,0)) END + 
				CASE WHEN (ISNULL(sar.tempdb__sess_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_internal_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__sess_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_internal_objects_dealloc_page_count,0)) END + 
				CASE WHEN (ISNULL(sar.tempdb__task_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_user_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__task_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_user_objects_dealloc_page_count,0)) END + 
				CASE WHEN (ISNULL(sar.tempdb__task_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_internal_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__task_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_internal_objects_dealloc_page_count,0)) END),
		td.LongestTranLength_ms,
		td.NumLogRecords,
		td.LogUsed_bytes,
		td.LogReserved_bytes,
		td.HasSnapshotTran
	FROM #IBInstances ibi
		INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
			ON ibi.session_id = sar.session_id
			AND ibi.TimeIdentifier = sar.TimeIdentifier
			AND ibi.LastSeenUTC = sar.UTCCaptureTime		--we want the stats of the idle spid as of the last time it was seen
		INNER JOIN (
			SELECT 
				td.UTCCaptureTime,
				td.session_id,
				LongestTranLength_ms = MAX(DATEDIFF(MILLISECOND, td.dtat_transaction_begin_time, td.SPIDCaptureTime)),
				NumLogRecords = SUM(ISNULL(td.dtdt_database_transaction_log_record_count,0)),
				LogUsed_bytes = SUM(ISNULL(td.dtdt_database_transaction_log_bytes_used,0) + ISNULL(td.dtdt_database_transaction_log_bytes_used_system,0)),
				LogReserved_bytes = SUM(ISNULL(td.dtdt_database_transaction_log_bytes_reserved,0) + ISNULL(td.dtdt_database_transaction_log_bytes_reserved_system,0)),
				HasSnapshotTran = MAX(CONVERT(TINYINT,td.dtasdt_tran_exists))
			FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails td
			WHERE td.CollectionInitiatorID = @init
			AND td.UTCCaptureTime BETWEEN @EffectiveStartUTC AND @EffectiveEndUTC
			GROUP BY td.UTCCaptureTime, td.session_id
		) td
			ON sar.UTCCaptureTime = td.UTCCaptureTime
			AND sar.session_id = td.session_id
	WHERE sar.CollectionInitiatorID = @init
	AND sar.UTCCaptureTime BETWEEN @EffectiveStartUTC AND @EffectiveEndUTC
	AND sar.sess__is_user_process = 1
	AND sar.calc__threshold_ignore = 0;


	--Resolve the Input Buffer IDs to the corresponding text.
	SET @lv__errorloc = N'Obtain IB raw text';
	INSERT INTO #InputBufferStore (
		PKInputBufferStoreID,
		inputbuffer
		--inputbuffer_xml
	)
	SELECT ibs.PKInputBufferStoreID,
		ibs.InputBuffer
	FROM @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore ibs
		INNER JOIN #IBHeaders ibh
			ON ibs.PKInputBufferStoreID = ibh.PKInputBufferStoreID;

	SET @lv__errorloc = N'Declare IB cursor';
	DECLARE resolveInputBufferStore  CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		PKInputBufferStoreID,
		inputbuffer
	FROM #InputBufferStore;

	SET @lv__errorloc = N'Open IB cursor';
	OPEN resolveInputBufferStore;
	FETCH resolveInputBufferStore INTO @PKInputBufferStore,@ibuf_text;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @lv__errorloc = N'In IB loop';
		IF @ibuf_text IS NULL
		BEGIN
			SET @ibuf_xml = CONVERT(XML, N'<?InputBuffer --' + NCHAR(10)+NCHAR(13) + N'The Input Buffer is NULL.' + NCHAR(10) + NCHAR(13) + 
			N'PKInputBufferStore: ' + CONVERT(NVARCHAR(20),ISNULL(@PKInputBufferStore,-1)) + 
			NCHAR(10) + NCHAR(13) + N'-- ?>');
		END
		ELSE
		BEGIN
			BEGIN TRY
				SET @ibuf_xml = CONVERT(XML, N'<?InputBuffer --' + NCHAR(10)+NCHAR(13) + @ibuf_text + + NCHAR(10) + NCHAR(13) + 
				N'PKInputBufferStore: ' + CONVERT(NVARCHAR(20),ISNULL(@PKInputBufferStore,-1)) + 
				NCHAR(10) + NCHAR(13) + N'-- ?>');
			END TRY
			BEGIN CATCH
				SET @ibuf_xml = CONVERT(XML, N'<?InputBuffer --' + NCHAR(10)+NCHAR(13) + N'Error CONVERTing Input Buffer to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
				N'PKInputBufferStore: ' + CONVERT(NVARCHAR(20),ISNULL(@PKInputBufferStore,-1)) + 
				NCHAR(10) + NCHAR(13) + N'-- ?>');
			END CATCH
		END

		UPDATE #InputBufferStore
		SET inputbuffer_xml = @ibuf_xml
		WHERE PKInputBufferStoreID = @PKInputBufferStore;

		FETCH resolveInputBufferStore INTO @PKInputBufferStore,@ibuf_text;
	END

	CLOSE resolveInputBufferStore;
	DEALLOCATE resolveInputBufferStore;
	/*******************************************************************************************************************************
											End of Input Buffers section
	********************************************************************************************************************************/


	/********************************************************************************************************************************
						  QQQQ     H   H      PPPP    PPPP    EEEEE   PPPP  
						 Q    Q    H   H      P   P	  P   P   E		  P   P	
						 Q    Q    HHHHH      PPPP	  PPPP    EEEEE	  PPPP	
						 Q    Q    H   H      P		  P  R    E		  P		
					      QQQQ     H   H      P		  P   R   EEEEE	  P		
						      Q
	********************************************************************************************************************************/
	/*
		The "QH" section focuses on ad-hoc SQL (NULL AutoWho.SQLStmtStore.object_id field). The identifier here is a query_hash, the
		signature of the text of a sql statement. We want to show queries that have run many times, and aggregate their stats.
		However, unlike the Input Buffer set where we only have 1 row per query, we want to show a representative sample of the
		data associated with a single query_hash value. This takes the form "top X StmtStoreID rows" under each query hash,
		where "top" means top # of executions. (We may give more ordering options at a later time). 
		If query plans are desired, then the key for each "representative row" changes from PKSQLStmtStoreID to PKSQLStmtStoreID/PKQueryPlanStmtStoreID.
		Thus, the same SQLStmtStoreID value could occur multiple times in the "representative rows" section.
	*/

	--First, obtain a list of instances
	SET @lv__errorloc = N'Populate #QHInstances';
	INSERT INTO #QHInstances (
		session_id,
		request_id,
		TimeIdentifier,
		StatementFirstCaptureUTC,

		StatementLastCaptureUTC,
		PreviousCaptureTimeUTC,
		query_hash,
		sess__database_id,
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,
		NumCaptureRows
	)
	SELECT 
		session_id,
		request_id,
		TimeIdentifier,
		StatementFirstCaptureUTC,

		StatementLastCaptureUTC,
		PreviousCaptureTimeUTC,
		query_hash,
		sess__database_id,
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,
		NumCaptureRows
	FROM (
		SELECT 
			--Each row signifies the execution of an individual statement
			ss.session_id,
			ss.request_id,
			ss.TimeIdentifier,
			ss.StatementFirstCaptureUTC,

			[StatementLastCaptureUTC] = MAX(ss.StatementLastCaptureUTC),	--only 1 row should be non-null so we obtain that
			[PreviousCaptureTimeUTC] = MAX(ss.PreviousCaptureTimeUTC),		--ditto
			[query_hash] = MAX(ss.query_hash),
			[sess__database_id] = MAX(sess__database_id),		--this orders a real DBID over the -1 that we have if it is NULL in SAR. This should be safe b/c
										--while Context DBID could change within a batch, it shouldn't change within a statement.
			[PKSQLStmtStoreID] = MAX(PKSQLStmtStoreID),
			[PKQueryPlanStmtStoreID] = MAX(PKQueryPlanStmtStoreID),
			[NumCaptureRows] = SUM(1)
		FROM (
			SELECT 
				sct.session_id,
				sct.request_id,
				sct.TimeIdentifier,
				sct.StatementFirstCaptureUTC,
				--We only capture 1 non-NULL value on these 2 fields so that we can apply MAX later to obtain it when we decrease granularity
				[StatementLastCaptureUTC] = CASE WHEN sct.IsStmtLastCapture = 1 OR sct.IsCurrentLastRowOfBatch = 1 
											THEN sct.UTCCaptureTime ELSE NULL END,
				[PreviousCaptureTimeUTC] = CASE WHEN sct.IsStmtFirstCapture = 1 THEN sct.PreviousCaptureTimeUTC ELSE NULL END,

				[query_hash] = CASE WHEN sct.IsStmtLastCapture = 1 OR sct.IsCurrentLastRowOfBatch = 1 THEN sct.rqst__query_hash ELSE NULL END,
				[sess__database_id] = CASE WHEN @context=N'Y' THEN ISNULL(sct.sess__database_id,-1) ELSE -1 END,

				[PKQueryPlanStmtStoreID] = CASE WHEN sct.IsStmtLastCapture = 1 OR sct.IsCurrentLastRowOfBatch = 1 
												THEN ISNULL(sct.PKQueryPlanStmtStoreID,-1)
												ELSE -1 END,

				sct.PKSQLStmtStoreID			--TODO: for now, this should be the same for all caps for the same statement. However, once we implement
												--TMR waits, that assumption may not be true anymore. May need to revisit.
			FROM @@CHIRHO_SCHEMA@@.AutoWho_StatementCaptureTimes sct
				LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore sss
					ON sct.PKSQLStmtStoreID = sss.PKSQLStmtStoreID
					AND sss.objectid = @lv__nullint
			WHERE sct.StatementFirstCaptureUTC BETWEEN @EffectiveStartUTC AND @EffectiveEndUTC
				--notice that we don't use UTCCaptureTime or SPIDCaptureTime here, because we don't want to grab partial
				--sets of rows for any statements.
		) ss
		GROUP BY ss.session_id,
			ss.request_id,
			ss.TimeIdentifier,
			ss.StatementFirstCaptureUTC
	) ss2
	WHERE ss2.query_hash IS NOT NULL;	--This can happen if the query hash is null for every UTCCaptureTime of the ad-hoc SQL. WAITFOR is an example of this.

	SET @lv__errorloc = N'Populate #QHHeaders';
	INSERT INTO #QHHeaders (
		query_hash,
		sess__database_id,
		UniqueOccurrences,		--the total # of unique executed statements for this query_hash/ContextDBID combination
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder
	)
	SELECT 
		query_hash,
		sess__database_id,
		UniqueOccurrences,
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder = ROW_NUMBER() OVER (ORDER BY UniqueOccurrences DESC)
	FROM (
		SELECT 
			qhi.query_hash,
			qhi.sess__database_id,
			UniqueOccurrences = SUM(1),
			NumCaptureRows = SUM(NumCaptureRows),
			FirstSeenUTC = MIN(qhi.StatementFirstCaptureUTC),
			LastSeenUTC = MAX(qhi.StatementLastCaptureUTC)
		FROM #QHInstances qhi
		GROUP BY qhi.query_hash,
			qhi.sess__database_id
	) ss;

	SET @lv__errorloc = N'Populate #QHSubHeaders';
	INSERT INTO #QHSubHeaders (
		query_hash,
		sess__database_id,

		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,

		UniqueOccurrences,
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder
	)
	SELECT 
		ss.query_hash,
		ss.sess__database_id,
		ss.PKSQLStmtStoreID,
		ss.PKQueryPlanStmtStoreID,
		ss.NumUniqueStatements,
		ss.NumCaptureRows,
		ss.FirstSeenUTC,
		ss.LastSeenUTC,
		[DisplayOrder] = ROW_NUMBER() OVER (PARTITION BY ss.query_hash, ss.sess__database_id
											ORDER BY ss.NumUniqueStatements DESC
											)
	FROM (
		--The granularity of #QHInstances is a statement.
		--The effective granularity of this subquery is 
		--	query_hash/DBID (if @context='Y')/PKSQLStmtStoreID/PKQueryPlanStmtStoreID (if @plan='Y')
		SELECT 
			qhi.query_hash,
			qhi.sess__database_id,

			qhi.PKSQLStmtStoreID,
			qhi.PKQueryPlanStmtStoreID,
				
			[NumUniqueStatements] = SUM(1),
			[NumCaptureRows] = SUM(qhi.NumCaptureRows),
			[FirstSeenUTC] = MIN(qhi.StatementFirstCaptureUTC),
			[LastSeenUTC] = MAX(qhi.StatementLastCaptureUTC)
		FROM #QHInstances qhi
		GROUP BY qhi.query_hash,
			qhi.sess__database_id,
			qhi.PKSQLStmtStoreID,
			qhi.PKQueryPlanStmtStoreID
	) ss;

	--Now we can calc stats and update QH Sub-headers
	SET @lv__errorloc = N'Calc stats for #QHSubHeaders';
	UPDATE qhs
	SET cpu_time = qhi.cpu_time
	FROM #QHSubHeaders qhs
		INNER JOIN (
			--We're glossing over a step here. More explicit logic would be to first calculate the cpu time of each statement
			-- (group by the identifying fields of #QHInstances) in a sub-query, and then aggregate over the metric (e.g. cpu time) for each statement.
			--However, we can safely just jump to grouping by our sub-header rows.
			SELECT
				qhi.query_hash, 
				qhi.sess__database_id,
				qhi.PKSQLStmtStoreID,
				qhi.PKQueryPlanStmtStoreID,
				cpu_time = SUM(sar.rqst__cpu_time - ISNULL(sarprev.rqst__cpu_time,0))   --Note that we essentially apportion ALL of the resource usage between the last cap of the prev stmt
																						-- and the first capture of this statement to this statement. That could be very incorrect: the prev stmt
																						-- could have ended 5 ms before the first capture of this statement, meaning that practically all of the
																						-- delta we're calculating really should be apportioned to the prev stmt. But we can't know that, given the
																						-- polling architecture of AutoWho. There's no perfect solution, but at least we'll be consistent w/our methodology.

				/* Metrics still to do (I may not do all of them)

					SAR
						[calc__duration_ms]
						blocking info e.g. [calc__blocking_session_id] and [calc__is_blocker]
						rqst__status_code
						rqst__open_transaction_count
						rqst__reads
						rqst__writes
						rqst__logical_reads
						rqst__transaction_isolation_level
						rqst__row_count
						rqst__granted_query_memory
						tempdb__sess_user_objects_alloc_page_count
						tempdb__sess_user_objects_dealloc_page_count
						tempdb__sess_internal_objects_alloc_page_count
						tempdb__sess_internal_objects_dealloc_page_count
						tempdb__task_user_objects_alloc_page_count
						tempdb__task_user_objects_dealloc_page_count
						tempdb__task_internal_objects_alloc_page_count
						tempdb__task_internal_objects_dealloc_page_count
						tempdb__CalculatedNumberOfTasks
						mgrant__request_time	and   mgrant__grant_time		i.e. the avg delay here
						mgrant__requested_memory_kb
						mgrant__granted_memory_kb
						mgrant__used_memory_kb
						mgrant__max_used_memory_kb
						mgrant__dop

						Other stuff to consider:
								calc__tmr_wait
								Something like calc__node_info
								Something like calc__status_info

					TAW
						tstate
						context_switches_count
						FKDimWaitType
						wait_duration_ms

						Other stuff to consider:
							wait_special_category
							wait_special_number
							wait_special_tag
							resource_description
							resource_dbid
							resource_associatedobjid
							cxp_wait_direction
							resolution_successful
							resolved_name


					Tran Details
						calculated # of transactions
						oldest tran begin time (dtat_transaction_begin_time and/or dtdt_database_transaction_begin_time)
						number of DBs that the trans are in (dtdt_database_id)
						dtdt_database_transaction_log_record_count
						dtdt_database_transaction_log_bytes_used
						dtdt_database_transaction_log_bytes_reserved
						dtdt_database_transaction_log_bytes_used_system
						dtdt_database_transaction_log_bytes_reserved_system
						dtasdt_tran_exists
						dtasdt_elapsed_time_seconds
						dtasdt_max_version_chain_traversed
						dtasdt_average_version_chain_traversed

						Other stuff to consider:
							dtst_is_user_transaction
							dtat_dtc_state
							dtat_transaction_state
							dtat_transaction_type
							dtst_is_local
							dtdt_database_transaction_type
							dtdt_database_transaction_state


					Lock Details
						Avg number of locks? (RecordCount)
				*/
			FROM #QHInstances qhi
				INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
					ON qhi.session_id = sar.session_id
					AND qhi.request_id = sar.request_id
					AND qhi.TimeIdentifier = sar.TimeIdentifier
					AND qhi.StatementLastCaptureUTC = sar.UTCCaptureTime	--the last capture will have the highest stats for things like cpu_time and reads
				LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sarprev
					ON qhi.session_id = sarprev.session_id
					AND qhi.request_id = sarprev.request_id
					AND qhi.TimeIdentifier = sarprev.TimeIdentifier
					AND qhi.PreviousCaptureTimeUTC = sarprev.UTCCaptureTime	--the last cap of the previous stmt (if one exists) will allow us to do a delta calculation
																			
			GROUP BY qhi.query_hash, 
				qhi.sess__database_id,
				qhi.PKSQLStmtStoreID,
				qhi.PKQueryPlanStmtStoreID
		) qhi
			ON qhs.query_hash = qhi.query_hash
			AND qhs.sess__database_id = qhi.sess__database_id
			AND qhs.PKSQLStmtStoreID = qhi.PKSQLStmtStoreID
			AND qhs.PKQueryPlanStmtStoreID = qhi.PKQueryPlanStmtStoreID
	;

	--Now aggregate up to #QH Headers
	SET @lv__errorloc = N'Calc stats for #QHHeaders';
	UPDATE qhh 
	SET cpu_time = qhs.cpu_time
		--TODO: more metrics, see above list
	FROM #QHHeaders qhh
		INNER JOIN (
			SELECT 
				qhs.query_hash,
				qhs.sess__database_id,
				cpu_time = SUM(cpu_time)
			FROM #QHSubHeaders qhs
			GROUP BY qhs.query_hash,
					qhs.sess__database_id
		) qhs
			ON qhs.query_hash = qhh.query_hash
			AND qhs.sess__database_id = qhh.sess__database_id;

	--Do the UTC->local translation
	UPDATE targ 
	SET FirstSeen = ct1.SPIDCaptureTime,
		LastSeen = ct2.SPIDCaptureTime
	FROM #QHHeaders targ 
		INNER JOIN #CaptureTimes ct1
			ON targ.FirstSeenUTC = ct1.UTCCaptureTime
		INNER JOIN #CaptureTimes ct2
			ON targ.LastSeenUTC = ct2.UTCCaptureTime;

	UPDATE targ 
	SET FirstSeen = ct1.SPIDCaptureTime,
		LastSeen = ct2.SPIDCaptureTime
	FROM #QHSubHeaders targ 
		INNER JOIN #CaptureTimes ct1
			ON targ.FirstSeenUTC = ct1.UTCCaptureTime
		INNER JOIN #CaptureTimes ct2
			ON targ.LastSeenUTC = ct2.UTCCaptureTime;
	/*******************************************************************************************************************************
											End of Query Hash data gathering section
	********************************************************************************************************************************/

	/********************************************************************************************************************************
						 OOOO    BBBB   JJJJJ       SSSS   TTTTT   MM   MM  TTTTT   SSSS 
						O    O   B   B    J        S         T     M M M M	  T    S     
						O    O   BBBB     J         SSSS     T     M  M  M	  T     SSSS 
						O    O   B   B    J             S    T     M     M	  T         S
						 OOOO    BBBB   JJ          SSSS     T     M     M	  T     SSSS 
	********************************************************************************************************************************/
	/*
		The Stmt section focuses on object SQL (@@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore.object_id is not null). The identifier here is PKSQLStmtStoreID, and
		for object SQL, should uniquely identify a statement inside of an object. (Same text in 2 different objects = 2 different IDs).
		We want to show queries that have run many times, and aggregate their stats. Like the Query Hash data, we want to potentially
		show sub-rows. However, unlike QH data, each subrow will be the same PKSQLStmtStoreID, but only different query plan IDs.
		If there is only 1 query plan for a given statement, then there will only be 1 sub-row. If query plans are not desired,
		then we don't show any sub-rows, just aggregated stats.
	*/
	--First, obtain a list of instances
	SET @lv__errorloc = N'Populate #ObjStmtInstances';
	INSERT INTO #ObjStmtInstances (
		--These are the identifying columns. The granularity of this table is the execution of an individual statement
		session_id,
		request_id,
		TimeIdentifier,
		StatementFirstCaptureUTC,

		StatementLastCaptureUTC,
		PreviousCaptureTimeUTC,
		sess__database_id,
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,
		NumCaptureRows
	)
	SELECT 
		session_id,
		request_id,
		TimeIdentifier,
		StatementFirstCaptureUTC,

		StatementLastCaptureUTC,
		PreviousCaptureTimeUTC,
		sess__database_id,
		PKSQLStmtStoreID,
		PKQueryPlanStmtStoreID,
		NumCaptureRows
	FROM (
		SELECT 
			--Each row signifies the execution of an individual statement
			ss.session_id,
			ss.request_id,
			ss.TimeIdentifier,
			ss.StatementFirstCaptureUTC,

			[StatementLastCaptureUTC] = MAX(ss.StatementLastCaptureUTC),--only 1 row should be non-null so we obtain that
			[PreviousCaptureTimeUTC] = MAX(ss.PreviousCaptureTimeUTC),		--ditto

			[sess__database_id] = MAX(sess__database_id),		--this orders a real DBID over the -1 that we have if it is NULL in SAR. This should be safe b/c
										--while Context DBID could change within a batch, it shouldn't change within a statement.
			[PKSQLStmtStoreID] = MAX(PKSQLStmtStoreID),
			[PKQueryPlanStmtStoreID] = MAX(PKQueryPlanStmtStoreID),
			[NumCaptureRows] = SUM(1)
		FROM (
			SELECT 
				sct.session_id,
				sct.request_id,
				sct.TimeIdentifier,
				sct.StatementFirstCaptureUTC,
				--We only capture 1 non-NULL value on these 2 fields so that we can apply MAX later to obtain it when we decrease granularity
				[StatementLastCaptureUTC] = CASE WHEN sct.IsStmtLastCapture = 1 OR sct.IsCurrentLastRowOfBatch = 1 
											THEN sct.UTCCaptureTime ELSE NULL END,
				[PreviousCaptureTimeUTC] = CASE WHEN sct.IsStmtFirstCapture = 1 THEN sct.PreviousCaptureTimeUTC ELSE NULL END,

				[sess__database_id] = CASE WHEN @context=N'Y' THEN ISNULL(sct.sess__database_id,-1) ELSE -1 END,

				[PKQueryPlanStmtStoreID] = CASE WHEN sct.IsStmtLastCapture = 1 OR sct.IsCurrentLastRowOfBatch = 1 
												THEN ISNULL(sct.PKQueryPlanStmtStoreID,-1)
												ELSE -1 END,

				sct.PKSQLStmtStoreID			--TODO: for now, this should be the same for all caps for the same statement. However, once we implement
												--TMR waits, that assumption may not be true anymore. May need to revisit.
			FROM @@CHIRHO_SCHEMA@@.AutoWho_StatementCaptureTimes sct
				LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore sss
					ON sct.PKSQLStmtStoreID = sss.PKSQLStmtStoreID
					AND sss.objectid <> @lv__nullint
			WHERE sct.StatementFirstCaptureUTC BETWEEN @EffectiveStartUTC AND @EffectiveEndUTC	
			--notice that we don't use UTCCaptureTime or SPIDCaptureTime here, because we don't want to grab partial
			--sets of rows for any statements.
		) ss
		GROUP BY ss.session_id,
			ss.request_id,
			ss.TimeIdentifier,
			ss.StatementFirstCaptureUTC
	) ss2;

	SET @lv__errorloc = N'Populate #ObjStmtSubHeaders';
	INSERT INTO #ObjStmtSubHeaders (
		PKSQLStmtStoreID,
		sess__database_id,
		PKQueryPlanStmtStoreID,

		UniqueOccurrences,
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder,

		cpu_time
	)
	SELECT 
		ss.PKSQLStmtStoreID,
		ss.sess__database_id,
		ss.PKQueryPlanStmtStoreID,

		ss.UniqueOccurrences,
		ss.NumCaptureRows,
		ss.FirstSeenUTC,
		ss.LastSeenUTC,
		[DisplayOrder] = ROW_NUMBER() OVER (PARTITION BY ss.PKSQLStmtStoreID, ss.sess__database_id ORDER BY ss.UniqueOccurrences DESC),
		ss.cpu_time
	FROM (
		SELECT 
			osi.PKSQLStmtStoreID,
			osi.sess__database_id,
			osi.PKQueryPlanStmtStoreID,
			[UniqueOccurrences] = SUM(1),	--the # of unique statement executions for a given StmtID/ContextDBID/PlanID 
			[NumCaptureRows] = SUM(osi.NumCaptureRows),
			FirstSeenUTC = MIN(osi.StatementFirstCaptureUTC),
			LastSeenUTC = MAX(osi.StatementLastCaptureUTC),
			[cpu_time] = SUM(sar.rqst__cpu_time - ISNULL(sarprev.rqst__cpu_time,0))
							/* Metrics still to do (I may not do all of them)

					SAR
						[calc__duration_ms]
						blocking info e.g. [calc__blocking_session_id] and [calc__is_blocker]
						rqst__status_code
						rqst__open_transaction_count
						rqst__reads
						rqst__writes
						rqst__logical_reads
						rqst__transaction_isolation_level
						rqst__row_count
						rqst__granted_query_memory
						tempdb__sess_user_objects_alloc_page_count
						tempdb__sess_user_objects_dealloc_page_count
						tempdb__sess_internal_objects_alloc_page_count
						tempdb__sess_internal_objects_dealloc_page_count
						tempdb__task_user_objects_alloc_page_count
						tempdb__task_user_objects_dealloc_page_count
						tempdb__task_internal_objects_alloc_page_count
						tempdb__task_internal_objects_dealloc_page_count
						tempdb__CalculatedNumberOfTasks
						mgrant__request_time	and   mgrant__grant_time		i.e. the avg delay here
						mgrant__requested_memory_kb
						mgrant__granted_memory_kb
						mgrant__used_memory_kb
						mgrant__max_used_memory_kb
						mgrant__dop

						Other stuff to consider:
								calc__tmr_wait
								Something like calc__node_info
								Something like calc__status_info

					TAW
						tstate
						context_switches_count
						FKDimWaitType
						wait_duration_ms

						Other stuff to consider:
							wait_special_category
							wait_special_number
							wait_special_tag
							resource_description
							resource_dbid
							resource_associatedobjid
							cxp_wait_direction
							resolution_successful
							resolved_name


					Tran Details
						calculated # of transactions
						oldest tran begin time (dtat_transaction_begin_time and/or dtdt_database_transaction_begin_time)
						number of DBs that the trans are in (dtdt_database_id)
						dtdt_database_transaction_log_record_count
						dtdt_database_transaction_log_bytes_used
						dtdt_database_transaction_log_bytes_reserved
						dtdt_database_transaction_log_bytes_used_system
						dtdt_database_transaction_log_bytes_reserved_system
						dtasdt_tran_exists
						dtasdt_elapsed_time_seconds
						dtasdt_max_version_chain_traversed
						dtasdt_average_version_chain_traversed

						Other stuff to consider:
							dtst_is_user_transaction
							dtat_dtc_state
							dtat_transaction_state
							dtat_transaction_type
							dtst_is_local
							dtdt_database_transaction_type
							dtdt_database_transaction_state


					Lock Details
						Avg number of locks? (RecordCount)
				*/
		FROM #ObjStmtInstances osi
			INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
				ON osi.session_id = sar.session_id
				AND osi.request_id = sar.request_id
				AND osi.TimeIdentifier = sar.TimeIdentifier
				AND osi.StatementLastCaptureUTC = sar.UTCCaptureTime
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sarprev
				ON osi.session_id = sarprev.session_id
				AND osi.request_id = sarprev.request_id
				AND osi.TimeIdentifier = sarprev.TimeIdentifier
				AND osi.PreviousCaptureTimeUTC = sarprev.UTCCaptureTime
		GROUP BY osi.PKSQLStmtStoreID,
			osi.sess__database_id,
			osi.PKQueryPlanStmtStoreID
	) ss;

	SET @lv__errorloc = N'Populate #ObjStmtHeaders';
	INSERT INTO #ObjStmtHeaders (
		PKSQLStmtStoreID,
		sess__database_id,
		UniqueOccurrences,
		NumCaptureRows,
		FirstSeenUTC,
		LastSeenUTC,
		DisplayOrder,
		cpu_time
	)
	SELECT 
		ss.PKSQLStmtStoreID,
		ss.sess__database_id,
		ss.UniqueOccurrences,
		ss.NumCaptureRows,
		ss.FirstSeenUTC,
		ss.LastSeenUTC,
		[DisplayOrder] = ROW_NUMBER() OVER (ORDER BY ss.UniqueOccurrences DESC),
		ss.cpu_time
	FROM (
		SELECT 
			osh.PKSQLStmtStoreID,
			osh.sess__database_id,
			[UniqueOccurrences] = SUM(1),				--the # of unique Query Plan IDs for a given StmtID/ContextDBID
			[NumCaptureRows] = SUM(osh.NumCaptureRows),
			[FirstSeenUTC] = MIN(osh.FirstSeenUTC),
			[LastSeenUTC] = MIN(osh.LastSeenUTC),
			[cpu_time] = SUM(osh.cpu_time)
		FROM #ObjStmtSubHeaders osh
		GROUP BY osh.PKSQLStmtStoreID,
			osh.sess__database_id
	) ss;

	--Do the UTC->local translation
	UPDATE targ 
	SET FirstSeen = ct1.SPIDCaptureTime,
		LastSeen = ct2.SPIDCaptureTime
	FROM #ObjStmtHeaders targ 
		INNER JOIN #CaptureTimes ct1
			ON targ.FirstSeenUTC = ct1.UTCCaptureTime
		INNER JOIN #CaptureTimes ct2
			ON targ.LastSeenUTC = ct2.UTCCaptureTime;

	UPDATE targ 
	SET FirstSeen = ct1.SPIDCaptureTime,
		LastSeen = ct2.SPIDCaptureTime
	FROM #ObjStmtSubHeaders targ 
		INNER JOIN #CaptureTimes ct1
			ON targ.FirstSeenUTC = ct1.UTCCaptureTime
		INNER JOIN #CaptureTimes ct2
			ON targ.LastSeenUTC = ct2.UTCCaptureTime;
	/*******************************************************************************************************************************
											End of Obj Stmt section
	********************************************************************************************************************************/

	/********************************************************************************************************************************
						RRRR    EEEEE    SSSS     OOOO    L    V       V   EEEEE
						R   R   E		S     	 O    O   L     V     V	   E	
						RRR     EEEEE	 SSSS 	 O    O   L      V   V	   EEEEE
						R  R    E		     S	 O    O   L       VVV	   E	
						R   R   EEEEE	 SSSS 	  OOOO    LLLLL    V	   EEEEE
	********************************************************************************************************************************/
	--Resolve the statement IDs to the actual statement text
	SET @lv__errorloc = N'Obtain Stmt Store raw';
	INSERT INTO #SQLStmtStore (
		PKSQLStmtStoreID,
		[sql_handle],
		statement_start_offset,
		statement_end_offset,
		[dbid],
		[objectid],
		datalen_batch,
		stmt_text
		--stmt_xml
		--dbname						NVARCHAR(128),
		--objname						NVARCHAR(128)
	)
	SELECT sss.PKSQLStmtStoreID, 
		sss.sql_handle,
		sss.statement_start_offset,
		sss.statement_end_offset,
		sss.dbid,
		sss.objectid,
		sss.datalen_batch,
		sss.stmt_text
	FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore sss
	WHERE sss.PKSQLStmtStoreID IN (
		SELECT qhs.PKSQLStmtStoreID
		FROM #QHSubHeaders qhs
		WHERE qhs.PKSQLStmtStoreID > 0

		UNION 

		SELECT osh.PKSQLStmtStoreID
		FROM #ObjStmtSubHeaders osh
		WHERE osh.PKSQLStmtStoreID > 0
		)
	;

	SET @lv__errorloc = N'Declare Stmt Store Cursor';
	DECLARE resolveSQLStmtStore CURSOR LOCAL FAST_FORWARD FOR
	SELECT 
		PKSQLStmtStoreID,
		[sql_handle],
		[dbid],
		[objectid],
		stmt_text
	FROM #SQLStmtStore sss
	;

	SET @lv__errorloc = N'Open Stmt Store Cursor';
	OPEN resolveSQLStmtStore;
	FETCH resolveSQLStmtStore INTO @PKSQLStmtStoreID,
		@sql_handle,
		@dbid,
		@objectid,
		@stmt_text
	;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @lv__errorloc = N'In Stmt Store loop';
		--Note that one major assumption of this procedure is that the DBID has not changed since the time the spid was 
		-- collected. For performance reasons, we don't resolve DBID in AutoWho.Collector; thus, if a DB is detached/re-attached,
		-- or deleted and the DBID is re-used by a completely different database, confusion can ensue.
		IF @dbid > 0
		BEGIN
			SET @dbname = DB_NAME(@dbid);
		END
		ELSE
		BEGIN
			SET @dbname = N'';
		END

		--Above note about DBID is relevant for this as well. 
		IF @objectid > 0
		BEGIN
			SET @objectname = OBJECT_NAME(@objectid,@dbid);
		END
		ELSE
		BEGIN
			SET @objectname = N'';
		END

		IF @objectid > 0
		BEGIN
			--if we do have a dbid/objectid pair, get the schema for the object
			IF @dbid > 0
			BEGIN
				SET @schname = OBJECT_SCHEMA_NAME(@objectid, @dbid);
			END
			ELSE
			BEGIN
				--if we don't have a valid dbid, we still do a "best effort" attempt to get schema
				SET @schname = OBJECT_SCHEMA_NAME(@objectid);
			END
			
			IF @schname IS NULL
			BEGIN
				SET @schname = N'';
			END
		END
		ELSE
		BEGIN
			SET @schname = N'';
		END

		IF @sql_handle = 0x0
		BEGIN
			SET @stmt_xml = CONVERT(XML, N'<?Stmt --' + NCHAR(10)+NCHAR(13) + N'sql_handle is 0x0. The current SQL statement cannot be displayed.' + NCHAR(10) + NCHAR(13) + 
			N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 
			NCHAR(10) + NCHAR(13) + N'-- ?>');
		END
		ELSE
		BEGIN
			IF @stmt_text IS NULL
			BEGIN
				SET @stmt_xml = CONVERT(XML, N'<?Stmt --' + NCHAR(10)+NCHAR(13) + N'The statement text is NULL. No T-SQL command to display.' + NCHAR(10) + NCHAR(13) + 
					N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
			END
			ELSE
			BEGIN
				BEGIN TRY
					SET @stmt_xml = CONVERT(XML, N'<?Stmt --' + NCHAR(10)+NCHAR(13) + @stmt_text + + NCHAR(10) + NCHAR(13) + 
					N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END TRY
				BEGIN CATCH
					SET @stmt_xml = CONVERT(XML, N'<?Stmt --' + NCHAR(10)+NCHAR(13) + N'Error CONVERTing text to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
					N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 

					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END CATCH
			END
		END

		UPDATE #SQLStmtStore
		SET dbname = @dbname,
			objname = @objectname,
			schname = @schname,
			stmt_xml = @stmt_xml
		WHERE PKSQLStmtStoreID = @PKSQLStmtStoreID;

		FETCH resolveSQLStmtStore INTO @PKSQLStmtStoreID,
			@sql_handle,
			@dbid,
			@objectid,
			@stmt_text
		;
	END	--WHILE loop for SQL Stmt Store cursor
		
	CLOSE resolveSQLStmtStore;
	DEALLOCATE resolveSQLStmtStore;

	--Resolve query plan identifiers to their actual XML
	IF @plan = N'y'
	BEGIN
		SET @lv__errorloc = N'Obtain query plan store raw';
		INSERT INTO #QueryPlanStmtStore (
			PKQueryPlanStmtStoreID,
			[plan_handle],
			--statement_start_offset,
			--statement_end_offset,
			--[dbid],
			--[objectid],
			[query_plan_text]
			--[query_plan_xml]
		)
		SELECT 
			qpss.PKQueryPlanStmtStoreID,
			qpss.plan_handle,
			qpss.query_plan
		FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore qpss
		WHERE qpss.PKQueryPlanStmtStoreID IN (
			SELECT qhs.PKQueryPlanStmtStoreID
			FROM #QHSubHeaders qhs
			WHERE qhs.PKQueryPlanStmtStoreID > 0

			UNION 

			SELECT osh.PKQueryPlanStmtStoreID
			FROM #ObjStmtSubHeaders osh
			WHERE osh.PKQueryPlanStmtStoreID > 0
		);

		SET @lv__errorloc = N'Declare query plan cursor';
		DECLARE resolveQueryPlanStmtStore CURSOR LOCAL FAST_FORWARD FOR 
		SELECT qpss.PKQueryPlanStmtStoreID,
			qpss.plan_handle,
			qpss.query_plan_text
		FROM #QueryPlanStmtStore qpss;

		SET @lv__errorloc = N'Open query plan cursor';
		OPEN resolveQueryPlanStmtStore;
		FETCH resolveQueryPlanStmtStore INTO @PKQueryPlanStmtStoreID,
			@plan_handle,
			@query_plan_text;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @lv__errorloc = N'In query plan loop';
			IF @plan_handle = 0x0
			BEGIN
				SET @query_plan_xml = CONVERT(XML, N'<?StmtPlan --' + NCHAR(10)+NCHAR(13) + N'plan_handle is 0x0. The Statement Query Plan cannot be displayed.' + NCHAR(10) + NCHAR(13) + 
				N'PKQueryPlanStmtStoreID: ' + CONVERT(NVARCHAR(20), ISNULL(@PKQueryPlanStmtStoreID,-1)) +
				NCHAR(10) + NCHAR(13) + N'-- ?>');
			END
			ELSE
			BEGIN
				IF @query_plan_text IS NULL
				BEGIN
					SET @query_plan_xml = CONVERT(XML, N'<?StmtPlan --' + NCHAR(10)+NCHAR(13) + N'The Statement Query Plan is NULL.' + NCHAR(10) + NCHAR(13) + 
					N'PKQueryPlanStmtStoreID: ' + CONVERT(NVARCHAR(20), ISNULL(@PKQueryPlanStmtStoreID,-1)) +
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END
				ELSE
				BEGIN
					BEGIN TRY
						SET @query_plan_xml = CONVERT(XML, @query_plan_text);
					END TRY
					BEGIN CATCH
						--Most common reason for this is the 128-node limit
						SET @query_plan_xml = CONVERT(XML, N'<?StmtPlan --' + NCHAR(10)+NCHAR(13) + N'Error CONVERTing Statement Query Plan to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
						N'PKQueryPlanStmtStoreID: ' + CONVERT(NVARCHAR(20), ISNULL(@PKQueryPlanStmtStoreID,-1)) +

						CASE WHEN ERROR_NUMBER() = 6335 AND @PKSQLStmtStoreID IS NOT NULL THEN 
							N'-- You can extract this query plan to a file with the below script
							--DROP TABLE dbo.largeQPbcpout
							SELECT query_plan
							INTO dbo.largeQPbcpout
							FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore q
							WHERE q.PKQueryPlanStmtStoreID = ' + CONVERT(NVARCHAR(20),@PKQueryPlanStmtStoreID) + N'
							--then from a command line:
							bcp dbo.largeQPbcpout out c:\largeqpxmlout.sqlplan -c -S. -T
							'
						ELSE N'' END + 

						NCHAR(10) + NCHAR(13) + N'-- ?>');
					END CATCH
				END
			END

			UPDATE #QueryPlanStmtStore
			SET query_plan_xml = @query_plan_xml
			WHERE PKQueryPlanStmtStoreID = @PKQueryPlanStmtStoreID;

			FETCH resolveQueryPlanStmtStore INTO @PKQueryPlanStmtStoreID,
				@plan_handle,
				@query_plan_text;
		END

		CLOSE resolveQueryPlanStmtStore;
		DEALLOCATE resolveQueryPlanStmtStore;
	END
	/*******************************************************************************************************************************
											End of Resolve Stmt and Plan IDs
	********************************************************************************************************************************/


	/********************************************************************************************************************************
						PPPP    RRRR    EEEEE    SSSS    EEEEE    N   N   TTTTT
						P   P   R   R   E		S     	 E		  NN  N     T  
						PPPP    RRR     EEEEE	 SSSS 	 EEEEE	  N N N     T  
						P	    R  R    E		     S	 E		  N  NN     T  
						P	    R   R   EEEEE	 SSSS 	 EEEEE	  N   N     T  
	********************************************************************************************************************************/
	--Query Hash dynamic SQL
	SET @lv__errorloc = N'Construct QH dyn SQL';
	SET @lv__DynSQL = N'
	SELECT ' + 
		CASE WHEN @context = N'N' THEN N'' ELSE N'
		[CntxtDB] = CASE WHEN ss.SubHeaderDisplayOrder = 0 THEN DB_NAME(ss.sess__database_id) ELSE N'''' END,' END + N'
		[StmtID] = CASE WHEN ss.SubHeaderDisplayOrder = 0 THEN N'''' ELSE CONVERT(VARCHAR(20),ss.PKSQLStmtStoreID) END,
		ss.StmtText,
		[PlanID] = CASE WHEN ss.SubHeaderDisplayOrder = 0 THEN N'''' ELSE CONVERT(VARCHAR(20),ss.PKQueryPlanStmtStoreID) END,
		ss.QPlan,
		[Uniq] = ss.UniqueOccurrences,
		[#Caps] = ss.NumCaptureRows,
		ss.FirstSeen,
		ss.LastSeen,
		ss.cpu_time
	FROM (
		SELECT 
			HeaderDisplayOrder = qhh.DisplayOrder,
			SubHeaderDisplayOrder = 0,
			qhh.sess__database_id,
			[PKSQLStmtStoreID] = -1,
			[StmtText] = N''Query Hash: 0x'' + CONVERT(VARCHAR(40),qhh.query_hash,2),
			[PKQueryPlanStmtStoreID] = -1,
			[QPlan] = N'''',
			qhh.UniqueOccurrences,
			qhh.NumCaptureRows,
			qhh.FirstSeen,
			qhh.LastSeen,
			qhh.cpu_time
		FROM #QHHeaders qhh

		UNION ALL 

		SELECT 
			HeaderDisplayOrder = qhh.DisplayOrder,
			SubHeaderDisplayOrder = qhs.DisplayOrder,
			qhs.sess__database_id,
			qhs.PKSQLStmtStoreID,
			[StmtText] = sss.stmt_xml,
			qhs.PKQueryPlanStmtStoreID,
			[QPlan] = qpss.query_plan_xml,
			qhs.UniqueOccurrences,
			qhs.NumCaptureRows,
			qhs.FirstSeen,
			qhs.LastSeen,
			qhs.cpu_time
		FROM #QHHeaders qhh
			INNER JOIN #QHSubHeaders qhs
				ON qhh.query_hash = qhs.query_hash
				AND qhh.sess__database_id = qhs.sess__database_id
			LEFT OUTER JOIN #SQLStmtStore sss
				ON qhs.PKSQLStmtStoreID = sss.PKSQLStmtStoreID
			LEFT OUTER JOIN #QueryPlanStmtStore qpss
				ON qhs.PKQueryPlanStmtStoreID = qpss.PKQueryPlanStmtStoreID
	) ss
	ORDER BY ss.HeaderDisplayOrder, ss.SubHeaderDisplayOrder;
	';
	SET @lv__errorloc = N'Execute QH dyn sql';
	EXEC sp_executesql @stmt=@lv__DynSQL;


	--Object Stmt dynamic sql
	SET @lv__errorloc = N'Construct ObjStmt dyn sql';
	SET @lv__DynSQL = N'
	SELECT ' + 
		CASE WHEN @context = N'N' THEN N'' ELSE N'
		[CntxtDB] = CASE WHEN ss.SubHeaderDisplayOrder = 0 THEN DB_NAME(ss.sess__database_id) ELSE N'''' END,' END + N'
		[StmtID] = CASE WHEN ss.SubHeaderDisplayOrder <> 0 THEN N'''' ELSE CONVERT(VARCHAR(20),ss.PKSQLStmtStoreID) END,
		ss.StmtOrPlan,
		[Uniq] = ss.UniqueOccurrences,
		[#Caps] = ss.NumCaptureRows,
		ss.FirstSeen,
		ss.LastSeen,
		ss.cpu_time
	FROM (
		SELECT 
			HeaderDisplayOrder = osh.DisplayOrder,
			SubHeaderDisplayOrder = 0,
			osh.sess__database_id,
			osh.PKSQLStmtStoreID,
			[StmtOrPlan] = sss.stmt_xml,
			osh.UniqueOccurrences,
			osh.NumCaptureRows,
			osh.FirstSeen,
			osh.LastSeen,
			osh.cpu_time
		FROM #ObjStmtHeaders osh
			LEFT OUTER JOIN #SQLStmtStore sss
				ON osh.PKSQLStmtStoreID = sss.PKSQLStmtStoreID

		UNION ALL 

		SELECT HeaderDisplayOrder = osh.DisplayOrder,
			SubHeaderDisplayOrder = ossh.DisplayOrder,
			osh.sess__database_id,
			osh.PKSQLStmtStoreID,
			[StmtOrPlan] = CASE WHEN ossh.PKQueryPlanStmtStoreID = -1 THEN CONVERT(XML,''No query plan obtained'')
				WHEN qpss.query_plan_xml IS NULL THEN CONVERT(XML,''Null plan obtained'') 
				ELSE qpss.query_plan_xml END,
			ossh.UniqueOccurrences,
			ossh.NumCaptureRows,
			ossh.FirstSeen,
			ossh.LastSeen,
			ossh.cpu_time
		FROM #ObjStmtHeaders osh
			INNER JOIN #ObjStmtSubHeaders ossh
				ON osh.PKSQLStmtStoreID = ossh.PKSQLStmtStoreID
				AND osh.sess__database_id = ossh.sess__database_id
			LEFT OUTER JOIN #QueryPlanStmtStore qpss
				ON ossh.PKQueryPlanStmtStoreID = qpss.PKQueryPlanStmtStoreID
	) ss
	ORDER BY ss.HeaderDisplayOrder, ss.SubHeaderDisplayOrder;
	';
	SET @lv__errorloc = N'Execute ObjStmt dyn sql';
	EXEC sp_executesql @stmt=@lv__DynSQL;
	

	--Input Buffer dynamic SQL
	SET @lv__errorloc = N'Construct IB dyn sql';
	SET @lv__DynSQL_base = N'
		SELECT 
			ibh.PKInputBufferStoreID,
			ibh.sess__database_id,
			ibs.inputbuffer_xml,
			ibh.UniqueOccurrences,
			ibh.NumCaptureRows,
			ibh.FirstSeen,
			ibh.LastSeen,
			ibh.DisplayOrder,

			ib.MinIdleDuration_ms,
			ib.MaxIdleDuration_ms,
			ib.AvgIdleDuration_ms,

			ib.MinTempDBAlloc_pages,
			ib.MaxTempDBAlloc_pages,
			ib.AvgTempDBAlloc_pages,

			ib.MinTempDBUsed_pages,
			ib.MaxTempDBUsed_pages,
			ib.AvgTempDBUsed_pages,

			ib.MinTranCount,
			ib.MaxTranCount,
			ib.AvgTranCount,

			ib.MinLongestTranLength_ms,
			ib.MaxLongestTranLength_ms,
			ib.AvgLongestTranLength_ms,

			ib.MinLogReserved_bytes,
			ib.MaxLogReserved_bytes,
			ib.AvgLogReserved_bytes,

			ib.MinLogUsed_bytes,
			ib.MaxLogUsed_bytes,
			ib.AvgLogUsed_bytes,

			ib.MinNumLogRecords,
			ib.MaxNumLogRecords,
			ib.AvgNumLogRecords,

			ib.MinPhysReads_pages,
			ib.MaxPhysReads_pages,
			ib.AvgPhysReads_pages,

			ib.MinLogicReads_pages,
			ib.MaxLogicReads_pages,
			ib.AvgLogicReads_pages,

			ib.MinWrites_pages,
			ib.MaxWrites_pages,
			ib.AvgWrites_pages
		FROM #IBHeaders ibh
			INNER JOIN #InputBufferStore ibs
				ON ibh.PKInputBufferStoreID = ibs.PKInputBufferStoreID
			INNER JOIN (
				SELECT 
					PKInputBufferStoreID,
					sess__database_id,

					MinCPUTime_ms = MIN(sess__cpu_time),
					MaxCPUTime_ms = MAX(sess__cpu_time),
					AvgCPUTime_ms = AVG(sess__cpu_time),

					MinPhysReads_pages = MIN(sess__reads),
					MaxPhysReads_pages = MAX(sess__reads),
					AvgPhysReads_pages = AVG(sess__reads),

					MinLogicReads_pages = MIN(sess__logical_reads),
					MaxLogicReads_pages = MAX(sess__logical_reads),
					AvgLogicReads_pages = AVG(sess__logical_reads),

					MinWrites_pages = MIN(sess__writes),
					MaxWrites_pages = MAX(sess__writes),
					AvgWrites_pages = AVG(sess__writes),

					MinTranCount = MIN(sess__open_transaction_count),
					MaxTranCount = MAX(sess__open_transaction_count),
					AvgTranCount = AVG(sess__open_transaction_count),

					MinIdleDuration_ms = MIN(calc__duration_ms),
					MaxIdleDuration_ms = MAX(calc__duration_ms),
					AvgIdleDuration_ms = AVG(calc__duration_ms),

					MinTempDBAlloc_pages = MIN(TempDBAlloc_pages),
					MaxTempDBAlloc_pages = MAX(TempDBAlloc_pages),
					AvgTempDBAlloc_pages = AVG(TempDBAlloc_pages),

					MinTempDBUsed_pages = MIN(TempDBUsed_pages),
					MaxTempDBUsed_pages = MAX(TempDBUsed_pages),
					AvgTempDBUsed_pages = AVG(TempDBUsed_pages),

					MinLongestTranLength_ms = MIN(LongestTranLength_ms),
					MaxLongestTranLength_ms = MAX(LongestTranLength_ms),
					AvgLongestTranLength_ms = AVG(LongestTranLength_ms),

					MinNumLogRecords = MIN(NumLogRecords),
					MaxNumLogRecords = MAX(NumLogRecords),
					AvgNumLogRecords = AVG(NumLogRecords),

					MinLogUsed_bytes = MIN(LogUsed_bytes),
					MaxLogUsed_bytes = MAX(LogUsed_bytes),
					AvgLogUsed_bytes = AVG(LogUsed_bytes),

					MinLogReserved_bytes = MIN(LogReserved_bytes),
					MaxLogReserved_bytes = MAX(LogReserved_bytes),
					AvgLogReserved_bytes = AVG(LogReserved_bytes)
				FROM #IBRawStats ib
				GROUP BY PKInputBufferStoreID, sess__database_id
			) ib
				ON ib.PKInputBufferStoreID = ibh.PKInputBufferStoreID
	';

	SET @lv__DynSQL = N'
	SELECT 
		[ContextDB] = ib_base.sess__database_id,
		[IBuf] = ib_base.inputbuffer_xml,
		[#UniqSeen] = ib_base.UniqueOccurrences,
		[TotalTimesSeen] = ib_base.NumCaptureRows,
		[FirstSeen] = ib_base.FirstSeen,
		[LastSeen] = ib_base.LastSeen,
		[IdleDur (Min)] = ib_base.MinIdleDuration_ms,
		[(Max)] = ib_base.MaxIdleDuration_ms,
		[(Avg)] = ib_base.AvgIdleDuration_ms,
		[TDB Alloc (Min)] = ib_base.MinTempDBAlloc_pages,
		[(Max)] = ib_base.MaxTempDBAlloc_pages,
		[(Avg)] = ib_base.AvgTempDBAlloc_pages,
		[TDB Used (Min)] = ib_base.MinTempDBUsed_pages,
		[(Max)] = ib_base.MaxTempDBUsed_pages,
		[(Avg)] = ib_base.AvgTempDBUsed_pages,
		[TranCount (Min)] = ib_base.MinTranCount,
		[(Max)] = ib_base.MaxTranCount,
		[(Avg)] = ib_base.AvgTranCount,
		[TranLength (Min)] = ib_base.MinLongestTranLength_ms,
		[(Max)] = ib_base.MaxLongestTranLength_ms,
		[(Avg)] = ib_base.AvgLongestTranLength_ms,
		[LogRsvd (Min)] = ib_base.MinLogReserved_bytes,
		[(Max)] = ib_base.MaxLogReserved_bytes,
		[(Avg)] = ib_base.AvgLogReserved_bytes,
		[LogUsed (Min)] = ib_base.MinLogUsed_bytes,
		[(Max)] = ib_base.MaxLogUsed_bytes,
		[(Avg)] = ib_base.AvgLogUsed_bytes,
		[PhysReads (Min)] = ib_base.MinPhysReads_pages,
		[(Max)] = ib_base.MaxPhysReads_pages,
		[(Avg)] = ib_base.AvgPhysReads_pages,
		[LogicReads (Min)] = ib_base.MinLogicReads_pages,
		[(Max)] = ib_base.MaxLogicReads_pages,
		[(Avg)] = ib_base.AvgLogicReads_pages,
		[Writes (Min)] = ib_base.MinWrites_pages,
		[(Max)] = ib_base.MaxWrites_pages,
		[(Avg)] = ib_base.AvgWrites_pages
	FROM (
	' + @lv__DynSQL_base + '
		) ib_base
	ORDER BY DisplayOrder;
	';
	SET @lv__errorloc = N'Execute IB dyn SQL';
	EXEC sp_executesql @stmt=@lv__DynSQL;



END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	SET @lv__errsev = ERROR_SEVERITY();
	SET @lv__errstate = ERROR_STATE();

	IF @lv__errorloc IN (N'Exec first dyn sql')
	BEGIN
		PRINT @lv__DynSQL;
	END

	SET @lv__msg = N'Exception occurred at location ("' + @lv__errorloc + N'"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
		N'; Severity: ' + CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + 
		N'; Msg: ' + ERROR_MESSAGE();

	RAISERROR(@lv__msg, @lv__errsev, @lv__errstate);
	RETURN -1;

END CATCH

	RETURN 0;
END