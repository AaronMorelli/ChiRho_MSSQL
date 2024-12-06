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

	FILE NAME: AutoWho_SessionsAndRequests.Table.sql

	TABLE NAME: AutoWho_SessionsAndRequests

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds the core "SAR" data set collected by @@CHIRHO_SCHEMA@@.AutoWho_Collector

*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests (
	[CollectionInitiatorID] [tinyint] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,
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
	[rqst__query_hash] [binary](8) NULL,
	[rqst__query_plan_hash] [binary](8) NULL,
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
	[calc__status_info] [nvarchar](40) NOT NULL,
	[FKSQLStmtStoreID] [bigint] NULL,
	[FKSQLBatchStoreID] [bigint] NULL,
	[FKInputBufferStoreID] [bigint] NULL,
	[FKQueryPlanBatchStoreID] [bigint] NULL,
	[FKQueryPlanStmtStoreID] [bigint] NULL
) ON [PRIMARY]
GO
CREATE CLUSTERED INDEX [CL_CapTime_Sess_Rqst] ON @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests
(
	[CollectionInitiatorID] ASC,
	[UTCCaptureTime] ASC,
	[session_id] ASC,
	[request_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO