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

	FILE NAME: ServerEye_dm_exec_query_resource_semaphores.Table.sql

	TABLE NAME: ServerEye_dm_exec_query_resource_semaphores

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_exec_query_resource_semaphores (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_exec_query_resource_semaphores(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[pool_id] [int] NOT NULL,
	[resource_semaphore_id] [smallint] NOT NULL,
	[target_memory_kb] [bigint] NULL,
	[max_target_memory_kb] [bigint] NULL,
	[total_memory_kb] [bigint] NULL,
	[available_memory_kb] [bigint] NULL,
	[granted_memory_kb] [bigint] NULL,
	[used_memory_kb] [bigint] NULL,
	[grantee_count] [int] NULL,
	[waiter_count] [int] NULL,
	[timeout_error_count] [bigint] NULL,
	[forced_grant_count] [bigint] NULL,

	--aggregated attributes from dm_exec_memory_grants
	[NumGrantRows] [int] NULL,
	[sum_dop] [int] NULL,
	[earliest_request_time] [datetime] NULL,
	[longest_granted_delay_sec] [bigint] NULL,
	[sum_requested_memory_kb] [bigint] NULL,
	[max_requested_memory_kb] [bigint] NULL,
	[sum_required_memory_kb] [bigint] NULL,
	[max_required_memory_kb] [bigint] NULL,
	[sum_max_used_memory_kb] [bigint] NULL,
	[max_max_used_memory_kb] [bigint] NULL,
	[sum_wait_time_ms] [bigint] NULL,
	[max_wait_time_ms] [bigint] NULL,
	[num_is_small] [int] NULL,
 CONSTRAINT [PKdm_exec_query_resource_semaphores] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[pool_id] ASC,
	[resource_semaphore_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


