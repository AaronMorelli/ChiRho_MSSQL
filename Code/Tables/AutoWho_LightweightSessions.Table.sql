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

	FILE NAME: AutoWho_LightweightSessions.Table.sql

	TABLE NAME: AutoWho_LightweightSessions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds data from a number of session-based DMVs when
	the @@CHIRHO_SCHEMA@@.AutoWho_Collector proc runs longer than a certain duration or fails.
	It represents an attempt to just grab a dump of the contents of the DMVs
	using loop joins (i.e. no mem requirements) if the more complicated logic
	of the Collector doesn't work or doesn't work quickly.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LightweightSessions(
	[SPIDCaptureTime] [datetime] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,		--unlike SAR, we need a UTC field because lightweight captures are not recorded in @@CHIRHO_SCHEMA@@.AutoWho_CaptureTime
	[sess__session_id] [smallint] NOT NULL,
	[sess__login_time] [datetime] NOT NULL,
	[sess__host_name] [nvarchar](128) NULL,
	[sess__program_name] [nvarchar](128) NULL,
	[sess__host_process_id] [int] NULL,
	[sess__client_version] [int] NULL,
	[sess__client_interface_name] [nvarchar](32) NULL,
	[sess__security_id] [varbinary](85) NOT NULL,
	[sess__login_name] [nvarchar](128) NOT NULL,
	[sess__nt_domain] [nvarchar](128) NULL,
	[sess__nt_user_name] [nvarchar](128) NULL,
	[sess__status] [nvarchar](30) NOT NULL,
	[sess__context_info] [varbinary](128) NULL,
	[sess__cpu_time] [int] NOT NULL,
	[sess__memory_usage] [int] NOT NULL,
	[sess__total_scheduled_time] [int] NOT NULL,
	[sess__total_elapsed_time] [int] NOT NULL,
	[sess__endpoint_id] [int] NOT NULL,
	[sess__last_request_start_time] [datetime] NOT NULL,
	[sess__last_request_end_time] [datetime] NULL,
	[sess__reads] [bigint] NOT NULL,
	[sess__writes] [bigint] NOT NULL,
	[sess__logical_reads] [bigint] NOT NULL,
	[sess__is_user_process] [bit] NOT NULL,
	[sess__text_size] [int] NOT NULL,
	[sess__language] [nvarchar](128) NULL,
	[sess__date_format] [nvarchar](3) NULL,
	[sess__date_first] [smallint] NOT NULL,
	[sess__quoted_identifier] [bit] NOT NULL,
	[sess__arithabort] [bit] NOT NULL,
	[sess__ansi_null_dflt_on] [bit] NOT NULL,
	[sess__ansi_defaults] [bit] NOT NULL,
	[sess__ansi_warnings] [bit] NOT NULL,
	[sess__ansi_padding] [bit] NOT NULL,
	[sess__ansi_nulls] [bit] NOT NULL,
	[sess__concat_null_yields_null] [bit] NOT NULL,
	[sess__transaction_isolation_level] [smallint] NOT NULL,
	[sess__lock_timeout] [int] NOT NULL,
	[sess__deadlock_priority] [int] NOT NULL,
	[sess__row_count] [bigint] NOT NULL,
	[sess__prev_error] [int] NOT NULL,
	[sess__original_security_id] [varbinary](85) NOT NULL,
	[sess__original_login_name] [nvarchar](128) NOT NULL,
	[sess__last_successful_logon] [datetime] NULL,
	[sess__last_unsuccessful_logon] [datetime] NULL,
	[sess__unsuccessful_logons] [bigint] NULL,
	[sess__group_id] [int] NOT NULL,
	[sess__database_id] [smallint] NULL,
	[sess__authenticating_database_id] [int] NULL,
	[sess__open_transaction_count] [int] NULL,
	[conn__most_recent_session_id] [int] NULL,
	[conn__connect_time] [datetime] NULL,
	[conn__net_transport] [nvarchar](40) NULL,
	[conn__protocol_type] [nvarchar](40) NULL,
	[conn__protocol_version] [int] NULL,
	[conn__endpoint_id] [int] NULL,
	[conn__encrypt_option] [nvarchar](40) NULL,
	[conn__auth_scheme] [nvarchar](40) NULL,
	[conn__node_affinity] [smallint] NULL,
	[conn__num_reads] [int] NULL,
	[conn__num_writes] [int] NULL,
	[conn__last_read] [datetime] NULL,
	[conn__last_write] [datetime] NULL,
	[conn__net_packet_size] [int] NULL,
	[conn__client_net_address] [varchar](48) NULL,
	[conn__client_tcp_port] [int] NULL,
	[conn__local_net_address] [varchar](48) NULL,
	[conn__local_tcp_port] [int] NULL,
	[conn__connection_id] [uniqueidentifier] NULL,
	[conn__parent_connection_id] [uniqueidentifier] NULL,
	[conn__most_recent_sql_handle] [varbinary](64) NULL,
	[rqst__request_id] [int] NULL,
	[rqst__start_time] [datetime] NULL,
	[rqst__status] [nvarchar](30) NULL,
	[rqst__command] [nvarchar](32) NULL,
	[rqst__sql_handle] [varbinary](64) NULL,
	[rqst__statement_start_offset] [int] NULL,
	[rqst__statement_end_offset] [int] NULL,
	[rqst__plan_handle] [varbinary](64) NULL,
	[rqst__database_id] [smallint] NULL,
	[rqst__user_id] [int] NULL,
	[rqst__connection_id] [uniqueidentifier] NULL,
	[rqst__blocking_session_id] [smallint] NULL,
	[rqst__wait_type] [nvarchar](60) NULL,
	[rqst__wait_time] [int] NULL,
	[rqst__last_wait_type] [nvarchar](60) NULL,
	[rqst__wait_resource] [nvarchar](256) NULL,
	[rqst__open_transaction_count] [int] NULL,
	[rqst__open_resultset_count] [int] NULL,
	[rqst__transaction_id] [bigint] NULL,
	[rqst__context_info] [varbinary](128) NULL,
	[rqst__percent_complete] [real] NULL,
	[rqst__estimated_completion_time] [bigint] NULL,
	[rqst__cpu_time] [int] NULL,
	[rqst__total_elapsed_time] [int] NULL,
	[rqst__scheduler_id] [int] NULL,
	[rqst__task_address] [varbinary](8) NULL,
	[rqst__reads] [bigint] NULL,
	[rqst__writes] [bigint] NULL,
	[rqst__logical_reads] [bigint] NULL,
	[rqst__text_size] [int] NULL,
	[rqst__language] [nvarchar](128) NULL,
	[rqst__date_format] [nvarchar](3) NULL,
	[rqst__date_first] [smallint] NULL,
	[rqst__quoted_identifier] [bit] NULL,
	[rqst__arithabort] [bit] NULL,
	[rqst__ansi_null_dflt_on] [bit] NULL,
	[rqst__ansi_defaults] [bit] NULL,
	[rqst__ansi_warnings] [bit] NULL,
	[rqst__ansi_padding] [bit] NULL,
	[rqst__ansi_nulls] [bit] NULL,
	[rqst__concat_null_yields_null] [bit] NULL,
	[rqst__transaction_isolation_level] [smallint] NULL,
	[rqst__lock_timeout] [int] NULL,
	[rqst__deadlock_priority] [int] NULL,
	[rqst__row_count] [bigint] NULL,
	[rqst__prev_error] [int] NULL,
	[rqst__nest_level] [int] NULL,
	[rqst__granted_query_memory] [int] NULL,
	[rqst__executing_managed_code] [bit] NULL,
	[rqst__group_id] [int] NULL,
	[rqst__query_hash] [binary](8) NULL,
	[rqst__query_plan_hash] [binary](8) NULL,
	[rqst__statement_sql_handle] [varbinary](64) NULL,
	[rqst__statement_context_id] [bigint] NULL,
	[sess__internal_objects_alloc_page_count] [bigint] NULL,
	[sess__internal_objects_dealloc_page_count] [bigint] NULL,
	[sess__user_objects_alloc_page_count] [bigint] NULL,
	[sess__user_objects_dealloc_page_count] [bigint] NULL,
	[mgrant__scheduler_id] [int] NULL,
	[mgrant__dop] [smallint] NULL,
	[mgrant__request_time] [datetime] NULL,
	[mgrant__grant_time] [datetime] NULL,
	[mgrant__requested_memory_kb] [bigint] NULL,
	[mgrant__granted_memory_kb] [bigint] NULL,
	[mgrant__required_memory_kb] [bigint] NULL,
	[mgrant__used_memory_kb] [bigint] NULL,
	[mgrant__max_used_memory_kb] [bigint] NULL,
	[mgrant__query_cost] [float] NULL,
	[mgrant__timeout_sec] [int] NULL,
	[mgrant__resource_semaphore_id] [smallint] NULL,
	[mgrant__queue_id] [smallint] NULL,
	[mgrant__wait_order] [int] NULL,
	[mgrant__is_next_candidate] [bit] NULL,
	[mgrant__wait_time_ms] [bigint] NULL,
	[mgrant__plan_handle] [varbinary](64) NULL,
	[mgrant__sql_handle] [varbinary](64) NULL,
	[mgrant__group_id] [int] NULL,
	[mgrant__pool_id] [int] NULL,
	[mgrant__is_small] [bit] NULL,
	[mgrant__ideal_memory_kb] [bigint] NULL
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
