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

	FILE NAME: ServerEye_dm_resource_governor_resource_pools.Table.sql

	TABLE NAME: ServerEye_dm_resource_governor_resource_pools

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_resource_governor_resource_pools (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_resource_governor_resource_pools(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[pool_id] [int] NOT NULL,
	[name] [nvarchar](256) NOT NULL,
	[statistics_start_time] [datetime] NOT NULL,
	[total_cpu_usage_ms] [bigint] NOT NULL,
	[cache_memory_kb] [bigint] NOT NULL,
	[compile_memory_kb] [bigint] NOT NULL,
	[used_memgrant_kb] [bigint] NOT NULL,
	[total_memgrant_count] [bigint] NOT NULL,
	[total_memgrant_timeout_count] [bigint] NOT NULL,
	[active_memgrant_count] [int] NOT NULL,
	[active_memgrant_kb] [bigint] NOT NULL,
	[memgrant_waiter_count] [int] NOT NULL,
	[max_memory_kb] [bigint] NOT NULL,
	[used_memory_kb] [bigint] NOT NULL,
	[target_memory_kb] [bigint] NOT NULL,
	[out_of_memory_count] [bigint] NOT NULL,
	[min_cpu_percent] [int] NOT NULL,
	[max_cpu_percent] [int] NOT NULL,
	[min_memory_percent] [int] NOT NULL,
	[max_memory_percent] [int] NOT NULL,
	[cap_cpu_percent] [int] NOT NULL,
	[min_iops_per_volume] [int] NULL,
	[max_iops_per_volume] [int] NULL,
	[read_io_queued_total] [int] NULL,
	[read_io_issued_total] [int] NULL,
	[read_io_completed_total] [int] NOT NULL,
	[read_io_throttled_total] [int] NULL,
	[read_bytes_total] [bigint] NOT NULL,
	[read_io_stall_total_ms] [bigint] NOT NULL,
	[read_io_stall_queued_ms] [bigint] NULL,
	[write_io_queued_total] [int] NULL,
	[write_io_issued_total] [int] NULL,
	[write_io_completed_total] [int] NOT NULL,
	[write_io_throttled_total] [int] NULL,
	[write_bytes_total] [bigint] NOT NULL,
	[write_io_stall_total_ms] [bigint] NOT NULL,
	[write_io_stall_queued_ms] [bigint] NULL,
	[io_issue_violations_total] [int] NULL,
	[io_issue_delay_total_ms] [bigint] NULL,
 CONSTRAINT [PKdm_resource_governor_resource_pools] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[pool_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO