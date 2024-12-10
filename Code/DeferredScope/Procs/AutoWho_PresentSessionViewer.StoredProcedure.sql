SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_PresentSessionViewer
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

	FILE NAME: AutoWho_PresentSessionViewer.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_PresentSessionViewer

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Called by the sp_XR_SessionViewer user-facing procedure when historical/AutoWho data is requested. 
		The logic below pulls data from the various AutoWho tables, based on parameter values, and combines
		and formats the data as appropriate. 


	FUTURE ENHANCEMENTS: 
		- make display for Waits3 (lock details) faster via XML trickery

		- Evaluate various performance tricks like query hints, join order, KEEPFIXED PLAN, etc. 

		- Give the option to show things in pages versus MB?

		- give the option to order by the various return columns (how badly do I need this now?)
			what is the order for the "Progress" column?

		- If the "self" spid is captured in AutoWho.Collector, there is not a way to identify it in the data.
			Thus, even if we added a "show self" option in this historical view, we would not know which spid
			to exclude. The way to solve this is probably to add a calc__is_self flag to the SAR table, default
			AutoWho to be capture self by default, and then configure the viewer to exclude it by default unless
			it was block-relevant.

		-- Consider whether to add the LSN-related fields to the tran-related display info.

To Execute
------------------------
Should not be called by programs or used regularly. Only call when debugging.

EXEC @@CHIRHO_SCHEMA@@.AutoWho_PresentSessionViewer @htcUTC='2016-04-25 16:12', @hct='2016-04-25 08:12',
	@dur=0, @db=N'', @xdb=N'', @spid=N'', @xspid=N'', @blockonly=N'N',
	@attr=N'N', @resource=N'N', @batch=N'N', @plan=N'none',		-- 'statement', 'full'
	@ibuf=N'N', @bchain=0, @tran=N'N', @waits=0		--0, 1, 2, or 3

*/
(
	@init				TINYINT,				-- CollectionInitiatorID (which method the data was collected)
	@currentmode		BIT,					--0 or 1
	@hctUTC				DATETIME,				-- cannot be NULL
	@hct				DATETIME,				-- cannot be NULL

	--filters:
	@activity			TINYINT=1,				-- 0 = Running only, 1 = Active + idle-open-tran, 2 = everything
	@dur				INT=0,					-- duration, milliseconds
	@db					NVARCHAR(512)=N'',		-- spids with context database names in this list will be included, all others excluded
	@xdb				NVARCHAR(512)=N'',		-- spids with context database names in this list will be excluded
	@spid				NVARCHAR(100)=N'',		-- spid #'s in this list will be included, all others excluded
	@xspid				NVARCHAR(100)=N'',		-- spid #'s in this list will be excluded
	@blockonly			NCHAR(1)=N'N',			-- if "Y", only show spids that are blockers or blocking

	--options
	@attr				NCHAR(1)=N'N',			-- include extra columns relevant to various system, connection, and login information
	@resource			NCHAR(1)=N'N',			-- include extra columns relevant to system resource usage by the spid/request
	@batch				NCHAR(1)=N'N',			-- whether to include the full text of the SQL batch (not just statement); only possible if AutoWho captured the batch
	@plan				NVARCHAR(20)=N'none',	-- 'none', 'statement', 'full'
	@ibuf				NCHAR(1)=N'N',			-- display the input buffer for spids. Only possible for those spids where AutoWho captured the input buffer
	@bchain				TINYINT=0,				-- 0 through 10
	@tran				NCHAR(1)=N'N',			-- include an extra column with information about transactions held open by this spid
	@waits				TINYINT=0,				-- 0, 1, 2, or 3

	@savespace			NCHAR(1)=N'N',			-- adjusts the formatting of various columns to reduce horizontal length, thus making the display more compressed so that
												-- more information fits in one screen.
	@effectiveordinal	INT,					-- presents the @offset (parameter to sp_XR_SessionViewer) value to the user to let them know which offset they are at in the time range they chose.
	@dir				NVARCHAR(512)			-- misc directives
)
AS
BEGIN
	SET NOCOUNT ON;
	SET ANSI_PADDING ON;

	DECLARE 
		--misc
		@lv__scratchint				INT,
		@lv__msg					NVARCHAR(MAX),
		@lv__nullstring				NVARCHAR(8),
		@lv__nullint				INT,
		@lv__nullsmallint			SMALLINT,

		--auxiliary options 
		@lv__IncludeSessConnAttr	BIT,
		@lv__BChainAvailable		BIT,
		@lv__LockDetailsAvailable	BIT,
		@lv__TranDetailsAvailable	BIT,
		@lv__IncludeBChain			BIT,
		@lv__IncludeLockDetails		BIT,
		@lv__IncludeTranDetails		BIT,
		@lv__BChainString			NVARCHAR(MAX),
		@lv__LockString				NVARCHAR(MAX),

		--wait-type enum values
		@enum__waitspecial__none			TINYINT,
		@enum__waitspecial__lck				TINYINT,
		@enum__waitspecial__pgblocked		TINYINT,
		@enum__waitspecial__pgio			TINYINT,
		@enum__waitspecial__pg				TINYINT,
		@enum__waitspecial__latchblocked	TINYINT,
		@enum__waitspecial__latch			TINYINT,
		@enum__waitspecial__cxp				TINYINT,
		@enum__waitspecial__other			TINYINT,

		--Dynamic SQL variables
		@lv__DummyRow				NVARCHAR(MAX),
		@lv__BaseSELECT1			NVARCHAR(MAX),
		@lv__BaseSELECT2			NVARCHAR(MAX),
		@lv__BaseFROM				NVARCHAR(MAX),
		@lv__Formatted				NVARCHAR(MAX),
		@lv__ResultDynSQL			NVARCHAR(MAX)
		;

	--Cursor variables
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

		--batch store
		@PKSQLBatchStoreID			BIGINT,
		@batch_text					NVARCHAR(MAX),
		@batch_xml					XML,

		--input buffer store
		@PKInputBufferStore			BIGINT,
		@ibuf_text					NVARCHAR(4000),
		@ibuf_xml					XML,

		--QueryPlan Stmt/Batch store
		@PKQueryPlanStmtStoreID		BIGINT,
		@PKQueryPlanBatchStoreID	BIGINT,
		@plan_handle				VARBINARY(64),
		@query_plan_text			NVARCHAR(MAX),
		@query_plan_xml				XML
		;

	--initial values/enum population:

	SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" would collide with a DMV value
	SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
	SET @lv__nullsmallint = -929;			-- overlapping with some special system value

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

	/*
		Our final result set's top row indicates whether the BGraph, LockDetails, and TranDetails data was collected at this @hctUTC, so that
		the user knows whether inspecting that data is even an option. 
	
		For historical runs, we can just use the simple 1/0 flags that are stored in @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary by the 
		@@CHIRHO_SCHEMA@@.AutoWho_PopulateCaptureSummary procedure (which looks at the base data in the AutoWho tables to determine these bit flag values). 
		Thus, pull those values.

		For current runs, @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary doesn't have any data in it, so we can't check it to see if bchain data was
		just captured by the Collector. We need to use a different method. For current mode, we check the base tables
		directly
	*/
	IF @currentmode = 1
	BEGIN
		SELECT 
			@lv__BChainAvailable = CASE WHEN b.UTCCaptureTime IS NULL THEN 0 ELSE 1 END,
			@lv__LockDetailsAvailable = CASE WHEN l.UTCCaptureTime IS NULL THEN 0 ELSE 1 END,
			@lv__TranDetailsAvailable = CASE WHEN tr.UTCCaptureTime IS NULL THEN 0 ELSE 1 END
		FROM (SELECT 1 as col1) t
			OUTER APPLY (
				SELECT TOP 1 b.UTCCaptureTime
				FROM @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs b
				WHERE b.CollectionInitiatorID = @init
				AND b.UTCCaptureTime = @hctUTC
			) b
			OUTER APPLY (
				SELECT TOP 1 l.UTCCaptureTime
				FROM @@CHIRHO_SCHEMA@@.AutoWho_LockDetails l
				WHERE l.CollectionInitiatorID = @init
				AND l.UTCCaptureTime = @hctUTC
			) l
			OUTER APPLY (
				SELECT TOP 1 t.UTCCaptureTime
				FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails t
				WHERE t.CollectionInitiatorID = @init
				AND t.UTCCaptureTime = @hctUTC
			) tr
	END
	ELSE
	BEGIN
		--Regardless of the Collection Initiator ID that we're pulling, its profile should
		-- be in CaptureSummary
		SELECT 
			@lv__BChainAvailable = ISNULL(BlockingGraph,0),
			@lv__LockDetailsAvailable = ISNULL(LockDetails,0),
			@lv__TranDetailsAvailable = ISNULL(TranDetails,0)
		FROM (SELECT 1 as col1) t
			OUTER APPLY (
				SELECT 
					BlockingGraph,
					LockDetails,
					TranDetails
				FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary cs
				WHERE cs.UTCCaptureTime = @hctUTC
				AND cs.CollectionInitiatorID = @init
			) xapp1;
	END

	--If the user has requested any of these 3 options, include them. Otherwise, we'll merely indicate that they are viewable
	IF @bchain > 0 AND @lv__BChainAvailable = 1
	BEGIN
		SET @lv__IncludeBChain = 1;
	END
	ELSE
	BEGIN
		SET @lv__IncludeBChain = 0;
	END

	IF @waits = 3 AND @lv__LockDetailsAvailable = 1
	BEGIN
		SET @lv__IncludeLockDetails = 1;
	END
	ELSE
	BEGIN
		SET @lv__IncludeLockDetails = 0;
	END

	IF @tran = N'Y' AND @lv__TranDetailsAvailable = 1
	BEGIN
		SET @lv__IncludeTranDetails = 1;
	END
	ELSE
	BEGIN
		SET @lv__IncludeTranDetails = 0;
	END

	--Calculate what DB/SPID inclusion/exclusions the user has asked for,
	-- and create a filtering table that will be used in the joins below.
	DECLARE @DBInclusionsExist	BIT, 
		@DBExclusionsExist BIT,
		@SPIDInclusionsExist BIT,
		@SPIDExclusionsExist BIT;

	CREATE TABLE #FilterTab
	(
		FilterType TINYINT NOT NULL, 
			--0 DB inclusion
			--1 DB exclusion
			--2 SPID inclusion
			--3 SPID exclusion
		FilterID INT NOT NULL, 
		FilterName NVARCHAR(255)
	);

	
	IF ISNULL(@db,N'') = N''
	BEGIN
		SET @DBInclusionsExist = 0;		--this flag (only for inclusions) is a perf optimization
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO #FilterTab (FilterType, FilterID, FilterName)
				SELECT 0, d.database_id, d.name
				FROM (SELECT [dbnames] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @db,  N',' , N'</M><M>') + N'</M>' AS XML) AS dblist) xmlparse
					CROSS APPLY dblist.nodes(N'/M') Split(a)
					) SS
					INNER JOIN sys.databases d			--we need the join to sys.databases so that we can get the correct case for the DB name.
						ON LOWER(SS.dbnames) = LOWER(d.name)	--the user may have passed in a db name that doesn't match the case for the DB name in the catalog,
				WHERE SS.dbnames <> N'';						-- and on a server with case-sensitive collation, we need to make sure we get the DB name exactly right

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @DBInclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @DBInclusionsExist = 1;
			END
		END TRY
		BEGIN CATCH
			SET @lv__msg = N'Error occurred when attempting to convert the @dbs parameter (comma-separated list of database names) to a table of valid DB names. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			RAISERROR(@lv__msg, 16, 1);
			RETURN -1;
		END CATCH
	END		--db inclusion string parsing


	
	IF ISNULL(@xdb, N'') = N''
	BEGIN
		SET @DBExclusionsExist = 0;
	END
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO #FilterTab (FilterType, FilterID, FilterName)
				SELECT 1, d.database_id, d.name
				FROM (SELECT [dbnames] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @xdb,  N',' , N'</M><M>') + N'</M>' AS XML) AS dblist) xmlparse
					CROSS APPLY dblist.nodes(N'/M') Split(a)
					) SS
					INNER JOIN sys.databases d			--we need the join to sys.databases so that we can get the correct case for the DB name.
						ON LOWER(SS.dbnames) = LOWER(d.name)	--the user may have passed in a db name that doesn't match the case for the DB name in the catalog,
				WHERE SS.dbnames <> N'';						-- and on a server with case-sensitive collation, we need to make sure we get the DB name exactly right

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @DBExclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @DBExclusionsExist = 1;
			END
		END TRY
		BEGIN CATCH
			SET @lv__msg = N'Error occurred when attempting to convert the @xdbs parameter (comma-separated list of database names) to a table of valid DB names. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			RAISERROR(@lv__msg, 16, 1);
			RETURN -1;
		END CATCH
	END		--db exclusion string parsing


	IF ISNULL(@spid,N'') = N''
	BEGIN
		SET @SPIDInclusionsExist = 0;		--this flag (only for inclusions) is a perf optimization
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO #FilterTab (FilterType, FilterID, FilterName)
				SELECT 2, SS.spids, NULL
				FROM (SELECT [spids] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @spid,  N',' , N'</M><M>') + N'</M>' AS XML) AS spidlist) xmlparse
					CROSS APPLY spidlist.nodes(N'/M') Split(a)
					) SS
				WHERE SS.spids <> N'';

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @SPIDInclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @SPIDInclusionsExist = 1;
			END
		END TRY
		BEGIN CATCH
			SET @lv__msg = N'Error occurred when attempting to convert the @spid parameter (comma-separated list of session IDs) to a table of valid integer values. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			RAISERROR(@lv__msg, 16, 1);
			RETURN -1;
		END CATCH
	END		--spid inclusion string parsing


	IF ISNULL(@xspid,N'') = N''
	BEGIN
		SET @SPIDExclusionsExist = 0;
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO #FilterTab (FilterType, FilterID, FilterName)
				SELECT 3, SS.spids, NULL
				FROM (SELECT [spids] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @xspid,  N',' , N'</M><M>') + N'</M>' AS XML) AS spidlist) xmlparse
					CROSS APPLY spidlist.nodes(N'/M') Split(a)
					) SS
				WHERE SS.spids <> N'';

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @SPIDExclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @SPIDExclusionsExist = 1;
			END
		END TRY
		BEGIN CATCH
			SET @lv__msg = N'Error occurred when attempting to convert the @xspid parameter (comma-separated list of session IDs) to a table of valid integer values. Error #: ' +  
				CONVERT(NVARCHAR(20), ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + N'; Severity: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + '; Message: ' + 
				ERROR_MESSAGE();

			RAISERROR(@lv__msg, 16, 1);
			RETURN -1;
		END CATCH
	END		--spid exclusion string parsing

	IF EXISTS (SELECT * FROM #FilterTab dbs 
					INNER JOIN #FilterTab xdbs
						ON dbs.FilterID = xdbs.FilterID
						AND dbs.FilterType = 0
						AND xdbs.FilterType = 1
			)
	BEGIN
		RAISERROR('A database cannot be specified in both the @dbs and @xdbs filter parameters.', 16, 1);
		RETURN -1;
	END

	IF EXISTS (SELECT * FROM #FilterTab spid 
					INNER JOIN #FilterTab xspid
						ON spid.FilterID = xspid.FilterID
						AND spid.FilterType = 2
						AND xspid.FilterType = 3
			)
	BEGIN
		RAISERROR('A session ID cannot be specified in both the @spids and @xspids filter parameters.', 16, 1);
		RETURN -1;
	END

	CREATE TABLE #DistinctFKs (
		FKSQLStmtStoreID		BIGINT,
		FKSQLBatchStoreID		BIGINT,
		FKInputBufferStoreID	BIGINT,
		FKQueryPlanBatchStoreID	BIGINT,
		FKQueryPlanStmtStoreID	BIGINT
	);

	--The store tables hold dbid/objectid info, but we want to display DBName and ObjectName info.
	-- There is also the possibility that conversion to XML will fail, so we don't want to wait until the final join.
	-- This temp table is our workspace for that resolution/conversion work.
	CREATE TABLE #SQLStmtStore (
		PKSQLStmtStoreID			BIGINT NOT NULL,
		[sql_handle]				VARBINARY(64) NOT NULL,
		statement_start_offset		INT NOT NULL,
		statement_end_offset		INT NOT NULL, 
		[dbid]						SMALLINT NOT NULL,
		[objectid]					INT NOT NULL,
		datalen_batch				INT NOT NULL,
		stmt_text					NVARCHAR(MAX) NOT NULL,
		stmt_xml					XML,
		dbname						NVARCHAR(128),
		schname						NVARCHAR(128),
		objname						NVARCHAR(128)
	);

	CREATE TABLE #SQLBatchStore (
		PKSQLBatchStoreID			BIGINT NOT NULL,
		[sql_handle]				VARBINARY(64) NOT NULL, 
		--[dbid]						SMALLINT NOT NULL,
		--[objectid]					INT NOT NULL,
		batch_text					NVARCHAR(MAX),
		batch_xml					XML
		--dbname						NVARCHAR(128),
		--schname						NVARCHAR(128),
		--objname						NVARCHAR(128)
	);

	--Ditto, input buffer conversions to XML can fail.
	CREATE TABLE #InputBufferStore (
		PKInputBufferStoreID		BIGINT NOT NULL,
		inputbuffer					NVARCHAR(4000) NOT NULL,
		inputbuffer_xml				XML
	);

	--Ditto, QP conversions to XML can fail.
	CREATE TABLE #QueryPlanStmtStore (
		PKQueryPlanStmtStoreID		BIGINT NOT NULL,
		[plan_handle]				VARBINARY(64) NOT NULL,
		--statement_start_offset		INT NOT NULL,
		--statement_end_offset		INT NOT NULL,
		--[dbid]						SMALLINT NOT NULL,
		--[objectid]					INT NOT NULL,
		[query_plan_text]			NVARCHAR(MAX) NOT NULL,
		[query_plan_xml]			XML
	);

	CREATE TABLE #QueryPlanBatchStore (
		PKQueryPlanBatchStoreID		BIGINT NOT NULL, 
		[plan_handle]				VARBINARY(64) NOT NULL,
		--[dbid]						SMALLINT NOT NULL,
		--[objectid]					INT NOT NULL,
		[query_plan_text]			NVARCHAR(MAX) NOT NULL,
		[query_plan_xml]			XML
	);

	CREATE TABLE #BchainConverted (
		bchain_xml					XML
	);

	CREATE TABLE #LockDetailsConverted (
		lockdetails_xml				XML
	);

	CREATE TABLE #TranDetails (
		session_id					INT,
		tran__tlog_rsvd_bytes		BIGINT,
		tran__info					NVARCHAR(MAX)
	);

	--Our very top row holds some info about the collection that occurred at @hctUTC time. We place that in the Cmd XML return column since
	-- the contents can be quite large (e.g. if the "queries" directive is specified)
	CREATE TABLE #CapTimeCmdText (
		captimecmd_xml				XML
	);

	IF @lv__BChainAvailable = 0 AND @lv__LockDetailsAvailable = 0 AND @lv__TranDetailsAvailable = 0
		AND @dir NOT LIKE '%quer%'
	BEGIN
		--None of the content we plan to include in the top row's "Cmd" XML has been requested or is available. Return an empty value.
		INSERT INTO #CapTimeCmdText (captimecmd_xml)
		SELECT N'';
	END
	ELSE
	BEGIN
		IF @dir NOT LIKE '%quer%'
		BEGIN
			--Show the user whether Blocking Chain data, Transaction data, or locks-held data is even available.
			INSERT INTO #CapTimeCmdText (captimecmd_xml)
			SELECT convert(xml,N'<?opt --' + NCHAR(10) +
						CASE WHEN @lv__BChainAvailable = 1 THEN N' bchain' ELSE N'' END +
						CASE WHEN @lv__TranDetailsAvailable = 1 THEN N' trans' ELSE N'' END +
						CASE WHEN @lv__LockDetailsAvailable = 1 THEN N' waits3' ELSE N'' END + NCHAR(10) + N'--?>');
		END
		ELSE
		BEGIN
			--user asked for the "queries" to go against various AutoWho base tables. These are for ad-hoc research that is more common.
			INSERT INTO #CapTimeCmdText (captimecmd_xml)
			SELECT convert(xml,N'<?optqry --' + NCHAR(10) +
						CASE WHEN @lv__BChainAvailable = 1 THEN N' bchain' ELSE N'' END +
						CASE WHEN @lv__TranDetailsAvailable = 1 THEN N' trans' ELSE N'' END +
						CASE WHEN @lv__LockDetailsAvailable = 1 THEN N' waits3' ELSE N'' END + NCHAR(10) + NCHAR(13) +
						N' -- ' + NCHAR(10) + NCHAR(13) + 
						N'SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct WITH (NOLOCK) ORDER BY ct.UTCCaptureTime DESC;
SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_Log l WITH (NOLOCK) ORDER BY l.LogDT DESC;
SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) WHERE sar.UTCCaptureTime = ''' + 
	REPLACE(CONVERT(NVARCHAR(20), @hctUTC, 102),'.','-')+' '+CONVERT(NVARCHAR(20), @hctUTC, 108)+'.'+RIGHT(CONVERT(NVARCHAR(20),N'000')+CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hctUTC)),3)+N''';
SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw WITH (NOLOCK) WHERE taw.UTCCaptureTime = ''' + 
	REPLACE(CONVERT(NVARCHAR(20), @hctUTC, 102),'.','-')+' '+CONVERT(NVARCHAR(20), @hctUTC, 108)+'.'+RIGHT(CONVERT(NVARCHAR(20),N'000')+CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hctUTC)),3)+N''';
SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails td WITH (NOLOCK) WHERE td.UTCCaptureTime = ''' + 
	REPLACE(CONVERT(NVARCHAR(20), @hctUTC, 102),'.','-')+' '+CONVERT(NVARCHAR(20), @hctUTC, 108)+'.'+RIGHT(CONVERT(NVARCHAR(20),N'000')+CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hctUTC)),3)+N''';
SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_LockDetails ld WITH (NOLOCK) WHERE ld.UTCCaptureTime = ''' + 
	REPLACE(CONVERT(NVARCHAR(20), @hctUTC, 102),'.','-')+' '+CONVERT(NVARCHAR(20), @hctUTC, 108)+'.'+RIGHT(CONVERT(NVARCHAR(20),N'000')+CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hctUTC)),3)+N''';
SELECT * FROM AutoWho.BlockingGraphs bg WITH (NOLOCK) WHERE bg.UTCCaptureTime = ''' + 
	REPLACE(CONVERT(NVARCHAR(20), @hctUTC, 102),'.','-')+' '+CONVERT(NVARCHAR(20), @hctUTC, 108)+'.'+RIGHT(CONVERT(NVARCHAR(20),N'000')+CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hctUTC)),3)+N''';
SELECT * FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore sss WITH (NOLOCK) WHERE sss.PKSQLStmtStoreID = ;
SELECT * FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore qpss WITH (NOLOCK) WHERE qpss.PKQueryPlanStmtStoreID = ;
SELECT dco.* --,sar.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimCommand dco --INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) ON sar.rqst__FKDimCommand = dco.DimCommandID
SELECT dca.* --,sar.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca --INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) ON sar.conn__FKDimConnectionAttribute = dca.DimConnectionAttributeID
SELECT dln.* --,sar.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln --INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) ON sar.sess__FKDimLoginName = dln.DimLoginNameID
SELECT dna.* --,sar.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna  --INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) ON sar.conn__FKDimNetAddress = dna.DimNetAddressID
SELECT dsa.*  --,sar.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa --INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) ON sar.sess__FKDimSessionAttribute = dsa.DimSessionAttributeID
SELECT dwt.*  --,sar.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt  --INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar WITH (NOLOCK) ON sar.rqst__FKDimWaitType = dwt.DimWaitTypeID
SELECT dwt.* ,taw.* 
FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt INNER JOIN @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw WITH (NOLOCK) ON taw.FKDimWaitType = dwt.DimWaitTypeID' + NCHAR(10) + NCHAR(13) + N'--?>')
		END
	END

	--Some of our below work will be more efficient if we pull a distinct list of FK<store> values.
	SET @lv__ResultDynSQL = N'
	INSERT INTO #DistinctFKs (
		FKSQLStmtStoreID,
		FKSQLBatchStoreID,
		FKInputBufferStoreID,
		FKQueryPlanBatchStoreID,
		FKQueryPlanStmtStoreID
	)
	SELECT DISTINCT 
			sar.FKSQLStmtStoreID,
			sar.FKSQLBatchStoreID,
			sar.FKInputBufferStoreID,
			sar.FKQueryPlanBatchStoreID,
			sar.FKQueryPlanStmtStoreID
		FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar 
		';

	--Keeping the distinct list as small as possible helps keep this procedure efficient.
	-- Apply filters here
	IF @DBInclusionsExist = 1
	BEGIN
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
			INNER JOIN #FilterTab dbs
				ON sar.sess__database_id = dbs.FilterID
				AND dbs.FilterType = 0
		';
	END

	IF @SPIDInclusionsExist = 1
	BEGIN
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
			INNER JOIN #FilterTab spid 
				ON sar.session_id = spid.FilterID
				AND spid.FilterType = 2
		';
	END

	SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		WHERE sar.UTCCaptureTime = @hctUTC
		AND sar.CollectionInitiatorID = ' + CONVERT(NVARCHAR,@init) + '
	';

	IF @activity = 0
	BEGIN
		--we only want to see running spids/requests
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		AND sar.request_id <> ' + convert(nvarchar(20), @lv__nullsmallint);
	END
	ELSE IF @activity = 1
	BEGIN
		--return running + idle w/tran
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		AND (sar.sess__open_transaction_count > 0 OR sar.request_id <> ' + convert(nvarchar(20), @lv__nullsmallint) + N')';
	END
	--ELSE IF @activity = 2		no filter on tran count or request_id
	
	--Are we filtering by duration?
	IF ISNULL(@dur,0) > 0
	BEGIN
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		AND sar.calc__duration_ms >= ' + CONVERT(nvarchar(30), @dur);
	END

	IF @blockonly = N'Y'
	BEGIN
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		AND sar.calc__block_relevant = 1
		';
	END

	IF @DBExclusionsExist = 1
	BEGIN
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		AND NOT EXISTS (SELECT * FROM #FilterTab xdbs WHERE sar.sess__database_id = xdbs.FilterID AND xdbs.FilterType = 1)
		';
	END

	IF @SPIDExclusionsExist = 1
	BEGIN
		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		AND NOT EXISTS (SELECT * FROM #FilterTab xspid WHERE sar.session_id = xspid.FilterID AND xspid.FilterType = 3)
		';
	END
	;
	--print @lv__ResultDynSQL;
	EXEC sp_executesql @stmt=@lv__ResultDynSQL, @params=N'@hctUTC DATETIME', @hctUTC=@hctUTC;

	
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
		SELECT DISTINCT fk.FKSQLStmtStoreID
		FROM #DistinctFKs fk
		WHERE fk.FKSQLStmtStoreID IS NOT NULL 
		)
	;

	DECLARE resolveSQLStmtStore CURSOR LOCAL FAST_FORWARD FOR
	SELECT 
		PKSQLStmtStoreID,
		[sql_handle],
		[dbid],
		[objectid],
		stmt_text
	FROM #SQLStmtStore sss
	;

	OPEN resolveSQLStmtStore;
	FETCH resolveSQLStmtStore INTO @PKSQLStmtStoreID,
		@sql_handle,
		@dbid,
		@objectid,
		@stmt_text
	;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		--Note that one major assumption of this procedure is that the DBID has not changed since the time the spid was 
		-- collected. For performance reasons, we do not resolve DBID in AutoWho.Collector; thus, if a DB is detached/re-attached,
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
			SET @stmt_xml = CONVERT(XML, N'<?cmd --' + NCHAR(10)+NCHAR(13) + N'sql_handle is 0x0. The current SQL statement cannot be displayed.' + NCHAR(10) + NCHAR(13) + 
			N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 
			NCHAR(10) + NCHAR(13) + N'-- ?>');
		END
		ELSE
		BEGIN
			IF @stmt_text IS NULL
			BEGIN
				SET @stmt_xml = CONVERT(XML, N'<?cmd --' + NCHAR(10)+NCHAR(13) + N'The statement text is NULL. No T-SQL command to display.' + NCHAR(10) + NCHAR(13) + 
					N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
			END
			ELSE
			BEGIN
				BEGIN TRY
					SET @stmt_xml = CONVERT(XML, N'<?cmd --' + NCHAR(10)+NCHAR(13) + @stmt_text + + NCHAR(10) + NCHAR(13) + 
					N'PKSQLStmtStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLStmtStoreID,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END TRY
				BEGIN CATCH
					SET @stmt_xml = CONVERT(XML, N'<?cmd --' + NCHAR(10)+NCHAR(13) + N'Error converting text to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
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

	IF @batch = N'Y'
	BEGIN
		INSERT INTO #SQLBatchStore (
			PKSQLBatchStoreID,
			[sql_handle],
			--[dbid],
			--[objectid],
			batch_text
			--batch_xml,
			--dbname,
			--schname,
			--objname
		)
		SELECT 
			sbs.PKSQLBatchStoreID,
			sbs.sql_handle,
			--sbs.dbid,
			--sbs.objectid,
			sbs.batch_text
		FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore sbs
		WHERE EXISTS (
			SELECT *
			FROM #DistinctFKs fk
			WHERE fk.FKSQLBatchStoreID IS NOT NULL 
			AND fk.FKSQLBatchStoreID = sbs.PKSQLBatchStoreID
		);

		DECLARE resolveSQLBatchStore CURSOR LOCAL FAST_FORWARD FOR 
		SELECT 
			sbs.PKSQLBatchStoreID,
			sbs.sql_handle,
			--sbs.dbid,
			--sbs.objectid,
			sbs.batch_text
		FROM #SQLBatchStore sbs
		;

		OPEN resolveSQLBatchStore;
		FETCH resolveSQLBatchStore INTO @PKSQLBatchStoreID,
			@sql_handle,
			--@dbid,
			--@objectid,
			@batch_text;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			/* We do not need to do this logic ("what is dbname? what is object name?") for the batch because we already did it for the statement
			IF @dbid > 0
			BEGIN
				SET @dbname = DB_NAME(@dbid);
			END
			ELSE
			BEGIN
				SET @dbname = N'';
			END

			IF @objectid > 0
			BEGIN
				SET @objectname = OBJECT_NAME(@objectid);
			END
			ELSE
			BEGIN
				SET @objectname = N'';
			END

			IF @objectid > 0
			BEGIN
				IF @dbid > 0
				BEGIN
					SET @schname = OBJECT_SCHEMA_NAME(@objectid, @dbid);
				END
				ELSE
				BEGIN
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
			*/

			IF @sql_handle = 0x0
			BEGIN
				SET @batch_xml = CONVERT(XML, N'<?SQLBatch --' + NCHAR(10)+NCHAR(13) + N'sql_handle is 0x0. The current SQL batch cannot be displayed.' + NCHAR(10) + NCHAR(13) + 
				N'@PKSQLBatchStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLBatchStoreID,-1)) + 
				NCHAR(10) + NCHAR(13) + N'-- ?>');
			END
			ELSE
			BEGIN
				IF @batch_text IS NULL
				BEGIN
					SET @batch_xml = CONVERT(XML, N'<?SQLBatch --' + NCHAR(10)+NCHAR(13) + N'The batch text is NULL. No T-SQL command to display.' + NCHAR(10) + NCHAR(13) + 
						N'@PKSQLBatchStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLBatchStoreID,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END
				ELSE
				BEGIN
					BEGIN TRY
						SET @batch_xml = CONVERT(XML, N'<?SQLBatch --' + NCHAR(10)+NCHAR(13) + @batch_text + NCHAR(10) + NCHAR(13) + 
						N'@PKSQLBatchStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLBatchStoreID,-1)) + 
						NCHAR(10) + NCHAR(13) + N'-- ?>');
					END TRY
					BEGIN CATCH
						SET @batch_xml = CONVERT(XML, N'<?SQLBatch --' + NCHAR(10)+NCHAR(13) + N'Error converting text to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
						N'@PKSQLBatchStoreID: ' + CONVERT(NVARCHAR(20),ISNULL(@PKSQLBatchStoreID,-1)) + 

						NCHAR(10) + NCHAR(13) + N'-- ?>');
					END CATCH
				END
			END

			UPDATE #SQLBatchStore
			SET --dbname = @dbname,
				--objname = @objectname,
				--schname = @schname,
				batch_xml = @batch_xml
			WHERE PKSQLBatchStoreID = @PKSQLBatchStoreID;

			FETCH resolveSQLBatchStore INTO @PKSQLBatchStoreID,
				@sql_handle,
				--@dbid,
				--@objectid,
				@batch_text;
		END	--WHILE loop for SQL Batch store cursor

		CLOSE resolveSQLBatchStore;
		DEALLOCATE resolveSQLBatchStore;
	END  --IF @batch = N'Y'

	IF @ibuf = N'Y'
	BEGIN
		INSERT INTO #InputBufferStore (
			PKInputBufferStoreID,
			inputbuffer
			--inputbuffer_xml
		)
		SELECT ibs.PKInputBufferStoreID,
			ibs.InputBuffer
		FROM @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore ibs
		WHERE EXISTS (
			SELECT * 
			FROM #DistinctFKs fk
			WHERE fk.FKInputBufferStoreID IS NOT NULL 
			AND fk.FKInputBufferStoreID = ibs.PKInputBufferStoreID
		)
		;

		DECLARE resolveInputBufferStore  CURSOR LOCAL FAST_FORWARD FOR 
		SELECT 
			PKInputBufferStoreID,
			inputbuffer
		FROM #InputBufferStore
		;

		OPEN resolveInputBufferStore;
		FETCH resolveInputBufferStore INTO @PKInputBufferStore,
			@ibuf_text;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @ibuf_text IS NULL
			BEGIN
				SET @ibuf_xml = CONVERT(XML, N'<?IBuf --' + NCHAR(10)+NCHAR(13) + N'The Input Buffer is NULL.' + NCHAR(10) + NCHAR(13) + 
				N'PKInputBufferStore: ' + CONVERT(NVARCHAR(20),ISNULL(@PKInputBufferStore,-1)) + 
				NCHAR(10) + NCHAR(13) + N'-- ?>');
			END
			ELSE
			BEGIN
				BEGIN TRY
					SET @ibuf_xml = CONVERT(XML, N'<?IBuf --' + NCHAR(10)+NCHAR(13) + @ibuf_text + + NCHAR(10) + NCHAR(13) + 
					N'PKInputBufferStore: ' + CONVERT(NVARCHAR(20),ISNULL(@PKInputBufferStore,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END TRY
				BEGIN CATCH
					SET @ibuf_xml = CONVERT(XML, N'<?IBuf --' + NCHAR(10)+NCHAR(13) + N'Error converting Input Buffer to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
					N'PKInputBufferStore: ' + CONVERT(NVARCHAR(20),ISNULL(@PKInputBufferStore,-1)) + 
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END CATCH
			END

			UPDATE #InputBufferStore
			SET inputbuffer_xml = @ibuf_xml
			WHERE PKInputBufferStoreID = @PKInputBufferStore;

			FETCH resolveInputBufferStore INTO @PKInputBufferStore,
				@ibuf_text;
		END

		CLOSE resolveInputBufferStore;
		DEALLOCATE resolveInputBufferStore;
	END		--IF @ibuf = N'Y'

	IF @plan = N'statement'
	BEGIN
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
		WHERE EXISTS (
			SELECT *
			FROM #DistinctFKs fk
			WHERE fk.FKQueryPlanStmtStoreID IS NOT NULL 
			AND fk.FKQueryPlanStmtStoreID = qpss.PKQueryPlanStmtStoreID
		)
		;

		DECLARE resolveQueryPlanStmtStore CURSOR LOCAL FAST_FORWARD FOR 
		SELECT qpss.PKQueryPlanStmtStoreID,
			qpss.plan_handle,
			qpss.query_plan_text
		FROM #QueryPlanStmtStore qpss;

		OPEN resolveQueryPlanStmtStore;
		FETCH resolveQueryPlanStmtStore INTO @PKQueryPlanStmtStoreID,
			@plan_handle,
			@query_plan_text;

		WHILE @@FETCH_STATUS = 0
		BEGIN
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
						SET @query_plan_xml = CONVERT(XML, N'<?StmtPlan --' + NCHAR(10)+NCHAR(13) + N'Error converting Statement Query Plan to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
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

	IF @plan = N'full'
	BEGIN
		INSERT INTO #QueryPlanBatchStore (
			PKQueryPlanBatchStoreID,
			[plan_handle],
			--[dbid],
			--[objectid],
			[query_plan_text]
		)
		SELECT 
			qpbs.PKQueryPlanBatchStoreID,
			qpbs.plan_handle,
			qpbs.query_plan
		FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore qpbs
		WHERE EXISTS (
			SELECT *
			FROM #DistinctFKs fk
			WHERE fk.FKQueryPlanBatchStoreID IS NOT NULL 
			AND fk.FKQueryPlanBatchStoreID = qpbs.PKQueryPlanBatchStoreID
		)
		;

		DECLARE resolveQueryPlanBatchStore CURSOR LOCAL FAST_FORWARD FOR 
		SELECT qpbs.PKQueryPlanBatchStoreID,
			qpbs.plan_handle,
			qpbs.query_plan_text
		FROM #QueryPlanBatchStore qpbs;

		OPEN resolveQueryPlanBatchStore;
		FETCH resolveQueryPlanBatchStore INTO @PKQueryPlanBatchStoreID,
			@plan_handle,
			@query_plan_text;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @plan_handle = 0x0
			BEGIN
				SET @query_plan_xml = CONVERT(XML, N'<?BatchPlan --' + NCHAR(10)+NCHAR(13) + N'plan_handle is 0x0. The Batch Query Plan cannot be displayed.' + NCHAR(10) + NCHAR(13) + 
				N'PKQueryPlanBatchStoreID: ' + CONVERT(NVARCHAR(20), ISNULL(@PKQueryPlanBatchStoreID,-1)) +
				NCHAR(10) + NCHAR(13) + N'-- ?>');
			END
			ELSE
			BEGIN
				IF @query_plan_text IS NULL
				BEGIN
					SET @query_plan_xml = CONVERT(XML, N'<?BatchPlan --' + NCHAR(10)+NCHAR(13) + N'The Batch Query Plan is NULL.' + NCHAR(10) + NCHAR(13) + 
					N'PKQueryPlanBatchStoreID: ' + CONVERT(NVARCHAR(20), ISNULL(@PKQueryPlanBatchStoreID,-1)) +
					NCHAR(10) + NCHAR(13) + N'-- ?>');
				END
				ELSE
				BEGIN
					BEGIN TRY
						SET @query_plan_xml = CONVERT(XML, @query_plan_text);
					END TRY
					BEGIN CATCH
						SET @query_plan_xml = CONVERT(XML, N'<?BatchPlan --' + NCHAR(10)+NCHAR(13) + N'Error converting Batch Query Plan to XML: ' + ERROR_MESSAGE() + NCHAR(10) + NCHAR(13) + 
						N'PKQueryPlanBatchStoreID: ' + CONVERT(NVARCHAR(20), ISNULL(@PKQueryPlanBatchStoreID,-1)) +

						CASE WHEN ERROR_NUMBER() = 6335 AND @PKSQLStmtStoreID IS NOT NULL THEN 
							N'-- You can extract this query plan to a file with the below script
							--DROP TABLE dbo.largeQPbcpout
							SELECT query_plan
							INTO dbo.largeQPbcpout
							FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore q
							WHERE q.PKQueryPlanBatchStoreID = ' + CONVERT(NVARCHAR(20),@PKQueryPlanBatchStoreID) + N'
							--then from a command line:
							bcp dbo.largeQPbcpout out c:\largeqpxmlout.sqlplan -c -S. -T
							'
						ELSE N'' END + 

						NCHAR(10) + NCHAR(13) + N'-- ?>');
					END CATCH
				END
			END

			UPDATE #QueryPlanBatchStore
			SET query_plan_xml = @query_plan_xml
			WHERE PKQueryPlanBatchStoreID = @PKQueryPlanBatchStoreID;

			FETCH resolveQueryPlanBatchStore INTO @PKQueryPlanBatchStoreID,
				@plan_handle,
				@query_plan_text;
		END

		CLOSE resolveQueryPlanBatchStore;
		DEALLOCATE resolveQueryPlanBatchStore;
	END

	IF @lv__IncludeBChain = 1
	BEGIN
		SET @lv__BChainString = N'';

		BEGIN TRY

			SELECT @lv__BChainString = @lv__BChainString + ss.StringRepresentation
			FROM (
				SELECT 
					StringRepresentation = (
						CASE --add a line break between groups
							WHEN bg.levelindc = 0 THEN NCHAR(13) + NCHAR(10) ELSE N'' END +
						REPLICATE(N'    ', bg.levelindc) + 
							SUBSTRING(CONVERT(NCHAR(20), bg.session_id), 1,7) +
							--Ugh, for some reason trying to do a NULLIF on request_id (comparing to @lv__nullsmallint) is screwing up the bchain
							SUBSTRING(REPLACE(CONVERT(NCHAR(20), bg.request_id),N'-929', N'idle'),1,7) + 
							SUBSTRING(ISNULL(CONVERT(NCHAR(20), bg.exec_context_id),CONVERT(NCHAR(20),N'idle')),1,7) + 

							--DEBUG ONLY: was useful for when I had problems with the sort order
							--SUBSTRING(ISNULL(CONVERT(NCHAR(20), bg.calc__blocking_session_id),CONVERT(NCHAR(20),N'idle')),1,7) + 
							--SUBSTRING(ISNULL(CONVERT(NCHAR(20), bg.sort_value),CONVERT(NCHAR(20),N'idle')),1,20) + 
						
							SUBSTRING(ISNULL(CONVERT(NCHAR(60), bg.wait_type),CONVERT(NCHAR(60),N'<null>')),1,24) + 
							SUBSTRING(ISNULL(CONVERT(NCHAR(60), bg.wait_duration_ms),CONVERT(NCHAR(60),N'<null>')),1,18) + 

							ISNULL(bg.resource_description, N'<null resource info>') + 
							N'        ' + 
								CASE WHEN bg.request_id = @lv__nullsmallint
										THEN ( 
											SELECT ISNULL(b2.InputBuffer, N'<Input Buffer is not available>')
											FROM
											(SELECT 1 as col1) dummy1 
												OUTER APPLY (
												SELECT REPLACE(REPLACE(SUBSTRING(b.InputBuffer, 1, 256),NCHAR(10), N' '), NCHAR(13), N' ') as InputBuffer
												FROM @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore b
												WHERE bg.FKInputBufferStoreID = b.PKInputBufferStoreID
												) b2
											)
									ELSE ((CASE WHEN OBJECT_NAME(stmt.objectid, stmt.dbid) IS NOT NULL 
												THEN N'[' + ISNULL(OBJECT_SCHEMA_NAME(stmt.objectid, stmt.dbid),N'<null>') + N'].[' + OBJECT_NAME(stmt.objectid, stmt.dbid) + N']'
											ELSE N'[Ad Hoc Batch]'
										END) + N'        ' + ISNULL(REPLACE(REPLACE(SUBSTRING(stmt.stmt_text, 1, 256),NCHAR(10), N' '), NCHAR(13), N' '),N'<statement text not available>')
										)
								END + 
						NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10) 
					),
					sort_value
				FROM @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs bg
					LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore stmt
						ON bg.FKSQLStmtStoreID = stmt.PKSQLStmtStoreID
				WHERE bg.UTCCaptureTime = @hctUTC
				AND bg.CollectionInitiatorID = @init
				AND bg.levelindc < = (@bchain - 1)
				) ss
			ORDER BY sort_value
			OPTION(MAXDOP 1, KEEPFIXED PLAN, MAXRECURSION 100);

			--select * from @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs order by UTCCaptureTime 

			SET @lv__BChainString = N'<?BChain --' + NCHAR(13) + NCHAR(10) + 
			N'Spid   Rqst   Ecid   WaitTyp                 Wait_Dur_ms       Wait Resource                              If idle, Input Buffer; If running, Object Name and Current Statement' + NCHAR(13) + NCHAR(10) +
			N'----------------------------------------------------------------------------------------------------------------------------------------------' + NCHAR(13) + NCHAR(10) + 
			@lv__BChainString + NCHAR(13) + NCHAR(10) + 
			NCHAR(13) + NCHAR(10) + 
	N'-- ?>';

			INSERT INTO #BchainConverted (
				bchain_xml 
			)
			SELECT CONVERT(XML,@lv__BChainString);
		END TRY
		BEGIN CATCH
			INSERT INTO #BchainConverted (
				bchain_xml 
			)
			SELECT CONVERT(XML,
				N'<?BChain --' + NCHAR(13) + NCHAR(10) + 
					N'Error occurred when converting BChain to XML: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()),N'<null>') + 
						N'; State: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_STATE()),N'<null>') + N'; Severity: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_SEVERITY()),N'<null>') + 
						N'; Message: ' + ISNULL(ERROR_MESSAGE(),N'<null>') +
						NCHAR(13) + NCHAR(10) + 
						NCHAR(13) + NCHAR(10) + 
				N'-- ?>'
			);
		END CATCH
	END		--IF @lv__IncludeBChain = 1


	IF @lv__IncludeLockDetails = 1
	BEGIN
		SET @lv__LockString = N'';

		BEGIN TRY
			--for debugging: 
			--DECLARE @lv__LockString NVARCHAR(MAX),
			--	@hctUTC DATETIME;

			;WITH FormattedAndOrdered AS (
				SELECT TOP 2147483647
					SPID = LTRIM(RTRIM(SPID)),
					[Status] = LTRIM(RTRIM([Status])),
					[Resource] = LTRIM(RTRIM([Resource])),
					ResourceDB = LTRIM(RTRIM(ResourceDB)),
					ResourceDesc = LTRIM(RTRIM(ResourceDesc)),
					ResourceEntity = LTRIM(RTRIM(isnull(ResourceEntity,'?'))),
					Mode = LTRIM(RTRIM(Mode)),
					[Partition] = LTRIM(RTRIM([Partition])),
					RecordCount = LTRIM(RTRIM(RecordCount)),
					OwnerInfo = LTRIM(RTRIM(OwnerInfo)),
					OwnerType = LTRIM(RTRIM(OwnerType))
				FROM (
					SELECT 
						--ordering columns
						request_session_id, 
						request_request_id,
						request_exec_context_id,
						request_status,
						resource_database_id,
						resource_type,
						resource_subtype,
						resource_associated_entity_id,

						[SPID] = CASE WHEN ISNULL(request_exec_context_id,0) = 0
									THEN (CASE WHEN ISNULL(request_request_id,0) = 0 
											THEN convert(nvarchar(20),request_session_id)
											ELSE convert(nvarchar(20),request_session_id) + N':' + convert(nvarchar(20),request_request_id)
											END
										)
									ELSE convert(nvarchar(20),request_session_id) + N':' + isnull(convert(nvarchar(20),request_request_id),N'<null>') + N':' + 
										convert(nvarchar(20),request_exec_context_id)
								END, 
						[Status] = request_status,
						[Resource] = resource_type + CASE WHEN LTRIM(RTRIM(ISNULL(resource_subtype,N''))) <> N'' THEN N':' + resource_subtype ELSE N'' END, 
						[ResourceDB] = CASE WHEN resource_database_id = 32767 THEN N'<resource DB>'
							WHEN resource_database_id = 0 THEN N'N/A'
							WHEN resource_database_id < 0 THEN N'?'
							ELSE ISNULL(DB_NAME(resource_database_id),'?')
						END, 
						[ResourceDesc] = resource_description, 
						[ResourceEntity] = CASE 
							WHEN resource_type = 'DATABASE' THEN N''
							WHEN resource_type = 'OBJECT' THEN OBJECT_NAME(resource_associated_entity_id,resource_database_id) 
							ELSE convert(nvarchar(20),resource_associated_entity_id) END, 
						[Mode] = request_mode, 
						[Partition] = ISNULL(convert(nvarchar(20),resource_lock_partition),N''), 
						RecordCount = CONVERT(nvarchar(20),ISNULL(RecordCount,0)),
						[OwnerInfo] = CASE WHEN request_owner_type = 3 THEN N'' 
										WHEN request_owner_type = 0 THEN N'Tran: ' + CONVERT(nvarchar(20),request_owner_id)
										ELSE N'??? ' + CONVERT(nvarchar(20),request_owner_id)
									END + 
								CASE WHEN request_owner_guid IS NULL OR LTRIM(RTRIM(request_owner_guid)) = N'' THEN N''
									ELSE N'{' + CONVERT(nvarchar(100), request_owner_guid) + N'}'
									END,
						[OwnerType] = CASE request_owner_type 
												WHEN 0 THEN N'TRANSACTION'
												WHEN 1 THEN N'CURSOR'
												WHEN 2 THEN N'SESSION'
												WHEN 3 THEN N'SHARED_TRANSACTION_WORKSPACE'
												WHEN 4 THEN N'EXCLUSIVE_TRANSACTION_WORKSPACE'
												WHEN 5 THEN N'NOTIFICATION_OBJECT'
												ELSE N'?'
											END
					FROM @@CHIRHO_SCHEMA@@.AutoWho_LockDetails
					WHERE UTCCaptureTime = @hctUTC	-- '2015-07-06 16:32:52.733'
					AND CollectionInitiatorID = @init 
				) ss
			ORDER BY request_session_id, 
					request_request_id,
					request_exec_context_id,
					request_status DESC,		--"WAIT" goes first
					resource_database_id,
					resource_type,
					resource_subtype,
					resource_associated_entity_id
			)
			SELECT @lv__LockString = @lv__LockString +
				SPID + REPLICATE(N' ',11 - LEN(SPID)) + 
				[Status] + REPLICATE(N' ',9 - LEN([Status])) + 
				[Resource] + REPLICATE(N' ',27 - LEN(substring([Resource],1,26))) + 
				ResourceDB + REPLICATE(N' ',26 - LEN(substring([ResourceDB],1,25))) + 
				ResourceDesc + REPLICATE(N' ',41 - LEN(substring([ResourceDesc],1,41))) + 
				ResourceEntity + REPLICATE(N' ',36 - LEN(substring([ResourceEntity],1,35))) + 
				Mode + REPLICATE(N' ',11 - LEN([Mode])) + 
				[Partition] + REPLICATE(N' ',16 - LEN([Partition])) + 
				RecordCount + REPLICATE(N' ',10 - LEN([RecordCount])) + 
				OwnerType + REPLICATE(N' ', 30 - LEN([OwnerType])) + 
				OwnerInfo + NCHAR(10)
			FROM FormattedAndOrdered
			;


			SET @lv__LockString = N'<?Locks -- ' + NCHAR(10) + N'
SPID       Status   ResourceTypeSubType        ResourceDB                ResourceDesc                             ResourceEntity                      Mode       Partition       #Rows     OwnerType                     OwnerInfo
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
' + ISNULL(@lv__LockString,N'<null>') + NCHAR(10) + NCHAR(13) + 
N' -- ?>';

/* copy-paste the below text just below the line of dashes above when making adjustments to the alignment
123:0:128__CONVERT_____________________________HealthcareWorkManagement__aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb_Sch-Maaaaa_bbbbbbbbbbbbbb__12345678__aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa__ccccccccccccccccccccccccccc
*/

			INSERT INTO #LockDetailsConverted (
				lockdetails_xml
			)
			SELECT CONVERT(XML, @lv__LockString);
			/*
			SELECT * from #LockDetailsConverted;
			SELECT * FROM dbo.AutoWho_SessionsAndRequests sar 
			WHERE sar.UTCCaptureTime = @hctUTC
			AND sar.session_id = -996;
			*/
		END TRY
		BEGIN CATCH
			INSERT INTO #LockDetailsConverted (
				lockdetails_xml
			)
			SELECT CONVERT(XML,
				N'<?Locks --' + NCHAR(13) + NCHAR(10) + 
					N'Error occurred when converting LockDetails to XML: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()),N'<null>') + 
						N'; State: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_STATE()),N'<null>') + N'; Severity: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_SEVERITY()),N'<null>') + 
						N'; Message: ' + ISNULL(ERROR_MESSAGE(),N'<null>') +
						NCHAR(13) + NCHAR(10) + 
						NCHAR(13) + NCHAR(10) + 
				N'-- ?>'
			);
		END CATCH
	END		--IF @lv__IncludeLockDetails = 1

	
	IF @lv__IncludeTranDetails = 1
	BEGIN
		INSERT INTO #TranDetails
		(session_id, tran__tlog_rsvd_bytes, tran__info)
		SELECT 
			bysession.bsnode.value('(session_id/text())[1]', 'SMALLINT') AS session_id,
			bysession.bsnode.value('(total_log_bytes/text())[1]', 'BIGINT') AS total_log_bytes,
			bysession.bsnode.value('(TranInfo/text())[1]', 'NVARCHAR(MAX)') AS tran_info
		FROM (
			SELECT CONVERT(XML,REPLACE
					(CONVERT(NVARCHAR(MAX), xmlcollapse.xmlcollapse1) COLLATE Latin1_General_Bin2,
						N'</TranInfo></trans><trans><TranInfo>',
						N''
							+ 
						--LEFT(CRYPT_GEN_RANDOM(1), 0)
						LEFT(CONVERT(VARCHAR(40),NEWID()),0)

						--This statement sometimes runs very slowly, so we are using a "side effecting function" to avoid the default Expression Service caching behavior,
						-- per the Paul White blog article here: http://sqlblog.com/blogs/paul_white/archive/2012/09/05/compute-scalars-expressions-and-execution-plan-performance.aspx 
						-- Yes, the warning was noted
					)
				) AS xmlbysession
			FROM (
				SELECT 
					CASE WHEN xmlprep.rn_sessionid = 1 THEN xmlprep.session_id ELSE NULL END as session_id, 
					CASE WHEN xmlprep.rn_sessionid = 1 THEN xmlprep.total_log_bytes ELSE NULL END as total_log_bytes,
					xmlprep.TranInfo
				FROM (
					SELECT TOP 1000
						SS2.session_id, 
						SS2.dtat_transaction_id, 
						SS2.rn_sessionid, 
						SS2.rn_tranid,
						total_log_bytes = CASE WHEN SS2.rn_sessionid = 1 THEN ISNULL(SS2.total_log_bytes,0) ELSE NULL END, 

						--The various mappings below come from BOL, of course. The emphasis of AutoWho.Collector is to store data in its raw form
						-- (direct from the DMVs) except when it would be very inefficient. The mapping/formatting is this procedure's responsibility.
						TranInfo = (
							(CASE WHEN SS2.rn_tranid = 1		--only output dtat info once per tran
							THEN 
						N'Xact (ID: ' + CONVERT(NVARCHAR(20),dtat_transaction_id) + N', Name: ' + ISNULL(dtat_name,N'<null>') + N')' + NCHAR(13) + 
						N'   UserTran: ' + CASE WHEN dtst_is_user_transaction IS NULL THEN N'?'
											WHEN dtst_is_user_transaction = 1 THEN N'True' ELSE N'False' END + NCHAR(13) + 
						N'   IsLocal: ' + CASE WHEN dtst_is_local IS NULL THEN N'?' 
											WHEN dtst_is_local = 1 THEN N'True' ELSE N'False' END + NCHAR(13) + 
						N'   Type: ' + CASE WHEN dtat_transaction_type = 1 THEN N'1=Read/Write' WHEN dtat_transaction_type = 2 THEN N'2=ReadOnly'
											WHEN dtat_transaction_type = 3 THEN N'3=Sys' WHEN dtat_transaction_type = 4 THEN N'4=Distributed' ELSE N'?' END + NCHAR(13) +
						N'   State: ' + CASE WHEN dtat_transaction_state = 0 THEN N'0=InitNotCompleted' WHEN dtat_transaction_state = 1 THEN N'1=InitButNotStarted' 
											WHEN dtat_transaction_state = 2 THEN N'2=Active' WHEN dtat_transaction_state = 3 THEN N'3=Ended' 
											WHEN dtat_transaction_state = 4 THEN N'4=CommitInitiated (Distributed-only)' WHEN dtat_transaction_state = 5 THEN N'5=PreparedandWaitingResolution' 
											WHEN dtat_transaction_state = 6 THEN N'6=Committed' WHEN dtat_transaction_state = 7 THEN N'7=InRollback' 
											WHEN dtat_transaction_state = 8 THEN N'8=RollbackComplete' ELSE N'?' END + NCHAR(13) + 
						N'   BeginTime: ' + ISNULL(CONVERT(NVARCHAR(30),dtat_transaction_begin_time,113),N'<null>') + NCHAR(13) + 
						N'   UOW: ' + ISNULL(CONVERT(NVARCHAR(40),dtat_transaction_uow), N'<null>') + NCHAR(13) +
								CASE WHEN dtat_dtc_state = 0 THEN N'' WHEN dtat_dtc_state = 1 THEN N'   DTCState: 1=ACTIVE'
									WHEN dtat_dtc_state = 2 THEN N'   DTCState: 2=PREPARED'
									WHEN dtat_dtc_state = 3 THEN N'   DTCState: 3=COMMITTED'
									WHEN dtat_dtc_state = 4 THEN N'   DTCState: 4=ABORTED'
									WHEN dtat_dtc_state = 5 THEN N'   DTCState: 5=RECOVERED'
									ELSE N'?' END  + NCHAR(13) + 
						N'   SnapshotTran: ' + CASE WHEN dtasdt_tran_exists IS NULL THEN N'No' 
									WHEN dtasdt_is_snapshot = 1 THEN N'Yes' ELSE N'VersionGeneratorOnly' END + NCHAR(13) + 
								CASE WHEN dtasdt_tran_exists IS NOT NULL  AND dtasdt_is_snapshot = 1
									THEN N'   MaxChainTraversed: ' + ISNULL(CONVERT(NVARCHAR(20),dtasdt_max_version_chain_traversed),N'?') + NCHAR(13) + 
										N'   AvgChainTraversed: ' + ISNULL(CONVERT(NVARCHAR(20),dtasdt_average_version_chain_traversed),N'?') + NCHAR(13) ELSE N'' END + 
						N'   Enlist Count: ' + ISNULL(CONVERT(NVARCHAR(20),dtst_enlist_count),N'?') + NCHAR(13) +
								CASE WHEN dtst_is_bound = 1 THEN (N'   IsBound: True ***' + NCHAR(13)) ELSE N'' END 
							ELSE N'' END)

							+ (
						 NCHAR(13) +  
							N'      DBXact ID: ' + ISNULL(CONVERT(NVARCHAR(20),dtdt_database_id),N'?') + NCHAR(13) +
							N'         DB: ' + ISNULL(DB_NAME(dtdt_database_id),N'<null>') + NCHAR(13) + 
							N'         Type: ' + CASE WHEN dtdt_database_transaction_type = 1 THEN N'1=Read/Write' WHEN dtdt_database_transaction_type = 2 THEN N'2=ReadOnly'
												WHEN dtdt_database_transaction_type = 3 THEN N'3=Sys' ELSE N'?' END + NCHAR(13) +
							N'         State: ' + CASE WHEN dtdt_database_transaction_state = 1 THEN N'1=NotInitialized' WHEN dtdt_database_transaction_state = 3 THEN N'3=InitButNoLogRecords' 
												WHEN dtdt_database_transaction_state = 4 THEN N'4=GeneratedLogRecords' WHEN dtdt_database_transaction_state = 5 THEN N'5=Prepared' 
												WHEN dtdt_database_transaction_state = 10 THEN N'10=Committed' WHEN dtdt_database_transaction_state = 11 THEN N'11=RolledBack' 
												WHEN dtdt_database_transaction_state = 12 THEN N'12=BeingCommitted' ELSE N'?' END + NCHAR(13) + 
							N'         BeginTime: ' + ISNULL(CONVERT(NVARCHAR(30),dtdt_database_transaction_begin_time,113),N'<null>') + NCHAR(13) +
							CASE WHEN dtdt_database_transaction_type = 2 THEN N''		--the below fields aren't relevant to read-only transactions
								ELSE (
							N'         #LogRecords: ' + CONVERT(NVARCHAR(20),dtdt_database_transaction_log_record_count) + + NCHAR(13) + 
							N'         #LogBytesRsvd: ' + CONVERT(NVARCHAR(20),dtdt_database_transaction_log_bytes_reserved) + 
								CASE WHEN dtdt_database_transaction_log_bytes_reserved_system > 0 
									THEN (N'  (sys: ' + CONVERT(NVARCHAR(20),dtdt_database_transaction_log_bytes_reserved_system) +
										CASE WHEN dtdt_database_transaction_log_bytes_reserved_system > (5*1024*1024) THEN N' ***' ELSE N'' END + N')  ')  ELSE N'' END + NCHAR(13) + 
							N'         #LogBytesUsed: ' + CONVERT(NVARCHAR(20),dtdt_database_transaction_log_bytes_used) + 
												CASE WHEN dtdt_database_transaction_log_bytes_used_system > 0 
													THEN (N'  (sys: ' + CONVERT(NVARCHAR(20),dtdt_database_transaction_log_bytes_used_system) + N')  ')  ELSE N'' END + NCHAR(13)
								)
							END + NCHAR(13)
							)
						)
					FROM (
						SELECT 
							SS1.*, 
							rn_tranid = ROW_NUMBER() OVER (PARTITION BY SS1.session_id, SS1.dtat_transaction_id ORDER BY dtdt_database_transaction_log_bytes_reserved DESC),
							rn_sessionid = ROW_NUMBER() OVER (PARTITION BY SS1.session_id ORDER BY (SELECT NULL)),
							[total_log_bytes] = SUM(SS1.tran_log_bytes) OVER (PARTITION BY SS1.session_id)
						FROM (
							SELECT
							--select * from @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails
								session_id,
								dtat_transaction_id,
								dtat_name,
								dtat_transaction_begin_time,
								dtat_transaction_type,
								dtat_transaction_state,
								dtat_transaction_uow,
								dtat_dtc_state,

								dtasdt_tran_exists,
								dtasdt_transaction_sequence_num,
								dtasdt_commit_sequence_num,
								[dtasdt_is_snapshot],
								dtasdt_first_snapshot_sequence_num,
								[dtasdt_max_version_chain_traversed],
								[dtasdt_average_version_chain_traversed],
								dtasdt_elapsed_time_seconds,

								[dtst_enlist_count],
								[dtst_is_enlisted],
								[dtst_is_user_transaction],
								[dtst_is_local],
								[dtst_is_bound],

								[dtdt_database_id],
								[dtdt_database_transaction_begin_time],
								[dtdt_database_transaction_type],
								[dtdt_database_transaction_state],
								[dtdt_database_transaction_log_record_count],
								--[dtdt_database_transaction_replicate_record_count],

								--Aaron: I've seen the used bytes be much higher than the reserved bytes (for an index rebuild).
								-- Don't understand that, so I'm just going to find the max and use that.
								[tran_log_bytes] = CASE WHEN (ISNULL(dtdt_database_transaction_log_bytes_used,0) + ISNULL(dtdt_database_transaction_log_bytes_used_system,0)) >= 
															(ISNULL(dtdt_database_transaction_log_bytes_reserved,0) + ISNULL(dtdt_database_transaction_log_bytes_reserved_system,0)) 
															THEN ISNULL(dtdt_database_transaction_log_bytes_used,0) + ISNULL(dtdt_database_transaction_log_bytes_used_system,0)
															ELSE ISNULL(dtdt_database_transaction_log_bytes_reserved,0) + ISNULL(dtdt_database_transaction_log_bytes_reserved_system,0) END,
								
								[dtdt_database_transaction_log_bytes_used],
								[dtdt_database_transaction_log_bytes_used_system],
								[dtdt_database_transaction_log_bytes_reserved],
								[dtdt_database_transaction_log_bytes_reserved_system]

								/*
								--TODO: consider whether to add the LSN fields
								[dtdt_database_transaction_most_recent_savepoint_lsn],
								[dtdt_database_transaction_commit_lsn],
								[dtdt_database_transaction_begin_lsn],
								[dtdt_database_transaction_last_lsn],
								[dtdt_database_transaction_last_rollback_lsn],
								[dtdt_database_transaction_next_undo_lsn]
								*/
							FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails t
							WHERE t.UTCCaptureTime = @hctUTC
							AND t.CollectionInitiatorID = @init
						) SS1
					) SS2
				) xmlprep
				ORDER BY xmlprep.session_id, dtat_transaction_id, rn_tranid
				FOR XML PATH(N'trans'), TYPE 
			) as xmlcollapse (xmlcollapse1)
		) as xmlextract
			CROSS APPLY xmlextract.xmlbysession.nodes(N'/trans') AS bysession (bsnode)
			WHERE bysession.bsnode.exist(N'session_id') = 1
		;

		--SELECT * FROM #TranDetails
	END		--IF @lv__IncludeTranDetails = 1
	
	SET @lv__BaseSELECT1 = N'
	;WITH basedata AS (
		SELECT 
			--sar fields
			sar.SPIDCaptureTime, 
			sar.session_id, 
			sar.request_id, 
			sar.TimeIdentifier, 
			sess__login_time, 
			sess__host_process_id, 
			sess__status_code, 
			sess__cpu_time = ISNULL(sess__cpu_time,0), 
			sess__memory_usage, 
			sess__total_scheduled_time, 
			sess__total_elapsed_time, 
			sess__last_request_start_time, 
			sess__last_request_end_time,
			sess__reads = ISNULL(sess__reads,0), 
			sess__writes = ISNULL(sess__writes,0), 
			sess__logical_reads = ISNULL(sess__logical_reads,0), 
			sess__is_user_process, 
			sess__lock_timeout, 
			sess__row_count, 
			sess__open_transaction_count, 
			sess__database_id, 
			sess__dbname = CASE WHEN sess__database_id = 32767 THEN N''<resource DB>'' 
								WHEN sess__database_id = 0 THEN N''''
								ELSE ISNULL(DB_NAME(sess__database_id),N'''') END,
			sess__FKDimLoginName, 
			sess__FKDimSessionAttribute, 
			conn__connect_time, 
			conn__FKDimNetAddress, 
			conn__FKDimConnectionAttribute, 
			rqst__start_time, 
			rqst__status_code, 
			rqst__blocking_session_id, 
			rqst__wait_time, 
			rqst__wait_resource, 
			rqst__open_transaction_count, 
			rqst__open_resultset_count, 
			rqst__percent_complete, 
			rqst__cpu_time = ISNULL(rqst__cpu_time,0), 
			rqst__total_elapsed_time, 
			rqst__scheduler_id, 
			rqst__reads = ISNULL(rqst__reads,0), 
			rqst__writes = ISNULL(rqst__writes,0), 
			rqst__logical_reads = ISNULL(rqst__logical_reads,0), 
			rqst__transaction_isolation_level, 
			rqst__lock_timeout, 
			rqst__deadlock_priority, 
			rqst__row_count, 
			rqst__granted_query_memory, 
			rqst__executing_managed_code, 
			rqst__group_id, 
			rqst__FKDimCommand, 
			rqst__FKDimWaitType, 
			tempdb__sess_user_objects_alloc_page_count, 
			tempdb__sess_user_objects_dealloc_page_count, 
			tempdb__sess_internal_objects_alloc_page_count, 
			tempdb__sess_internal_objects_dealloc_page_count, 
			tempdb__task_user_objects_alloc_page_count, 
			tempdb__task_user_objects_dealloc_page_count, 
			tempdb__task_internal_objects_alloc_page_count, 
			tempdb__task_internal_objects_dealloc_page_count, 
			[tempdb__usage] = (
				CASE WHEN (ISNULL(sar.tempdb__sess_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_user_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__sess_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_user_objects_dealloc_page_count,0)) END + 
				CASE WHEN (ISNULL(sar.tempdb__sess_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_internal_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__sess_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__sess_internal_objects_dealloc_page_count,0)) END + 
				CASE WHEN (ISNULL(sar.tempdb__task_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_user_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__task_user_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_user_objects_dealloc_page_count,0)) END + 
				CASE WHEN (ISNULL(sar.tempdb__task_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_internal_objects_dealloc_page_count,0)) < 0 THEN 0
					ELSE (ISNULL(sar.tempdb__task_internal_objects_alloc_page_count,0) - ISNULL(sar.tempdb__task_internal_objects_dealloc_page_count,0)) END),
			[tempdb__alloc] = (
				ISNULL(tempdb__sess_user_objects_alloc_page_count,0) + ISNULL(tempdb__sess_internal_objects_alloc_page_count,0) + 
				ISNULL(tempdb__task_user_objects_alloc_page_count,0) + ISNULL(tempdb__task_internal_objects_alloc_page_count,0)),
			tempdb__CalculatedNumberOfTasks, 
			mgrant__request_time, 
			mgrant__grant_time, 
			mgrant__requested_memory_kb, 
			mgrant__required_memory_kb, 
			mgrant__granted_memory_kb, 
			mgrant__used_memory_kb, 
			mgrant__max_used_memory_kb, 
			mgrant__dop, 
			calc__record_priority, 
			calc__is_compiling,
			calc__duration_ms, 
			[calc__duration_seconds] = (
				CASE 
					WHEN sar.session_id <= 0 THEN NULL
					WHEN (rqst__start_time = ''1900-01-01'' OR sess__last_request_end_time = ''1900-01-01'') THEN NULL
					ELSE DATEDIFF(SECOND, TimeIdentifier, sar.SPIDCaptureTime)
				END
			),
			calc__blocking_session_id, 
			calc__block_relevant, 
			calc__wait_details, 
			calc__return_to_user, 
			calc__is_blocker, 
			calc__sysspid_isinteresting, 
			calc__tmr_wait,
			calc__node_info,
			calc__status_info,
			FKSQLStmtStoreID, 
			FKSQLBatchStoreID, 
			FKInputBufferStoreID, 
			FKQueryPlanBatchStoreID, 
			FKQueryPlanStmtStoreID,
		';

		SET @lv__BaseSELECT2 = N'
			--progress fields
			ProgressPct = CASE 
						WHEN sar.request_id = @lv__nullsmallint OR sar.session_id <= 0 THEN N''''
						WHEN ISNULL(sar.rqst__percent_complete,0) < 0.001 THEN N'''' 
						ELSE N''('' + CONVERT(nvarchar(20), convert(decimal(5,2),sar.rqst__percent_complete)) + N''%)  '' 
					END,
			ProgressSessStat = CASE WHEN sar.session_id <= 0 OR (sar.sess__is_user_process = 0 AND sar.sess__status_code IN (0,1)) THEN N''''
						WHEN sar.sess__status_code IN (2,3,255) 
							THEN (CASE sar.sess__status_code
									WHEN 2 THEN N''[dormant] ''
									WHEN 3 THEN N''[preconnect] ''
									ELSE N''[sess status: ?] ''
								END)
						ELSE N''''
					END,
			ProgressRqstStat = CASE WHEN sar.request_id = @lv__nullsmallint OR sar.session_id <= 0 THEN N'''' 
							WHEN sar.sess__is_user_process = 0 AND sar.rqst__status_code = 0 THEN N''''
							WHEN sar.tempdb__CalculatedNumberOfTasks > 1 AND sar.calc__status_info <> N''<placeholder>''
								THEN N''{'' + sar.calc__status_info + N''} ''
							WHEN sar.rqst__status_code IN (1,4) THEN N''''
							ELSE (CASE sar.rqst__status_code
									WHEN 0 THEN N''{bkgd}  ''
									WHEN 2 THEN N''{rable}  ''
									WHEN 3 THEN N''{sleep}  ''
									ELSE N''{rqst status: ?}  ''
								END)
						END,
			--dimcmd fields
			[rqst__command] = dimcmd.command,

			--dln fields
			dln.login_name,
			dln.original_login_name,

			--taw fields
			task_address, 
			parent_task_address, 
			exec_context_id, 
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

			--sss fields
			stmt_sql_handle = sss.sql_handle,
			sss.statement_start_offset,
			sss.statement_end_offset,
			stmt_dbid = sss.dbid,
			stmt_objectid = sss.objectid,
			stmt_datalen_batch = sss.datalen_batch,
			sss.stmt_xml,
			stmt_dbname = sss.dbname,
			stmt_objname = sss.objname,
			stmt_schname = sss.schname, 
			stmt_isadhoc = CASE WHEN sar.request_id <> @lv__nullsmallint AND sss.dbid = @lv__nullsmallint AND sss.objectid = @lv__nullsmallint
							THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END,
			' + 
			CASE WHEN @lv__IncludeTranDetails = 1 THEN N'
			transtring = td.tran__info,
			trantotallogbytes = tran__tlog_rsvd_bytes,
			' ELSE N'' END + 

			CASE WHEN @plan = N'none' THEN N''
				WHEN @plan = 'statement'
				THEN N'		qpss.query_plan_xml,'
				WHEN @plan = 'full'
				THEN N'		qpbs.query_plan_xml,'
			ELSE N''
			END + 

			CASE WHEN @batch = N'N' THEN N'' 
			ELSE N'			sbs.batch_xml,'
			END + 

			CASE WHEN @ibuf = N'N' THEN N''
			ELSE N'			ibs.inputbuffer_xml,'
			END;

		/* Waits logic
			Misc notes: 
				- we assume that not many system spids will be "interesting" at the same time. Thus, the correlated sub-query in that block of the WHEN 
					will not be run often. (Normal caveats about CASE short-circuiting not being 100% guaranteed apply. I haven't had a problem with this so far). 

				- If FKDimCommand=3 (the special mapping for dm_exec_requests.command = "TM REQUEST"), then we consult the calc__tmr_wait field to see which tmr sub-code 
					to display. The reason for this convoluted logic is that we track command="TM REQUEST" cases explicitly, since the sql_handle is often 0x0 in those
					cases, even when a procedure is being used instead of ad-hoc SQL. We want to display something to the user in the ObjectName field to let them know
					that this isn't necessarily ad-hoc SQL, but that the sql_handle couldn't be resolved.

					Thus, we need to track TM REQUEST instances anyways, so for those cases we also track the wait_type value as an encoded number for efficiency.

				- An attempt was made to determine when a SPID was compiling (based on some patterns observed in the sql text/plan text-related fields of dm_exec_requests.
					However, in production that logic did not work well, and so for now I've backed off. 

		*/
		IF @waits = 0		--show just the wait_type, rather than any info that might give more in-depth insight to the wait
		BEGIN
			SET @lv__BaseSELECT2 = @lv__BaseSELECT2 + N'
			wait_type = CASE WHEN sar.session_id < 0 OR sar.request_id = @lv__nullsmallint THEN N'''' 
				WHEN sar.calc__sysspid_isinteresting = 1 THEN (SELECT ' + CASE WHEN @savespace = N'Y' THEN N'wait_type_short' ELSE N'wait_type' END + N'
							FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType syswait
							WHERE syswait.DimWaitTypeID = sar.rqst__FKDimWaitType)
				WHEN sar.rqst__FKDimCommand = 3 THEN (
					CASE sar.calc__tmr_wait 
						WHEN 2 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'WriLog' ELSE N'WRITELOG' END + N''' 
						WHEN 3 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'PREm_TransImport' ELSE N'PREEMPTIVE_TRANSIMPORT' END + N''' 
						WHEN 4 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'PREm_DTCEnlist' ELSE N'PREEMPTIVE_DTC_ENLIST' END + N''' 
						WHEN 5 THEN N''DTC_STATE''
						WHEN 6 THEN N''DTC''
						WHEN 7 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'LogBuf' ELSE N'LOGBUFFER' END + N''' 
						WHEN 8 THEN N''TRANSACTION_MUTEX''
						WHEN 254 THEN N''?wait''
						ELSE N'''' END)
				--WHEN sar.calc__is_compiling = CONVERT(BIT,1) THEN N''<compiling>''
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__none) + N') THEN N''''
				WHEN dwt.wait_type LIKE N''LATCH%'' THEN dwt.latch_subtype + REPLACE(dwt.wait_type,N''LATCH_'', N''('') + N'')''
				ELSE ' + CASE WHEN @savespace = N'N' THEN N'dwt.wait_type' ELSE N'dwt.wait_type_short' END + N'
				END
			';
		END
		ELSE IF @waits = 1
			--show the type of lock wait, the type of page, and the CXPACKET node
		BEGIN
			--Note that LCK_M waits don't have a "short" version, and thus the dwt.wait_type tag hasn't been
			-- replaced in the below code
			SET @lv__BaseSELECT2 = @lv__BaseSELECT2 + N'
			wait_type = CASE WHEN sar.session_id < 0 OR sar.request_id = @lv__nullsmallint THEN N''''
				WHEN sar.calc__sysspid_isinteresting = 1 THEN (SELECT ' + CASE WHEN @savespace = N'Y' THEN N'wait_type_short' ELSE N'wait_type' END + N'
							FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType syswait
							WHERE syswait.DimWaitTypeID = sar.rqst__FKDimWaitType)
				WHEN sar.rqst__FKDimCommand = 3 THEN (
					CASE sar.calc__tmr_wait 
						WHEN 2 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'WriLog' ELSE N'WRITELOG' END + N''' 
						WHEN 3 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'PREm_TransImport' ELSE N'PREEMPTIVE_TRANSIMPORT' END + N''' 
						WHEN 4 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'PREm_DTCEnlist' ELSE N'PREEMPTIVE_DTC_ENLIST' END + N''' 
						WHEN 5 THEN N''DTC_STATE''
						WHEN 6 THEN N''DTC''
						WHEN 7 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'LogBuf' ELSE N'LOGBUFFER' END + N''' 
						WHEN 8 THEN N''TRANSACTION_MUTEX''
						WHEN 254 THEN N''?wait''
						ELSE N'''' END)
				--WHEN sar.calc__is_compiling = CONVERT(BIT,1) THEN N''<compiling>''
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__none) + N') THEN N''''
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__lck) + N') 
					THEN (CASE taw.wait_special_number
						WHEN 1 THEN N''KEY''	WHEN 2 THEN N''RID''
						WHEN 3 THEN N''PAGE''	WHEN 4 THEN N''OBJECT''
						WHEN 5 THEN N''APP''	WHEN 6 THEN N''HOBT''
						WHEN 7 THEN N''ALLOCUNIT''	WHEN 8 THEN N''DB''
						WHEN 9 THEN N''FILE''	WHEN 10 THEN N''EXTENT''
						ELSE N''?'' END + 
					
					REPLACE(dwt.wait_type,N''LCK_M_'',N''{req:'') + N'' held:'' + taw.wait_special_tag + N''}'' )

				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__pgblocked) + N',' + CONVERT(nvarchar(20),@enum__waitspecial__pgio) + N',' + CONVERT(nvarchar(20),@enum__waitspecial__pg) + N') 
					THEN (' + CASE WHEN @savespace = N'Y' 
								THEN N'dwt.wait_type_short' 
								ELSE N'dwt.wait_type' 
							END + N' + 
							N''{'' + ISNULL(DB_NAME(resource_dbid),N''?db?'') + N'' '' + 
									ISNULL(CONVERT(nvarchar(20),wait_special_number),N''?file?'') + N'':'' + 
							CASE WHEN taw.resource_associatedobjid % 8088 = 0 OR taw.resource_associatedobjid = 1 THEN N''PFS''
								WHEN (taw.resource_associatedobjid-1) % 511232 = 0 OR taw.resource_associatedobjid = 3 THEN N''SGAM''
								WHEN taw.resource_associatedobjid % 511232 = 0 OR taw.resource_associatedobjid = 2 THEN N''GAM''
								WHEN (taw.resource_associatedobjid-6) % 511232 = 0 OR taw.resource_associatedobjid = 6 THEN N''DCM''
								WHEN (taw.resource_associatedobjid-7) % 511232 = 0 OR taw.resource_associatedobjid = 7 THEN N''ML''
							ELSE N'''' END + N''}'')
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__cxp) + N') 
					THEN (' + CASE WHEN @savespace = N'Y' THEN N'dwt.wait_type_short' ELSE N'dwt.wait_type' END + N' + N'':'' + taw.wait_special_tag + N'':'' + CONVERT(nvarchar(20),taw.wait_special_number))
				WHEN dwt.wait_type LIKE N''LATCH%'' THEN dwt.latch_subtype + REPLACE(dwt.wait_type,N''LATCH_'', N''('') + N'')'' 
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__other) + N')
					THEN ' + CASE WHEN @savespace = N'Y' THEN N'dwt.wait_type_short' ELSE N'dwt.wait_type' END + N'
				ELSE N'''' END
			';
		END
		ELSE	--@wait IN (2,3): lotsa detail
		BEGIN
			--Note that LCK_M waits don't have a "short" version, and thus the dwt.wait_type tag hasn't been
			-- replaced in the below code
			SET @lv__BaseSELECT2 = @lv__BaseSELECT2 + N'
			wait_type = CASE WHEN sar.session_id < 0 OR sar.request_id = @lv__nullsmallint THEN N''''
				WHEN sar.calc__sysspid_isinteresting = 1 THEN (SELECT ' + CASE WHEN @savespace = N'Y' THEN N'wait_type_short' ELSE N'wait_type' END + N'
							FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType syswait
							WHERE syswait.DimWaitTypeID = sar.rqst__FKDimWaitType)
				WHEN sar.rqst__FKDimCommand = 3 THEN (
					CASE sar.calc__tmr_wait 
						WHEN 2 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'WriLog' ELSE N'WRITELOG' END + N''' 
						WHEN 3 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'PREm_TransImport' ELSE N'PREEMPTIVE_TRANSIMPORT' END + N''' 
						WHEN 4 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'PREm_DTCEnlist' ELSE N'PREEMPTIVE_DTC_ENLIST' END + N''' 
						WHEN 5 THEN N''DTC_STATE''
						WHEN 6 THEN N''DTC''
						WHEN 7 THEN N''' + CASE WHEN @savespace = N'Y' THEN N'LogBuf' ELSE N'LOGBUFFER' END + N''' 
						WHEN 8 THEN N''TRANSACTION_MUTEX''
						WHEN 254 THEN N''?wait''
						ELSE N'''' END)
				--WHEN sar.calc__is_compiling = CONVERT(BIT,1) THEN N''<compiling>''
				WHEN taw.wait_special_category IN (' + CONVERT(nvarchar(20),@enum__waitspecial__none) + N') THEN N''''
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__lck) + N') 
				THEN (CASE taw.wait_special_number
						WHEN 1 THEN N''KEY''	WHEN 2 THEN N''RID''
						WHEN 3 THEN N''PAGE''	WHEN 4 THEN N''OBJECT''
						WHEN 5 THEN N''APP''	WHEN 6 THEN N''HOBT''
						WHEN 7 THEN N''ALLOCUNIT''	WHEN 8 THEN N''DB''
						WHEN 9 THEN N''FILE''	WHEN 10 THEN N''EXTENT''
						ELSE N''?'' END + 
					
					REPLACE(dwt.wait_type,N''LCK_M_'',N''{req:'') + 
					N'' held:'' + taw.wait_special_tag + N''}'' + 
						CASE WHEN taw.resolution_successful = CONVERT(BIT,0) OR taw.resolved_name IS NULL
							THEN N''{dbid:'' + CONVERT(nvarchar(20),taw.resource_dbid) + 
								N'' id:'' + ISNULL(CONVERT(nvarchar(20),NULLIF(taw.resource_associatedobjid,@lv__nullint)),N''?'') + N''}'' 
							ELSE taw.resolved_name
							END 
						)
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__pgblocked) + N',' + CONVERT(nvarchar(20),@enum__waitspecial__pgio) + N',' + CONVERT(nvarchar(20),@enum__waitspecial__pg) + N') 
					THEN (' + CASE WHEN @savespace = N'Y' 
								THEN N'dwt.wait_type_short' 
								ELSE N'dwt.wait_type' 
							END + N' + 
						 
						N''{'' + CASE WHEN taw.resolution_successful = CONVERT(BIT,1) AND taw.resolved_name IS NOT NULL THEN taw.resolved_name
							ELSE ( ISNULL(DB_NAME(resource_dbid),N''?db?'') + 
									ISNULL(CONVERT(nvarchar(20),wait_special_number),N''?file?'') + N'':'' + 
									CASE WHEN taw.resource_associatedobjid % 8088 = 0 OR taw.resource_associatedobjid = 1 THEN N''PFS''
										WHEN (taw.resource_associatedobjid-1) % 511232 = 0 OR taw.resource_associatedobjid = 3 THEN N''SGAM''
										WHEN taw.resource_associatedobjid % 511232 = 0 OR taw.resource_associatedobjid = 2 THEN N''GAM''
										WHEN (taw.resource_associatedobjid-6) % 511232 = 0 OR taw.resource_associatedobjid = 6 THEN N''DCM''
										WHEN (taw.resource_associatedobjid-7) % 511232 = 0 OR taw.resource_associatedobjid = 7 THEN N''ML''
									ELSE N'''' END
								)
							END + N''}''
						)
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__cxp) + N') 
					THEN (' + CASE WHEN @savespace = N'Y' THEN N'dwt.wait_type_short' ELSE N'dwt.wait_type' END + N' + N'':'' + taw.wait_special_tag + N'':'' + CONVERT(nvarchar(20),taw.wait_special_number))
				WHEN dwt.wait_type LIKE N''LATCH%'' THEN dwt.latch_subtype + REPLACE(dwt.wait_type,N''LATCH_'', N''('') + N'')'' 
				WHEN taw.wait_special_category IN (' + CONVERT(NVARCHAR(20),@enum__waitspecial__other) + N')
					THEN ' + CASE WHEN @savespace = N'Y' THEN N'dwt.wait_type_short' ELSE N'dwt.wait_type' END + N'
				ELSE N'''' END
			';
		END

		--Extra info about connectivity and session attributes
		IF @attr = N'Y'
		BEGIN
			SET @lv__BaseSELECT2 = @lv__BaseSELECT2 + N'
			,[Client] = dsa.host_name
			,[IP] = dna.client_net_address
			,[Program] = dsa.program_name
			,[SessAttr] = CASE WHEN sar.sess__is_user_process = 0 OR sar.session_id < 0 THEN N'''' 
				ELSE N''<?spid'' + CONVERT(nvarchar(20),sar.session_id) + N'' -- '' + NCHAR(10) + NCHAR(13) + 

				N''Connect Time:				'' + isnull(convert(nvarchar(30),sar.conn__connect_time,113),N''<null>'') + NCHAR(10) + 
				N''Login Time:					'' + isnull(convert(nvarchar(30),sar.sess__login_time,113),N''<null>'') + NCHAR(10) + 
				N''Last Request Start Time:	'' + isnull(convert(nvarchar(30),sar.sess__last_request_start_time,113),N''<null>'') + NCHAR(10) + 
				N''Last Request End Time:		'' + isnull(convert(nvarchar(30),sar.sess__last_request_end_time,113),N''<null>'') + NCHAR(10) + NCHAR(13) + 

				N''Client PID:					'' + isnull(CONVERT(nvarchar(20),sar.sess__host_process_id),N''<null>'') + NCHAR(10) +
				N''Client Interface/Version:	'' + isnull(dsa.client_interface_name,N''<null>'') + N'' / '' + isnull(CONVERT(nvarchar(20),dsa.client_version),N''<null>'') + NCHAR(10) +
				N''Net Transport:				'' + isnull(dca.net_transport,N''<null>'') + NCHAR(10) +
				N''Client Address/Port:		'' + isnull(dna.client_net_address,N''<null>'') + + N'' / '' + isnull(convert(nvarchar(20),nullif(sar.conn__client_tcp_port,@lv__nullint)),N''<null>'') + NCHAR(10) + 
				N''Local Address/Port:			'' + isnull(nullif(dna.local_net_address,@lv__nullstring),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),nullif(dna.local_tcp_port,@lv__nullint)),N''<null>'') + NCHAR(10) + 
				N''Endpoint (Sess/Conn):		'' + isnull(convert(nvarchar(20),dsa.endpoint_id),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),dca.endpoint_id),N''<null>'') + NCHAR(10) + 
				N''Protocol Type/Version:		'' + isnull(dca.protocol_type,N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),dca.protocol_version),N''<null>'') + NCHAR(10) +
				N''Net Transport:				'' + isnull(dca.net_transport,N''<null>'') + NCHAR(10) + 
				N''Net Packet Size:			'' + isnull(convert(nvarchar(20),dca.net_packet_size),N''<null>'') + NCHAR(10) + 
				N''Encrypt Option:				'' + isnull(dca.encrypt_option,N''<null>'') + NCHAR(10) + 
				N''Auth Scheme:				'' + isnull(dca.auth_scheme,N''<null>'') + NCHAR(10) + NCHAR(13) + 

				N''Node Affinity:				'' + isnull(convert(nvarchar(20),dca.node_affinity),N''<null>'') + NCHAR(10) +
				N''Group ID (Sess/Rqst):		'' + isnull(convert(nvarchar(20),dsa.group_id),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),isnull(sar.rqst__group_id,-1)),N''<null>'') + NCHAR(10) + 
				N''Scheduler ID:				'' + isnull(convert(nvarchar(20),sar.rqst__scheduler_id),N''<null>'') + NCHAR(10) + 
				N''Managed Code:				'' + isnull(convert(nvarchar(20),sar.rqst__executing_managed_code),N''<null>'') + NCHAR(10) + NCHAR(13) + 

				N''Open Tran Count (Sess/Rqst):		'' + isnull(convert(nvarchar(20),sar.sess__open_transaction_count),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),sar.rqst__open_transaction_count),N''<null>'') + NCHAR(10) + 
				N''Tran Iso Level (Sess/Rqst):			'' + isnull(convert(nvarchar(20),dsa.transaction_isolation_level),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),sar.rqst__transaction_isolation_level),N''<null>'') + NCHAR(10) + 
				N''Lock Timeout (Sess/Rqst):			'' + isnull(convert(nvarchar(20),sar.sess__lock_timeout),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),sar.rqst__lock_timeout),N''<null>'') + NCHAR(10) + 
				N''Deadlock Priority (Sess/Rqst):		'' + isnull(convert(nvarchar(20),dsa.deadlock_priority),N''<null>'') + N'' / '' + isnull(convert(nvarchar(20),sar.rqst__deadlock_priority),N''<null>'') + NCHAR(10) + 
				 NCHAR(13) + N'' -- ?>'' 
				END
			';
		END

		--detailed counters about tempdb, memory, CPU, and IO
		IF @resource = N'Y'
		BEGIN
			SET @lv__BaseSELECT2 = @lv__BaseSELECT2 + N'
			,[Resources] = CASE WHEN sar.session_id < 0 THEN N'''' 
		ELSE N''<?spid'' + CONVERT(nvarchar(20),sar.session_id) + N'' --'' + NCHAR(10) + NCHAR(13) + 
			N''TempDB'' + NCHAR(10) + 
			N''-----------------------------------------------------------'' + NCHAR(10) + 
			N''Session User Pages:		'' + CASE 
				WHEN tempdb__sess_user_objects_alloc_page_count IS NULL OR tempdb__sess_user_objects_dealloc_page_count IS NULL
					THEN N''<null>  (alloc: '' + ISNULL(CONVERT(nvarchar(20),tempdb__sess_user_objects_alloc_page_count),N''<null>'') + N''  dealloc: '' + 
							ISNULL(CONVERT(nvarchar(20),tempdb__sess_user_objects_dealloc_page_count),N''<null>'') + N'')''
					ELSE (CONVERT(nvarchar(20),tempdb__sess_user_objects_alloc_page_count - tempdb__sess_user_objects_dealloc_page_count) + 
						N'' = '' + CONVERT(nvarchar(20),tempdb__sess_user_objects_alloc_page_count) + N'' (alloc) - '' + 
						CONVERT(nvarchar(20),tempdb__sess_user_objects_dealloc_page_count) + N'' (dealloc)''
						)
				END + NCHAR(10) + 
			N''Session Internal Pages:	'' + CASE 
				WHEN tempdb__sess_internal_objects_alloc_page_count IS NULL OR tempdb__sess_internal_objects_dealloc_page_count IS NULL
					THEN N''<null>  (alloc: '' + ISNULL(CONVERT(nvarchar(20),tempdb__sess_internal_objects_alloc_page_count),N''<null>'') + N''  dealloc: '' + 
							ISNULL(CONVERT(nvarchar(20),tempdb__sess_internal_objects_dealloc_page_count),N''<null>'') + N'')''
					ELSE (CONVERT(nvarchar(20),tempdb__sess_internal_objects_alloc_page_count - tempdb__sess_internal_objects_dealloc_page_count) + 
						N'' = '' + CONVERT(nvarchar(20),tempdb__sess_internal_objects_alloc_page_count) + N'' (alloc) - '' + 
						CONVERT(nvarchar(20),tempdb__sess_internal_objects_dealloc_page_count) + N'' (dealloc)''
						)
				END + NCHAR(10) + 
			N''Task User Pages:		'' + CASE 
				WHEN tempdb__task_user_objects_alloc_page_count IS NULL OR tempdb__task_user_objects_dealloc_page_count IS NULL
					THEN N''<null>  (alloc: '' + ISNULL(CONVERT(nvarchar(20),tempdb__task_user_objects_alloc_page_count),N''<null>'') + N''  dealloc: '' + 
							ISNULL(CONVERT(nvarchar(20),tempdb__task_user_objects_dealloc_page_count),N''<null>'') + N'')''
					ELSE (CONVERT(nvarchar(20),tempdb__task_user_objects_alloc_page_count - tempdb__task_user_objects_dealloc_page_count) + 
						N'' = '' + CONVERT(nvarchar(20),tempdb__task_user_objects_alloc_page_count) + N'' (alloc) - '' + 
						CONVERT(nvarchar(20),tempdb__task_user_objects_dealloc_page_count) + N'' (dealloc)''
						)
				END + NCHAR(10) + 
			N''Task Internal Pages:	'' + CASE 
				WHEN tempdb__sess_internal_objects_alloc_page_count IS NULL OR tempdb__task_internal_objects_dealloc_page_count IS NULL
					THEN N''<null>  (alloc: '' + ISNULL(CONVERT(nvarchar(20),tempdb__task_internal_objects_alloc_page_count),N''<null>'') + N''  dealloc: '' + 
							ISNULL(CONVERT(nvarchar(20),tempdb__task_internal_objects_dealloc_page_count),N''<null>'') + N'')''
					ELSE (CONVERT(nvarchar(20),tempdb__task_internal_objects_alloc_page_count - tempdb__task_internal_objects_dealloc_page_count) + 
						N'' = '' + CONVERT(nvarchar(20),tempdb__task_internal_objects_alloc_page_count) + N'' (alloc) - '' + 
						CONVERT(nvarchar(20),tempdb__task_internal_objects_dealloc_page_count) + N'' (dealloc)''
						)
				END + NCHAR(10) + NCHAR(13) + 
			N''Memory'' + NCHAR(10) + 
			N''-----------------------------------------------------------'' + NCHAR(10) + 
			N''Session Memory (kb) =	'' + isnull(convert(nvarchar(20),sess__memory_usage),N''<null>'') + NCHAR(10) + 
			N''Grant Request Time =	'' + isnull(convert(nvarchar(30),mgrant__request_time,113),N''<null>'') + NCHAR(10) + 
			N''Grant Time =			'' + isnull(convert(nvarchar(30),mgrant__grant_time,113),N''<null>'') + NCHAR(13) + NCHAR(10) + 
			N''Required Mem (kb) =		'' + ISNULL(CONVERT(nvarchar(20),mgrant__required_memory_kb),N''<null>'') + NCHAR(10) + 
			N''Requested Mem (kb) =	'' + ISNULL(CONVERT(nvarchar(20),mgrant__requested_memory_kb),N''<null>'') + NCHAR(10) + 
			N''Granted Mem (kb) =		'' + ISNULL(CONVERT(nvarchar(20),mgrant__granted_memory_kb),N''<null>'') + NCHAR(10) + 
			N''Orig Mem Grant (kb) =	'' + ISNULL(CONVERT(nvarchar(20),rqst__granted_query_memory*8),N''<null>'') + NCHAR(10) + 
			N''Used Mem (kb) =			'' + ISNULL(CONVERT(nvarchar(20),mgrant__used_memory_kb),N''<null>'') + NCHAR(10) + 
			N''Max Used Mem (kb) =		'' + ISNULL(CONVERT(nvarchar(20),mgrant__max_used_memory_kb),N''<null>'') + NCHAR(10) + 
			N''DOP =					'' + isnull(convert(nvarchar(20),mgrant__dop),N''<null>'') + NCHAR(10) + NCHAR(13) + 
			N''CPU and IO [Sess/Rqst]'' + NCHAR(10) + 
			N''-----------------------------------------------------------'' + NCHAR(10) + 
			N''Total Scheduled Time (ms) =	'' + ISNULL(CONVERT(nvarchar(20),sess__total_scheduled_time),N''<null>'') + NCHAR(10) + 
			N''Total Elapsed Time (ms) =	'' + ISNULL(CONVERT(nvarchar(20),sess__total_elapsed_time),N''<null>'') + N'' / '' + ISNULL(CONVERT(nvarchar(20),rqst__total_elapsed_time),N''<null>'') + NCHAR(10) + 
			N''CPU Time (ms) =				'' + ISNULL(CONVERT(nvarchar(20),sess__cpu_time),N''<null>'') + N'' / '' + ISNULL(CONVERT(nvarchar(20),rqst__cpu_time),N''<null>'') + NCHAR(10) + 
			N''# 8KB Reads (Logic) =		'' + ISNULL(CONVERT(nvarchar(20),sess__logical_reads),N''<null>'') + N'' / '' + ISNULL(CONVERT(nvarchar(20),rqst__logical_reads),N''<null>'') + NCHAR(10) + 
			N''# 8KB Reads (Phys) =		'' + ISNULL(CONVERT(nvarchar(20),sess__reads),N''<null>'') + N'' / '' + ISNULL(CONVERT(nvarchar(20),rqst__reads),N''<null>'') + NCHAR(10) + 
			N''# 8KB Writes (Logic) =		'' + ISNULL(CONVERT(nvarchar(20),sess__writes),N''<null>'') + N'' / '' + ISNULL(CONVERT(nvarchar(20),rqst__writes),N''<null>'') + NCHAR(10) +NCHAR(13) + 
			N''Miscellaneous'' + NCHAR(10) + 
			N''-----------------------------------------------------------'' + NCHAR(10) + 
			N''Rowcount =			'' + ISNULL(CONVERT(nvarchar(20),sess__row_count),N''<null>'') + N'' / '' + ISNULL(CONVERT(nvarchar(20),rqst__row_count),N''<null>'') + NCHAR(10) + 
			N''Open Result Sets =	'' + ISNULL(CONVERT(nvarchar(20),rqst__open_resultset_count),N''<null>'') + NCHAR(10) + NCHAR(13) + 
			N''--?>'' 
		END 
			';
		END

		SET @lv__BaseFROM = N'
		FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
		' + CASE WHEN @DBInclusionsExist = 1 THEN N'
			INNER JOIN #FilterTab dbs
				ON sar.sess__database_id = dbs.FilterID
				AND dbs.FilterType = 0
		' 
		ELSE N'' END
		+ CASE WHEN @SPIDInclusionsExist = 1 THEN N'
			INNER JOIN #FilterTab spid 
				ON sar.session_id = spid.FilterID
				AND spid.FilterType = 2
		'
		ELSE N'' END;

		SET @lv__BaseFROM = @lv__BaseFROM + N'
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimCommand dimcmd
				ON sar.rqst__FKDimCommand = dimcmd.DimCommandID
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
				ON sar.CollectionInitiatorID = taw.CollectionInitiatorID
				AND taw.CollectionInitiatorID = @init
				AND sar.UTCCaptureTime = taw.UTCCaptureTime
				AND taw.UTCCaptureTime = @tvar
				AND sar.session_id = taw.session_id
				AND sar.request_id = taw.request_id
				AND taw.task_priority = 1
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
				ON taw.FKDimWaitType = dwt.DimWaitTypeID
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln
				ON sar.sess__FKDimLoginName = dln.DimLoginNameID
			LEFT OUTER JOIN #SQLStmtStore sss
				ON sar.FKSQLStmtStoreID = sss.PKSQLStmtStoreID ' + 
				CASE WHEN @batch = N'Y'
				THEN N'
			LEFT OUTER JOIN #SQLBatchStore sbs
				ON sar.FKSQLBatchStoreID = sbs.PKSQLBatchStoreID'
				ELSE N''
				END + 

				CASE WHEN @ibuf = N'Y'
				THEN N'
			LEFT OUTER JOIN #InputBufferStore ibs
				ON sar.FKInputBufferStoreID = ibs.PKInputBufferStoreID'
				ELSE N''
				END + 

				CASE WHEN @plan = N'statement'
				THEN N'
			LEFT OUTER JOIN #QueryPlanStmtStore qpss
				ON sar.FKQueryPlanStmtStoreID = qpss.PKQueryPlanStmtStoreID'
				WHEN @plan = N'full'
				THEN N'
			LEFT OUTER JOIN #QueryPlanBatchStore qpbs
				ON sar.FKQueryPlanBatchStoreID = qpbs.PKQueryPlanBatchStoreID'
				ELSE N''
				END +

				CASE WHEN @attr = N'Y'
				THEN N'
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa
				ON sar.sess__FKDimSessionAttribute = dsa.DimSessionAttributeID
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna
				ON sar.conn__FKDimNetAddress = dna.DimNetAddressID
			LEFT OUTER JOIN @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca
				ON sar.conn__FKDimConnectionAttribute = dca.DimConnectionAttributeID
				'
				ELSE N'' END + 

				CASE WHEN @lv__IncludeTranDetails = 1 
				THEN N'
			LEFT OUTER JOIN #TranDetails td
				ON sar.session_id = td.session_id
				'
				ELSE N'' END + 
				
				+ N'
		WHERE sar.UTCCaptureTime = @tvar
		AND sar.CollectionInitiatorID = @init ' + 
		CASE WHEN ISNULL(@dur,0) <= 0 THEN N''
		ELSE N' AND ( sar.session_id < 0 OR sar.calc__duration_ms >= ' + CONVERT(nvarchar(20), @dur) + N' ) '
		END + 

		CASE WHEN @activity = 0 THEN N'
		AND (sar.session_id < 0 OR sar.request_id <> @lv__nullsmallint)
		' 
		WHEN @activity = 1 THEN N'
		AND (sar.session_id < 0 OR sar.request_id <> @lv__nullsmallint OR sar.sess__open_transaction_count > 0)
		' ELSE N'' END +

		CASE WHEN @blockonly = N'Y' THEN N'
		AND sar.calc__block_relevant = 1
		' ELSE N'' END + 

		CASE WHEN @lv__IncludeBChain = 0 THEN N'AND sar.session_id <> -997' ELSE N'' END + 
		CASE WHEN @lv__IncludeLockDetails = 0 THEN N'AND sar.session_id <> -996' ELSE N'' END +
		CASE WHEN @DBExclusionsExist = 1 THEN N'
		AND NOT EXISTS (SELECT * FROM #FilterTab xdbs WHERE sar.sess__database_id = xdbs.FilterID AND xdbs.FilterType = 1)
		' ELSE N'' END + 
		CASE WHEN @SPIDExclusionsExist = 1 THEN N'
		AND NOT EXISTS (SELECT * FROM #FilterTab xspid WHERE sar.session_id = xspid.FilterID AND xspid.FilterType = 3)
		' ELSE N'' END + N'
	)';


	--The "Progress" field has been by far the hardest to write/debug. if the "basedata" directive has been
	-- specified, we get the dynamic SQL for basedata and the 4 parts of the Progress field broken out.
	IF @dir LIKE '%basedata%'
	BEGIN
		SET @lv__ResultDynSQL = @lv__BaseSELECT1 + @lv__BaseSELECT2 + @lv__BaseFROM


		SELECT dyntxt as BaseDataDynamicSQL, TxtLink
		from (SELECT @lv__ResultDynSQL AS dyntxt) t0
			cross apply (select TxtLink=(select [processing-instruction(q)]=dyntxt
                            for xml path(''),type)) F2
		;


		SET @lv__ResultDynSQL = @lv__ResultDynSQL + N'
		SELECT b.* ,
			ProgressWaitType = CASE WHEN session_id = -998 
					THEN N''THREADPOOL'' + 
						CASE WHEN calc__duration_ms < 10000 THEN  + N'' = '' + CONVERT(nvarchar(20),calc__duration_ms) + N'' ms'' 
						ELSE N''  --> '' + CONVERT(NVARCHAR(20), CONVERT(DECIMAL(21,1),calc__duration_ms/1000.)) + N''sec <--'' END
					WHEN NULLIF(wait_type,@lv__nullstring) IS NULL OR wait_type = N''<nullvalue>'' OR wait_type = N'''' OR session_id <= 0 THEN N''''
					ELSE ( wait_type + 
							CASE WHEN calc__tmr_wait > 1 or calc__sysspid_isinteresting=1 THEN (
									CASE WHEN ISNULL(rqst__wait_time,0) < 10000
										THEN N'' = '' + CONVERT(NVARCHAR(20), ISNULL(rqst__wait_time,0)) + N''ms'' 
										ELSE N''  --> '' + CONVERT(NVARCHAR(20), CONVERT(DECIMAL(21,1),ISNULL(rqst__wait_time,0)/1000.)) + N''sec <--''
									END)
								--WHEN calc__is_compiling = CONVERT(BIT,1) THEN N''<compiling>''
								WHEN ISNULL(wait_duration_ms,0) < 10000
									THEN N''  = '' + CONVERT(NVARCHAR(20), ISNULL(wait_duration_ms,0)) + N''ms''
								ELSE N''  --> '' + CONVERT(NVARCHAR(20), CONVERT(DECIMAL(21,1),ISNULL(wait_duration_ms,0)/1000.)) + N''sec <--''
							END
						)
					END
		FROM basedata b;
		';


		EXEC sp_executesql @stmt=@lv__ResultDynSQL, 
			@params=N'@lv__nullsmallint SMALLINT, @lv__nullint INT, @lv__nullstring NVARCHAR(8), @tvar DATETIME, @init TINYINT', 
			@lv__nullsmallint=@lv__nullsmallint, @lv__nullint = @lv__nullint, @lv__nullstring = @lv__nullstring, @tvar=@hctUTC, @init=@init;

		RETURN 0;
	END



	--We always want a "header row" so that we can display the capture time and some other information.
	SET @lv__DummyRow = N'
	SELECT 
		[order_duration] = 0,
		[session_id] = ' + CASE WHEN @savespace = N'N' THEN N'N''CapTime' 
							ELSE N'N''Cap' END
			
		+ CASE WHEN @effectiveordinal IS NULL THEN N''
							ELSE N'[' + CONVERT(NVARCHAR(20),@effectiveordinal) + N']' END + N':'', 
		[request_id] = @lv__nullsmallint,
		[SPIDContext] = ''' + REPLACE(CONVERT(NVARCHAR(20), @hct, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @hct, 108) + '.' + 
			--old logic: CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hct)) + N''',
			RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @hct)),3) + N''',
		[Duration] = N'''', 
		[Blocking_SPID] =  N'''',
		[Object_Name] = N'''',
		[Current_Command] = (SELECT captimecmd_xml FROM #CapTimeCmdText),
		[#Tasks] = N'''',
		[Progress] = N'''',
		[QMem_MB] = N'''',
		[Tempdb_MB] = N'''',
		[cpu_time] = N'''',
		[reads] = N'''',
		[writes] = N'''',
		[logical_reads] = N'''',
		' + CASE WHEN @batch = N'N' THEN N''
			ELSE N'[BatchText] = N'''', '
			END + 
			CASE WHEN @plan IN (N'statement', N'full')
				THEN N'[QPlan] = N'''','
				ELSE N''
			END +
			CASE WHEN @ibuf = N'N' THEN N''
			ELSE N'[InputBuffer] = N'''','
			END + N'
		[Cxs] = N'''',
		[Login] = N'''',
		[calc__record_priority] = 0' + 

		CASE WHEN @lv__IncludeTranDetails = 1 THEN N'
		,[trans] = N''''
		' ELSE N'' END + 

		CASE WHEN @attr = N'Y' THEN N'
		,Client = N''''
		,IP = N''''
		,Program = N''''
		,SessAttr = N''''
		' ELSE N'' END +
			
		CASE WHEN @resource = N'Y' THEN N'
		,Resources = N''''
		' ELSE N'' END + N'
	UNION ALL
	';



	SET @lv__Formatted = 
	N', formatteddata AS (
	' + CASE WHEN @hctUTC IS NOT NULL 
		THEN @lv__DummyRow 
		ELSE N'' END + N'
	SELECT 
		' + CASE WHEN @hctUTC IS NOT NULL THEN N'' ELSE N'SPIDCaptureTime,' END + N'
		[order_duration] = (CASE WHEN session_id < 0 THEN 0
					WHEN calc__duration_seconds IS NULL THEN 99999
					WHEN request_id = @lv__nullsmallint THEN 
						( 
							CONVERT(decimal(15,1), 0) - 
							( 
								CONVERT(DECIMAL(15,1),calc__duration_seconds) + 

								CONVERT(DECIMAL(15,1),
									DATEDIFF(millisecond,
												DATEADD(second, 
														calc__duration_seconds,
														TimeIdentifier
														), 
												SPIDCaptureTime
											)/1000.
										)
							)
						)
					ELSE (
						CONVERT(DECIMAL(15,1),calc__duration_seconds) + 

						CONVERT(DECIMAL(15,1),
							DATEDIFF(millisecond,
										DATEADD(second, 
												calc__duration_seconds,
												TimeIdentifier
												), 
										SPIDCaptureTime
									)/1000.
								)
					)
				END),
		[session_id] = CASE WHEN session_id > 0
						THEN (CASE WHEN calc__is_blocker = 1 AND ISNULL(calc__blocking_session_id,0) = 0 THEN N''(!)  '' 
								WHEN calc__is_blocker = 1 AND ISNULL(calc__blocking_session_id,0) > 0 THEN N''*  ''
								ELSE N'''' END + 
								CASE WHEN sess__is_user_process = 0 THEN N''s'' ELSE N'''' END + CONVERT(nvarchar(20),session_id) + 
								CASE WHEN request_id > 0 THEN N'':'' + CONVERT(nvarchar(20),request_id) ELSE N'''' END
								)
						ELSE (CASE WHEN session_id = -998 THEN N''TaskWOSpid''
								WHEN session_id = -997 THEN N''Blk Chains''
								WHEN session_id = -996 THEN N''Lock Details''
							ELSE N'''' END)
						END, 
		request_id,
		[SPIDContext] = ' + CASE WHEN @savespace = N'N' THEN N'sess__dbname,'
					ELSE N'REPLACE(REPLACE(REPLACE(sess__dbname,N''Healthcareworkmanagement'', N''HCWM''), N''ReportingDW'', N''RDW''),N''BizTalk'',N''Bz:''),'
					END + N'
		[Duration] = CASE WHEN session_id < 0 THEN N''''
			WHEN request_id = @lv__nullsmallint THEN N''-'' ELSE N'''' END +
		
			(CASE WHEN session_id < 0 THEN N'''' 
					WHEN calc__duration_seconds IS NULL THEN N''???''
					ELSE (
						CASE WHEN calc__duration_seconds > 863999 
							THEN CONVERT(nvarchar(20), calc__duration_seconds / 86400) + N''~'' +			--day
										REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),(calc__duration_seconds % 86400)/3600)
											),1,2)) + N'':'' +			--hour
										REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),((calc__duration_seconds % 86400)%3600)/60)
											),1,2)) + N'':'' +			--minute
										REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),((calc__duration_seconds % 86400)%3600)%60)
											),1,2)) 					--second

							WHEN calc__duration_seconds > 86399
							THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),calc__duration_seconds / 86400)
											),1,2)) + N''~'' +			--day
										REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),(calc__duration_seconds % 86400)/3600)
											),1,2)) + N'':'' +			--hour
										REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),((calc__duration_seconds % 86400)%3600)/60)
											),1,2)) + N'':'' +			--minute
										REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),((calc__duration_seconds % 86400)%3600)%60)
											),1,2)) 			--second

							WHEN calc__duration_seconds > 59
								THEN REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),(calc__duration_seconds % 86400)/3600)
										),1,2)) + N'':'' +			--hour
									REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),((calc__duration_seconds % 86400)%3600)/60)
										),1,2)) + N'':'' +			--minute
									REVERSE(SUBSTRING(REVERSE(N''0'' + CONVERT(nvarchar(20),((calc__duration_seconds % 86400)%3600)%60)
										),1,2)) 			--second

							ELSE
								CONVERT(nvarchar(20),
									CONVERT(DECIMAL(15,1),calc__duration_seconds) + 

									CONVERT(DECIMAL(15,1),
										DATEDIFF(millisecond,
													DATEADD(second, 
															calc__duration_seconds,
															TimeIdentifier
															), 
													SPIDCaptureTime
												)/1000.
											)
									)
							END)
				END),
		'

	SET @lv__Formatted = @lv__Formatted + N'
		[Blocking_SPID] = CASE WHEN calc__blocking_session_id IS NULL OR session_id < 0 OR request_id = @lv__nullsmallint THEN N''''
							WHEN calc__blocking_session_id = 0 THEN N'''' 
							ELSE CONVERT(NVARCHAR(20), calc__blocking_session_id) END,
		[Object_Name] = CASE WHEN request_id = @lv__nullsmallint OR stmt_isadhoc = CONVERT(BIT,1) THEN N'''' 
							WHEN sess__is_user_process = 0 THEN ISNULL(rqst__command,N'''') 
							WHEN stmt_objectid IS NULL THEN N''?obj N/A?'' 
							ELSE ('
							+ CASE WHEN @savespace = N'Y' THEN N' '
							ELSE N'
							CASE WHEN stmt_schname IS NULL THEN N''?unknownschema.''
									WHEN stmt_schname = N'''' THEN N''''
									ELSE stmt_schname + N''.'' 
									END + ' END + N'
								CASE WHEN stmt_objname IS NULL THEN CONVERT(NVARCHAR(20),stmt_objectid)
								ELSE stmt_objname END' + 
							CASE WHEN @savespace = N'Y' THEN N' '
							ELSE N' + 
							CASE WHEN stmt_dbid IS NULL THEN N'' (?unknowndb)''
									WHEN stmt_dbid = 0 THEN N'' (?unknowndb)''
									WHEN stmt_dbid = 32767 THEN N'' (resourcedb)''
									ELSE (CASE 
											WHEN stmt_dbname IS NULL THEN N'' ('' + CONVERT(NVARCHAR(20),stmt_dbid) + N'')''
											WHEN stmt_dbname = sess__dbname THEN N''''
											ELSE N'' ('' + stmt_dbname + N'')'' 
										END)
									END' END + N' 
								)
					END + CASE WHEN rqst__FKDimCommand = 3 AND sess__is_user_process = 1 THEN N''(TMRQ)'' ELSE N'''' END,
		[Current_Command] = CASE WHEN session_id = -997 THEN (SELECT b.bchain_xml FROM #BchainConverted b)
						WHEN session_id = -996 THEN (SELECT l.lockdetails_xml FROM #LockDetailsConverted l)
					ELSE ISNULL(stmt_xml,N'''') END,
		[#Tasks] = CASE WHEN session_id = -998 THEN CONVERT(nvarchar(20),tempdb__CalculatedNumberOfTasks)
						WHEN request_id = @lv__nullsmallint OR session_id < 0 THEN N'''' 
						WHEN tempdb__CalculatedNumberOfTasks IS NULL THEN N'':?:'' 
						ELSE CONVERT(nvarchar(20), tempdb__CalculatedNumberOfTasks)' + 
							CASE WHEN @resource = N'N' THEN N'' 
							ELSE N'+ (CASE WHEN calc__node_info <> N''<placeholder>'' 
								THEN N'' - '' + calc__node_info 
								ELSE N'''' END)'
							END + N'
					END,
		[Progress] = ProgressPct + ProgressSessStat + ProgressRqstStat + 
				CASE WHEN session_id = -998 
					THEN N''THREADPOOL'' + 
						CASE WHEN calc__duration_ms < 10000 THEN  + N'' = '' + CONVERT(nvarchar(20),calc__duration_ms) + N'' ms'' 
						ELSE N''  --> '' + CONVERT(NVARCHAR(20), CONVERT(DECIMAL(21,1),calc__duration_ms/1000.)) + N''sec <--'' END
					WHEN NULLIF(wait_type,@lv__nullstring) IS NULL OR wait_type = N''<nullvalue>'' OR wait_type = N'''' OR session_id <= 0 THEN N''''
					ELSE ( wait_type + 
							CASE WHEN calc__tmr_wait > 1 or calc__sysspid_isinteresting=1 THEN (
									CASE WHEN ISNULL(rqst__wait_time,0) < 10000
										THEN N'' = '' + CONVERT(NVARCHAR(20), ISNULL(rqst__wait_time,0)) + N''ms'' 
										ELSE N''  --> '' + CONVERT(NVARCHAR(20), CONVERT(DECIMAL(21,1),ISNULL(rqst__wait_time,0)/1000.)) + N''sec <--''
									END)
								--WHEN calc__is_compiling = CONVERT(BIT,1) THEN N''<compiling>''
								WHEN ISNULL(wait_duration_ms,0) < 10000
									THEN N''  = '' + CONVERT(NVARCHAR(20), ISNULL(wait_duration_ms,0)) + N''ms''
								ELSE N''  --> '' + CONVERT(NVARCHAR(20), CONVERT(DECIMAL(21,1),ISNULL(wait_duration_ms,0)/1000.)) + N''sec <--''
							END
						)
					END,
		[QMem_MB] = CASE WHEN mgrant__granted_memory_kb IS NOT NULL 
						THEN convert(nvarchar(20), CONVERT(DECIMAL(21,3),mgrant__granted_memory_kb/1024.)) ' 
						+ CASE WHEN @resource = N'N' THEN N'' 
							ELSE N' + (CASE WHEN mgrant__used_memory_kb IS NOT NULL THEN N'' /us:'' + convert(nvarchar(20), CONVERT(DECIMAL(21,3),mgrant__used_memory_kb/1024.))
										ELSE N'''' END) '
							END + N'
						WHEN mgrant__requested_memory_kb IS NOT NULL THEN N''(Req)  '' + convert(nvarchar(20), CONVERT(DECIMAL(21,3),mgrant__requested_memory_kb/1024.))
					ELSE N''''
					END,
		[TempDB_MB] = CASE WHEN tempdb__usage <= 0 THEN N''''
						 WHEN tempdb__usage >= 1280000
							THEN convert(nvarchar(20),convert(money,tempdb__usage*8./1024.),1) 
						 ELSE CONVERT(NVARCHAR(20),CONVERT(DECIMAL(21,2),tempdb__usage*8./1024.))
						 END +
					CASE WHEN tempdb__alloc < 6400 THEN N'''' ELSE N'' /a: '' + CONVERT(NVARCHAR(20),CONVERT(DECIMAL(21,2),tempdb__alloc*8./1024.)) END,
		[cpu_time] = CASE WHEN session_id <= 0 THEN N''''
						WHEN request_id = @lv__nullsmallint
						THEN (CASE WHEN sess__cpu_time <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20),convert(money,sess__cpu_time),1) END) 
						ELSE (CASE WHEN rqst__cpu_time <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20), convert(money,rqst__cpu_time),1) END)
						END,
		[reads] = CASE WHEN session_id <= 0 THEN N''''
						WHEN request_id = @lv__nullsmallint
						THEN (CASE WHEN sess__reads <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20),CONVERT(money,sess__reads*8./1024.),1) END) 
						ELSE (CASE WHEN rqst__reads <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20),CONVERT(money,rqst__reads*8./1024.),1) END)
						END,
		[writes] = CASE WHEN session_id <= 0 THEN N''''
						WHEN request_id = @lv__nullsmallint
						THEN (CASE WHEN sess__writes <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20),CONVERT(money,sess__writes*8./1024.),1) END) 
						ELSE (CASE WHEN rqst__writes <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20), CONVERT(money,rqst__writes*8./1024.),1) END)
						END,
		';

		SET @lv__Formatted = @lv__Formatted + N'
		[logical_reads] = CASE WHEN session_id <= 0 THEN N''''
						WHEN request_id = @lv__nullsmallint
						THEN (CASE WHEN sess__logical_reads <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20),CONVERT(money,sess__logical_reads*8./1024.),1) END) 
						ELSE (CASE WHEN rqst__logical_reads <= 0 THEN N''''
								ELSE CONVERT(NVARCHAR(20), CONVERT(money,rqst__logical_reads*8./1024.),1) END)
						END,
		 ' + 
			CASE WHEN @batch = N'N' THEN N''
			ELSE N'		[BatchText] = CASE WHEN batch_xml IS NULL THEN N'''' ELSE batch_xml END,'
			END +

			CASE WHEN @plan IN (N'statement',N'full')
				THEN N'		[QPlan] = CASE WHEN query_plan_xml IS NULL THEN N'''' ELSE query_plan_xml END,'
			ELSE N''
			END + 

			CASE WHEN @ibuf = N'N' THEN N''
			ELSE N'		[InputBuffer] = CASE WHEN inputbuffer_xml IS NULL THEN N'''' ELSE inputbuffer_xml END,'
			END + N'
		[Cxs] = CASE WHEN context_switches_count <= 0 THEN N'''' ELSE CONVERT(NVARCHAR(20),context_switches_count) END,
		[Login] = CASE WHEN session_id <= 0 THEN N''''
					WHEN login_name IS NULL THEN ISNULL(original_login_name,N''<n/a>'')
						ELSE (CASE WHEN login_name <> ISNULL(original_login_name,''<null>'')
									THEN login_name + '' (orig: '' + ISNULL(original_login_name,''<null>'') + '')''
									ELSE login_name
									END)
						END,
		calc__record_priority
		' + 
		CASE WHEN @lv__IncludeTranDetails = 1 THEN N'
		,[trans] = CASE WHEN transtring IS NULL THEN N'''' ELSE
			CONVERT(XML, N''<?log'' + CASE WHEN ISNULL(trantotallogbytes,0) = 0 THEN N''0kb -- ''
										WHEN trantotallogbytes > 10485760 THEN REPLACE(CONVERT(NVARCHAR(20),CONVERT(DECIMAL(17,2),trantotallogbytes/1024./1024.)),N''.'',N''_'') + N''MB -- ''
										ELSE REPLACE(CONVERT(NVARCHAR(20),CONVERT(DECIMAL(17,2),trantotallogbytes/1024.)),N''.'',N''_'') + N''kb -- ''
										END + NCHAR(10) + NCHAR(13) + 
						ISNULL(transtring,N'''') + NCHAR(10) + NCHAR(13) + 
						N'' --?>'')
			END
		' ELSE N'' END + 

		CASE WHEN @attr = N'Y' THEN N'
		,Client = ISNULL(NULLIF(Client,@lv__nullstring),N'''')
		,IP = ISNULL(NULLIF(IP,@lv__nullstring),N'''')
		,Program = ISNULL(NULLIF(Program,@lv__nullstring),N'''')
		,SessAttr = CONVERT(xml,SessAttr)
		' ELSE N'' END + 

		CASE WHEN @resource = N'Y' THEN N'
		,Resources = CONVERT(xml,Resources)
		' ELSE N'' END +
		
		N'
	FROM basedata b
	)
	';

	IF @savespace = N'N'
	BEGIN
		SET @lv__ResultDynSQL = @lv__BaseSELECT1 + + @lv__BaseSELECT2 + @lv__BaseFROM + @lv__Formatted + 
		N'
		SELECT 
			[SPID] = session_id, 
			SPIDContext,
			--order_duration,
			Duration,
			[Blocker] = Blocking_SPID,
			[ObjectName] = Object_Name,
			[CurrentCommand] = Current_Command,
			[#Tasks],
			[Progress],
			[QueryMem_MB] = QMem_MB,
			[TempDB_MB] = Tempdb_MB,
			[CPUTime] = CASE WHEN cpu_time = N'''' THEN N'''' ELSE 
							SUBSTRING(cpu_time, 1, CHARINDEX(N''.'',cpu_time)-1) END,
			[PhysicalReads_MB] = reads,
			[LogicalReads_MB] = logical_reads,
			[Writes_MB] = writes
			' + CASE WHEN @lv__IncludeTranDetails = 1 THEN N',Transactions = trans' ELSE N'' END + 
			CASE WHEN @resource = N'Y' THEN N'
			,Resources
			' ELSE N'' END +
			CASE WHEN @batch = N'N' THEN N''
				ELSE N',BatchText'
				END + 
				CASE WHEN @plan IN (N'statement', N'full') THEN N',QueryPlan = QPlan' 
					ELSE N''
				END + 
				CASE WHEN @ibuf = N'N' THEN N''
				ELSE N',InputBuffer'
				END + N'
			,Login
			' + CASE WHEN @attr = N'Y' THEN N'
			,Client
			,IP
			,Program
			,[Attributes] = SessAttr' ELSE N'' END + N'
		FROM formatteddata
		ORDER BY calc__record_priority ASC, order_duration DESC
		';
	END 
	ELSE
	BEGIN
		--use short column names
		SET @lv__ResultDynSQL = @lv__BaseSELECT1 + + @lv__BaseSELECT2 + @lv__BaseFROM + @lv__Formatted + 
		N'
		SELECT 
			[SPID] = session_id, 
			[Cntxt] = SPIDContext,
			[Dur] = Duration,
			[Blk] = Blocking_SPID,
			[OName] = Object_Name,
			[Cmd] = Current_Command,
			[#T] = [#Tasks],
			[Progress],
			[QMem] = QMem_MB,
			[TDB] = Tempdb_MB,
			[CPU] = CASE WHEN cpu_time = N'''' THEN N'''' ELSE 
						SUBSTRING(cpu_time, 1, CHARINDEX(N''.'',cpu_time)-1) END,
			[PhyRd] = reads,
			[LRd] = logical_reads,
			[Wri] = writes
			' + CASE WHEN @lv__IncludeTranDetails = 1 THEN N',Xact = trans' ELSE N'' END + 
			CASE WHEN @resource = N'Y' THEN N'
			,[Res] = Resources
			' ELSE N'' END +
			CASE WHEN @batch = N'N' THEN N''
				ELSE N',[BTxt] = BatchText'
				END + 
				CASE WHEN @plan IN (N'statement', N'full') THEN N',QPlan = QPlan' 
					ELSE N''
				END + 
				CASE WHEN @ibuf = N'N' THEN N''
				ELSE N',[IB] = InputBuffer'
				END + N'
			,Login
			' + CASE WHEN @attr = N'Y' THEN N'
			,Client
			,IP
			,Program
			,[Attr] = SessAttr' ELSE N'' END + N'
		FROM formatteddata
		ORDER BY calc__record_priority ASC, order_duration DESC
		';
	END

	/*
	DECLARE @lv__DebugBase NVARCHAR(MAX);
	SET @lv__DebugBase = @lv__BaseSELECT1 + @lv__BaseSELECT2 + @lv__BaseFROM + N'
	SELECT * FROM basedata';

	print SUBSTRING(@lv__DebugBase,1,4000);
	print SUBSTRING(@lv__DebugBase,4001,8000);
	print SUBSTRING(@lv__DebugBase,8001,12000);

	EXEC sp_executesql @stmt=@lv__DebugBase, @params=N'@st1 DATETIME, @st2 DATETIME', @st1=@hctUTC, @st2=@hctUTC;

	return 0;
	*/
	/*
	print len(@lv__ResultDynSQL);
	print datalength(@lv__ResultDynSQL);
	print SUBSTRING(@lv__ResultDynSQL,1,4000);
	print SUBSTRING(@lv__ResultDynSQL,4001,8000);
	print SUBSTRING(@lv__ResultDynSQL,8001,12000);
	print SUBSTRING(@lv__ResultDynSQL,12001,16000);
	print SUBSTRING(@lv__ResultDynSQL,16001,20000);
	print SUBSTRING(@lv__ResultDynSQL,20001,24000);
	print SUBSTRING(@lv__ResultDynSQL,24001,28000);
	--return 0;
	*/
	

	EXEC sp_executesql @stmt=@lv__ResultDynSQL, 
		@params=N'@lv__nullsmallint SMALLINT, @lv__nullint INT, @lv__nullstring NVARCHAR(8), @tvar DATETIME, @init TINYINT', 
		@lv__nullsmallint=@lv__nullsmallint, @lv__nullint = @lv__nullint, @lv__nullstring = @lv__nullstring, @tvar=@hctUTC, @init=@init;

	RETURN 0;
END
GO