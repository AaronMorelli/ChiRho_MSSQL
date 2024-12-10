SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [AutoWho].[ViewCurrentSessions] 
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

	FILE NAME: AutoWho_ViewCurrentSessions.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ViewCurrentSessions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Called by the sp_XR_SessionViewer user-facing procedure when current DMV data (that is analogous
		to the AutoWho/ViewHistoricalSessions data) is requested. 
		The logic below creates temp tables that look like AutoWho base tables, and relies on the Collector and 
		PostProcessor to modify their logic and operate on these temp tables rather than the base AutoWho tables.


	FUTURE ENHANCEMENTS: 


To Execute
------------------------
Should not be called by programs or used regularly. Only call when debugging.


*/
(
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

		--AutoWho option values. We only need to pull some from the AutoWho.Options table; others are set
		-- based on the parms to sp_XR_SessionViewer. 
		@opt__IncludeIdleWithTran				NVARCHAR(5),
		@opt__IncludeIdleWithoutTran			NVARCHAR(5),
		@opt__DurationFilter					INT,
		@opt__IncludeDBs						NVARCHAR(500),	
		@opt__ExcludeDBs						NVARCHAR(500),	
		@opt__HighTempDBThreshold				INT,
		@opt__CollectSystemSpids				NCHAR(1),	
		@opt__HideSelf							NCHAR(1),

		@opt__ObtainBatchText					NCHAR(1),	
		@opt__ParallelWaitsThreshold			INT,
		@opt__ObtainLocksForBlockRelevantThreshold	INT,
		@opt__ObtainQueryPlanForStatement		NCHAR(1),	
		@opt__ObtainQueryPlanForBatch			NCHAR(1),
		@opt__InputBufferThreshold				INT,
		@opt__BlockingChainThreshold			INT,
		@opt__BlockingChainDepth				TINYINT,
		@opt__TranDetailsThreshold				INT,
		@opt__ResolvePageLatches				NCHAR(1),
		@opt__Enable8666						NCHAR(1),
		@opt__ThresholdFilterRefresh			INT,
		@opt__QueryPlanThreshold				INT,
		@opt__QueryPlanThresholdBlockRel		INT,


		--Collector parms
		@lv__TempDBCreateTime		DATETIME,
		@lv__NumSPIDsCaptured		INT,
		@lv__DBInclusionsExist		BIT,
		@lv__DBExclusionsExist		BIT,
		@lv__SPIDInclusionsExist	BIT,
		@lv__SPIDExclusionsExist	BIT,

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

	DECLARE @FilterTVP AS CoreXRFiltersType;
	/*
	CREATE TYPE CoreXRFiltersType AS TABLE 
	(
		FilterType TINYINT NOT NULL, 
			--0 DB inclusion
			--1 DB exclusion
			--128 threshold filtering (spids that should not be counted against the various thresholds that trigger auxiliary data collection)
			--down the road, more to come (TODO: maybe filter by logins down the road?)
		FilterID INT NOT NULL, 
		FilterName NVARCHAR(255)
	)
	*/

	DECLARE @SessionFilters AS CoreXRFiltersType;
		-- we put session inclusion (code = 2) and exclusion (code = 3) into this table,
		-- and then put the exclusion rows into the above filter table as threshold filters
		-- so they do not trigger longer-running Collector statements needlessly.

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


	IF ISNULL(@db,N'') = N''
	BEGIN
		SET @lv__DBInclusionsExist = 0;		--this flag (only for inclusions) is a perf optimization
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO @FilterTVP (FilterType, FilterID, FilterName)
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
				SET @lv__DBInclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @lv__DBInclusionsExist = 1;
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
		SET @lv__DBExclusionsExist = 0;
	END
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO @FilterTVP (FilterType, FilterID, FilterName)
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
				SET @lv__DBExclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @lv__DBExclusionsExist = 1;
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
		SET @lv__SPIDInclusionsExist = 0;		--this flag (only for inclusions) is a perf optimization
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO @SessionFilters (FilterType, FilterID, FilterName)
				SELECT 2, SS.spids, NULL
				FROM (SELECT [spids] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @spid,  N',' , N'</M><M>') + N'</M>' AS XML) AS spidlist) xmlparse
					CROSS APPLY spidlist.nodes(N'/M') Split(a)
					) SS
				WHERE SS.spids <> N'';

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @lv__SPIDInclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @lv__SPIDInclusionsExist = 1;
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
		SET @lv__SPIDExclusionsExist = 0;
	END 
	ELSE
	BEGIN
		BEGIN TRY 
			INSERT INTO @SessionFilters (FilterType, FilterID, FilterName)
				SELECT 3, SS.spids, NULL
				FROM (SELECT [spids] = LTRIM(RTRIM(Split.a.value(N'.', 'NVARCHAR(512)')))
					FROM (SELECT CAST(N'<M>' + REPLACE( @xspid,  N',' , N'</M><M>') + N'</M>' AS XML) AS spidlist) xmlparse
					CROSS APPLY spidlist.nodes(N'/M') Split(a)
					) SS
				WHERE SS.spids <> N'';

			SET @lv__ScratchInt = @@ROWCOUNT;

			IF @lv__ScratchInt = 0
			BEGIN
				SET @lv__SPIDExclusionsExist = 0;
			END
			ELSE
			BEGIN
				SET @lv__SPIDExclusionsExist = 1;
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

	IF EXISTS (SELECT * FROM @FilterTVP dbs 
					INNER JOIN @FilterTVP xdbs
						ON dbs.FilterID = xdbs.FilterID
						AND dbs.FilterType = 0
						AND xdbs.FilterType = 1
			)
	BEGIN
		RAISERROR('A database cannot be specified in both the @dbs and @xdbs filter parameters.', 16, 1);
		RETURN -1;
	END

	IF EXISTS (SELECT * FROM @SessionFilters spid 
					INNER JOIN @SessionFilters xspid
						ON spid.FilterID = xspid.FilterID
						AND spid.FilterType = 2
						AND xspid.FilterType = 3
			)
	BEGIN
		RAISERROR('A session ID cannot be specified in both the @spids and @xspids filter parameters.', 16, 1);
		RETURN -1;
	END

	--Session exclusions are passed to the collector as threshold-ignore spids
	INSERT INTO @FilterTVP (FilterType, FilterID)
	SELECT 128, s.FilterID
	FROM @SessionFilters s
	WHERE FilterType = 3
	;


	--We define temp table equivalents to SAR, TAW, BlockingGraphs, LockDetails, and TransactionDetails
	-- (For now, let's leave the exception logic pointing to the permanent SARException and TAWExeption tables)
	CREATE TABLE #VwCS_SessionsAndRequests (
		[SPIDCaptureTime] [datetime] NOT NULL,
		[session_id] [smallint] NOT NULL,
		[request_id] [smallint] NOT NULL,
		[TimeIdentifier] [datetime] NOT NULL,
		[sess__login_time] [datetime] NULL,
		[sess__host_process_id] [int] NULL,
		[sess__status_code] [tinyint] NULL,
		[sess__cpu_time] [int] NULL,
		[sess__memory_usage] [int] NULL,
		[sess__total_scheduled_time] [int] NULL,
		[sess__total_elapsed_time] [int] NULL,
		[sess__last_request_start_time] [datetime] NULL,
		[sess__last_request_end_time] [datetime] NULL,
		[sess__reads] [bigint] NULL,
		[sess__writes] [bigint] NULL,
		[sess__logical_reads] [bigint] NULL,
		[sess__is_user_process] [bit] NULL,
		[sess__lock_timeout] [int] NULL,
		[sess__row_count] [bigint] NULL,
		[sess__open_transaction_count] [int] NULL,
		[sess__database_id] [smallint] NULL,
		[sess__FKDimLoginName] [smallint] NULL,
		[sess__FKDimSessionAttribute] [smallint] NULL,
		[conn__connect_time] [datetime] NULL,
		[conn__client_tcp_port] [int] NULL,
		[conn__FKDimNetAddress] [smallint] NULL,
		[conn__FKDimConnectionAttribute] [smallint] NULL,
		[rqst__start_time] [datetime] NULL,
		[rqst__status_code] [tinyint] NULL,
		[rqst__blocking_session_id] [smallint] NULL,
		[rqst__wait_time] [int] NULL,
		[rqst__wait_resource] [nvarchar](256) NULL,
		[rqst__open_transaction_count] [int] NULL,
		[rqst__open_resultset_count] [int] NULL,
		[rqst__percent_complete] [real] NULL,
		[rqst__cpu_time] [int] NULL,
		[rqst__total_elapsed_time] [int] NULL,
		[rqst__scheduler_id] [int] NULL,
		[rqst__reads] [bigint] NULL,
		[rqst__writes] [bigint] NULL,
		[rqst__logical_reads] [bigint] NULL,
		[rqst__transaction_isolation_level] [tinyint] NULL,
		[rqst__lock_timeout] [int] NULL,
		[rqst__deadlock_priority] [smallint] NULL,
		[rqst__row_count] [bigint] NULL,
		[rqst__granted_query_memory] [int] NULL,
		[rqst__executing_managed_code] [bit] NULL,
		[rqst__group_id] [int] NULL,
		[rqst__FKDimCommand] [smallint] NULL,
		[rqst__FKDimWaitType] [smallint] NULL,
		[tempdb__sess_user_objects_alloc_page_count] [bigint] NULL,
		[tempdb__sess_user_objects_dealloc_page_count] [bigint] NULL,
		[tempdb__sess_internal_objects_alloc_page_count] [bigint] NULL,
		[tempdb__sess_internal_objects_dealloc_page_count] [bigint] NULL,
		[tempdb__task_user_objects_alloc_page_count] [bigint] NULL,
		[tempdb__task_user_objects_dealloc_page_count] [bigint] NULL,
		[tempdb__task_internal_objects_alloc_page_count] [bigint] NULL,
		[tempdb__task_internal_objects_dealloc_page_count] [bigint] NULL,
		[tempdb__CalculatedNumberOfTasks] [smallint] NULL,
		[mgrant__request_time] [datetime] NULL,
		[mgrant__grant_time] [datetime] NULL,
		[mgrant__requested_memory_kb] [bigint] NULL,
		[mgrant__required_memory_kb] [bigint] NULL,
		[mgrant__granted_memory_kb] [bigint] NULL,
		[mgrant__used_memory_kb] [bigint] NULL,
		[mgrant__max_used_memory_kb] [bigint] NULL,
		[mgrant__dop] [smallint] NULL,
		[calc__record_priority] [tinyint] NULL,
		[calc__is_compiling] [bit] NULL,
		[calc__duration_ms] [bigint] NULL,
		[calc__blocking_session_id] [smallint] NULL,
		[calc__block_relevant] [tinyint] NULL,
		[calc__wait_details] [nvarchar](max) NULL,
		[calc__return_to_user] [smallint] NULL,
		[calc__is_blocker] [bit] NULL,
		[calc__sysspid_isinteresting] [bit] NULL,
		[calc__tmr_wait] [tinyint] NULL,
		[calc__threshold_ignore] [bit] NULL,
		[calc__node_info] [nvarchar](40) NOT NULL,
		[calc__status_info] [nvarchar](20) NOT NULL,
		[FKSQLStmtStoreID] [bigint] NULL,
		[FKSQLBatchStoreID] [bigint] NULL,
		[FKInputBufferStoreID] [bigint] NULL,
		[FKQueryPlanBatchStoreID] [bigint] NULL,
		[FKQueryPlanStmtStoreID] [bigint] NULL
	);


	CREATE TABLE #VwCS_TasksAndWaits (
		[SPIDCaptureTime] [datetime] NOT NULL,
		[task_address] [varbinary](8) NOT NULL,
		[parent_task_address] [varbinary](8) NULL,
		[session_id] [smallint] NOT NULL,
		[request_id] [smallint] NOT NULL,
		[exec_context_id] [smallint] NOT NULL,
		[tstate] [nchar](1) NOT NULL,
		[scheduler_id] [int] NULL,
		[context_switches_count] [bigint] NOT NULL,
		[FKDimWaitType] [smallint] NOT NULL,
		[wait_duration_ms] [bigint] NOT NULL,
		[wait_special_category] [tinyint] NOT NULL,
		[wait_order_category] [tinyint] NOT NULL,
		[wait_special_number] [int] NOT NULL,
		[wait_special_tag] [nvarchar](100) NOT NULL,
		[task_priority] [int] NOT NULL,
		[blocking_task_address] [varbinary](8) NULL,
		[blocking_session_id] [smallint] NOT NULL,
		[blocking_exec_context_id] [smallint] NOT NULL,
		[resource_description] [nvarchar](3072) NULL,
		[resource_dbid] [int] NOT NULL,
		[resource_associatedobjid] [bigint] NOT NULL,
		[cxp_wait_direction] [tinyint] NOT NULL,
		[resolution_successful] [bit] NOT NULL,
		[resolved_name] [nvarchar](256) NULL
	);

	CREATE TABLE #VwCS_BlockingGraphs (
		[SPIDCaptureTime] [datetime] NOT NULL,
		[session_id] [smallint] NOT NULL,
		[request_id] [smallint] NOT NULL,
		[exec_context_id] [smallint] NULL,
		[calc__blocking_session_Id] [smallint] NULL,
		[wait_type] [nvarchar](60) NULL,
		[wait_duration_ms] [bigint] NULL,
		[resource_description] [nvarchar](500) NULL,
		[FKInputBufferStoreID] [bigint] NULL,
		[FKSQLStmtStoreID] [bigint] NULL,
		[sort_value] [nvarchar](400) NULL,
		[block_group] [smallint] NULL,
		[levelindc] [smallint] NOT NULL,
		[rn] [smallint] NOT NULL
	);

	CREATE TABLE #VwCS_LockDetails (
		[SPIDCaptureTime] [datetime] NOT NULL,
		[request_session_id] [smallint] NOT NULL,
		[request_request_id] [smallint] NULL,
		[TimeIdentifier] [datetime] NOT NULL,
		[request_exec_context_id] [smallint] NULL,
		[request_owner_type] [tinyint] NULL,
		[request_owner_id] [bigint] NULL,
		[request_owner_guid] [nvarchar](40) NULL,
		[resource_type] [nvarchar](60) NULL,
		[resource_subtype] [nvarchar](60) NULL,
		[resource_database_id] [int] NULL,
		[resource_description] [nvarchar](256) NULL,
		[resource_associated_entity_id] [bigint] NULL,
		[resource_lock_partition] [int] NULL,
		[request_mode] [nvarchar](60) NULL,
		[request_type] [nvarchar](60) NULL,
		[request_status] [nvarchar](60) NULL,
		[RecordCount] [bigint] NULL
	);

	CREATE TABLE #VwCS_TransactionDetails (
		[SPIDCaptureTime] [datetime] NOT NULL,
		[session_id] [smallint] NOT NULL,
		[TimeIdentifier] [datetime] NOT NULL,
		[dtat_transaction_id] [bigint] NOT NULL,
		[dtat_name] [nvarchar](32) NULL,
		[dtat_transaction_begin_time] [datetime] NULL,
		[dtat_transaction_type] [smallint] NULL,
		[dtat_transaction_uow] [uniqueidentifier] NULL,
		[dtat_transaction_state] [smallint] NULL,
		[dtat_dtc_state] [smallint] NULL,
		[dtst_enlist_count] [smallint] NULL,
		[dtst_is_user_transaction] [bit] NULL,
		[dtst_is_local] [bit] NULL,
		[dtst_is_enlisted] [bit] NULL,
		[dtst_is_bound] [bit] NULL,
		[dtdt_database_id] [int] NULL,
		[dtdt_database_transaction_begin_time] [datetime] NULL,
		[dtdt_database_transaction_type] [smallint] NULL,
		[dtdt_database_transaction_state] [smallint] NULL,
		[dtdt_database_transaction_log_record_count] [bigint] NULL,
		[dtdt_database_transaction_log_bytes_used] [bigint] NULL,
		[dtdt_database_transaction_log_bytes_reserved] [bigint] NULL,
		[dtdt_database_transaction_log_bytes_used_system] [int] NULL,
		[dtdt_database_transaction_log_bytes_reserved_system] [int] NULL,
		[dtasdt_tran_exists] [bit] NULL,
		[dtasdt_transaction_sequence_num] [bigint] NULL,
		[dtasdt_commit_sequence_num] [bigint] NULL,
		[dtasdt_is_snapshot] [smallint] NULL,
		[dtasdt_first_snapshot_sequence_num] [bigint] NULL,
		[dtasdt_max_version_chain_traversed] [int] NULL,
		[dtasdt_average_version_chain_traversed] [real] NULL,
		[dtasdt_elapsed_time_seconds] [bigint] NULL
	);

	--Now that temp tables are defined, let's call the collector, telling it to populate the temp tables instead of the standard
	-- AutoWho tables.
	SET @lv__TempDBCreateTime = (select d.create_date from sys.databases d where d.name = N'tempdb');

	--0 = Running only, 1 = Active + idle-open-tran, 2 = everything
	IF @activity = 0
	BEGIN
		SET @opt__IncludeIdleWithTran = N'N';
		SET @opt__IncludeIdleWithoutTran = N'N';
	END
	ELSE IF @activity = 1
	BEGIN
		SET @opt__IncludeIdleWithTran = N'Y';
		SET @opt__IncludeIdleWithoutTran = N'N';
	END
	ELSE IF @activity = 2
	BEGIN
		SET @opt__IncludeIdleWithTran = N'Y';
		SET @opt__IncludeIdleWithoutTran = N'Y';
	END

	IF @plan = N'none'
	BEGIN
		SET @opt__ObtainQueryPlanForStatement = N'N';
		SET @opt__ObtainQueryPlanForBatch = N'N';
		SET @opt__QueryPlanThreshold = 999999;
		SET @opt__QueryPlanThresholdBlockRel = 999999;
	END
	ELSE IF @plan = N'statement'
	BEGIN
		SET @opt__ObtainQueryPlanForStatement = N'Y';
		SET @opt__ObtainQueryPlanForBatch = N'N';
		SET @opt__QueryPlanThreshold = 0;
		SET @opt__QueryPlanThresholdBlockRel = 0;
	END
	ELSE IF @plan = N'full'
	BEGIN
		SET @opt__ObtainQueryPlanForStatement = N'N';
		SET @opt__ObtainQueryPlanForBatch = N'Y';
		SET @opt__QueryPlanThreshold = 0;
		SET @opt__QueryPlanThresholdBlockRel = 0;
	END

	IF @ibuf = N'Y'
	BEGIN
		SET @opt__InputBufferThreshold = 0;
	END
	ELSE
	BEGIN
		SET @opt__InputBufferThreshold = 999999;
	END

	SET @opt__BlockingChainDepth = @bchain;
	IF @bchain = 0
	BEGIN
		SET @opt__BlockingChainThreshold = 999999;
	END
	ELSE
	BEGIN
		SET @opt__BlockingChainThreshold = 0;
	END

	IF @tran = N'Y'
	BEGIN
		SET @opt__TranDetailsThreshold = 0;
	END
	ELSE
	BEGIN
		SET @opt__TranDetailsThreshold = 999999;
	END

	SELECT 
		@opt__DurationFilter					= @dur,
		@opt__HighTempDBThreshold				= [HighTempDBThreshold],
		@opt__CollectSystemSpids				= [CollectSystemSpids],
		@opt__HideSelf							= [HideSelf],

		@opt__ObtainBatchText					= @batch,
		@opt__ParallelWaitsThreshold			= [ParallelWaitsThreshold],		--for now, use the system value. May revisit if this is super annoying.
		@opt__ObtainLocksForBlockRelevantThreshold = [ObtainLocksForBlockRelevantThreshold],		--ditto
		@opt__Enable8666						= [Enable8666]
	FROM AutoWho.Options o
	;

	/*
	Still TODO:
		- Add a param for the Collector proc, of course!

		- Do we need to do anything with the app lock?
			EXEC sp_releaseapplock @Resource = 'AutoWhoBackgroundTrace', @LockOwner = 'Session';

	Lower priority:
		- should we let the user recompile the collector proc? (via a directive)


	EXEC AutoWho.Collector
		@TempDBCreateTime = @lv__TempDBCreateTime,
		@IncludeIdleWithTran = @opt__IncludeIdleWithTran,
		@IncludeIdleWithoutTran = @opt__IncludeIdleWithoutTran,
		@DurationFilter = @opt__DurationFilter, 
		@FilterTable = @FilterTVP, 
		@DBInclusionsExist = @lv__DBInclusionsExist, 
		@HighTempDBThreshold = @opt__HighTempDBThreshold, 
		@CollectSystemSpids = @opt__CollectSystemSpids, 
		@HideSelf = @opt__HideSelf, 

		@ObtainBatchText = @opt__ObtainBatchText,
		@QueryPlanThreshold = @opt__QueryPlanThreshold,
		@QueryPlanThresholdBlockRel = @opt__QueryPlanThresholdBlockRel,
		@ParallelWaitsThreshold = @opt__ParallelWaitsThreshold, 
		@ObtainLocksForBlockRelevantThreshold = @opt__ObtainLocksForBlockRelevantThreshold,
		@ObtainQueryPlanForStatement = @opt__ObtainQueryPlanForStatement, 
		@ObtainQueryPlanForBatch = @opt__ObtainQueryPlanForBatch,
		@InputBufferThreshold = @opt__InputBufferThreshold, 
		@BlockingChainThreshold = @opt__BlockingChainThreshold,
		@BlockingChainDepth = @opt__BlockingChainDepth, 
		@TranDetailsThreshold = @opt__TranDetailsThreshold,

		@DebugSpeed = N'N',
		@SaveBadDims = N'N',
		@NumSPIDs = @lv__NumSPIDsCaptured OUTPUT
		;
	*/

	/*

				WITH RECOMPILE;


	EXEC AutoWho.Collector @TempDBCreateTime = @lv__TempDBCreateTime,
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
		--@ResolvePageLatches					NCHAR(1),		--Y/N

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
		@NumSPIDs							INT OUTPUT
	;
	*/


	/* TODO: This is the part of the ViewHistoricalSpids proc that I stopped at
		Once we have temp tables, and they've been populated by the Collector and updated
		by the post-processor (the post-processor is conditional) then we can scan
		the BChain, Lock, and Tran tables to see if there are any records present
		and populate the 3 variables.


	--Our final result set's top row indicates whether the BGraph, LockDetails, and TranDetails data was collected at this @hct, so that
	-- the user knows whether inspecting that data is even an option. Simple 1/0 flags are stored in @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary by the 
	-- AutoWho.PopulateCaptureSummary table (which looks at the base data in the AutoWho tables to determine these bit flag values). 
	-- Thus, pull those values
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
			WHERE cs.SPIDCaptureTime = @hct
		) xapp1;

	*/

	RETURN 0;
END

GO