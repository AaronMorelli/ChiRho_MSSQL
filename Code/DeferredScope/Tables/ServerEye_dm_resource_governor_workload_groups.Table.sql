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

	FILE NAME: ServerEye_dm_resource_governor_workload_groups.Table.sql

	TABLE NAME: ServerEye_dm_resource_governor_workload_groups

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_resource_governor_workload_groups (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_resource_governor_workload_groups(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[group_id] [int] NOT NULL,
	[name] [nvarchar](256) NOT NULL,
	[pool_id] [int] NOT NULL,
	[statistics_start_time] [datetime] NOT NULL,
	[total_request_count] [bigint] NOT NULL,
	[total_queued_request_count] [bigint] NOT NULL,
	[active_request_count] [int] NOT NULL,
	[queued_request_count] [int] NOT NULL,
	[total_cpu_limit_violation_count] [bigint] NOT NULL,
	[total_cpu_usage_ms] [bigint] NOT NULL,
	[max_request_cpu_time_ms] [bigint] NOT NULL,
	[blocked_task_count] [int] NOT NULL,
	[total_lock_wait_count] [bigint] NOT NULL,
	[total_lock_wait_time_ms] [bigint] NOT NULL,
	[total_query_optimization_count] [bigint] NOT NULL,
	[total_suboptimal_plan_generation_count] [bigint] NOT NULL,
	[total_reduced_memgrant_count] [bigint] NOT NULL,
	[max_request_grant_memory_kb] [bigint] NOT NULL,
	[active_parallel_thread_count] [bigint] NOT NULL,
	[importance] [nvarchar](256) NOT NULL,
	[request_max_memory_grant_percent] [int] NOT NULL,
	[request_max_cpu_time_sec] [int] NOT NULL,
	[request_memory_grant_timeout_sec] [int] NOT NULL,
	[group_max_requests] [int] NOT NULL,
	[max_dop] [int] NOT NULL,
	[effective_max_dop] [int] NOT NULL,
 CONSTRAINT [PKdm_resource_governor_workload_groups] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[group_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO