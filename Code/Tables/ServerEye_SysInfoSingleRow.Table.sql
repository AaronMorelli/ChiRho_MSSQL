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

	FILE NAME: ServerEye_SysInfoSingleRow.Table.sql

	TABLE NAME: ServerEye_SysInfoSingleRow

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Columns come from either DMVs that always have 1 row or from metrics 
		aggregated down to just 1 row. There will *always* just be 1 row per UTCCaptureTime in this table.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_SysInfoSingleRow(
	[UTCCaptureTime]					[datetime] NOT NULL,
	[LocalCaptureTime]					[datetime] NOT NULL,
	[StableOSIID]						[int] NOT NULL,	--a pointer to the "current" row in ServerEye_dm_os_sys_info_stable

	--metrics from sys.dm_os_sys_info (that are volatile enough to not be in ServerEye_dm_os_sys_info)
	[cpu_ticks]							[bigint] NOT NULL,
	[ms_ticks]							[bigint] NOT NULL,
	[committed_kb]						[int] NULL,
	--[bpool_committed]					[int] NULL,
	[committed_target_kb]				[int] NULL,
	--[bpool_commit_target]				[int] NULL,
	[visible_target_kb]					[int] NULL,
	--[bpool_visible]					[int] NULL,
	[process_kernel_time_ms]			[bigint] NULL,
	[process_user_time_ms]				[bigint] NULL,

	--columns from sys.dm_os_process_memory
	[physical_memory_in_use_kb]			[bigint] NOT NULL,
	[large_page_allocations_kb]			[bigint] NOT NULL,
	[locked_page_allocations_kb]		[bigint] NOT NULL,
	[total_virtual_address_space_kb]	[bigint] NOT NULL,
	[virtual_address_space_reserved_kb] [bigint] NOT NULL,
	[virtual_address_space_committed_kb] [bigint] NOT NULL,
	[virtual_address_space_available_kb] [bigint] NOT NULL,
	[page_fault_count]					[bigint] NOT NULL,
	[memory_utilization_percentage]		[int] NOT NULL,
	[available_commit_limit_kb]			[bigint] NOT NULL,
	[process_physical_memory_low]		[bit] NOT NULL,
	[process_virtual_memory_low]		[bit] NOT NULL,

	--columns from sys.dm_os_sys_memory
	[total_physical_memory_kb]			[bigint] NOT NULL,
	[available_physical_memory_kb]		[bigint] NOT NULL,
	[total_page_file_kb]				[bigint] NOT NULL,
	[available_page_file_kb]			[bigint] NOT NULL,
	[system_cache_kb]					[bigint] NOT NULL,
	[kernel_paged_pool_kb]				[bigint] NOT NULL,
	[kernel_nonpaged_pool_kb]			[bigint] NOT NULL,
	[system_high_memory_signal_state]	[bit] NOT NULL,
	[system_low_memory_signal_state]	[bit] NOT NULL,
	[system_memory_state_desc]			[nvarchar](256) NOT NULL,

	--data from sys.dm_os_tasks, just for background tasks, aggregated to a single row
	[NumBackgroundTasks]				[int] NOT NULL,
	[task__context_switches_count]		[bigint] NOT NULL,
	[task__pending_io_count]			[bigint] NOT NULL,
	[task__pending_io_byte_count]		[bigint] NOT NULL,

	--data from sys.dm_os_threads, for all threads, aggregated to a single row
	[NumThreads]						[int] NOT NULL,
	[NumThreadsStartedBySQLServer]		[int] NOT NULL,
	[SumKernelTime]						[bigint] NOT NULL,
	[SumUsermodeTime]					[bigint] NOT NULL,
	[SumStackBytesCommitted]			[bigint] NOT NULL,
	[SumStackBytesUsed]					[bigint] NOT NULL,

	--data from sys.dm_db_session_space_usage, just for background spids, aggregated to a single row
	[bkgdsess__user_objects_alloc_page_count] [bigint] NOT NULL,
	[bkgdsess__user_objects_dealloc_page_count] [bigint] NOT NULL,
	[bkgdsess__internal_objects_alloc_page_count] [bigint] NOT NULL,
	[bkgdsess__internal_objects_dealloc_page_count] [bigint] NOT NULL,
	[bkgdsess__user_objects_deferred_dealloc_page_count] [bigint] NOT NULL,
	[bkgdtask__user_objects_alloc_page_count] [bigint] NOT NULL,
	[bkgdtask__user_objects_dealloc_page_count] [bigint] NOT NULL,
	[bkgdtask__internal_objects_alloc_page_count] [bigint] NOT NULL,
	[bkgdtask__internal_objects_dealloc_page_count] [bigint] NOT NULL,
 CONSTRAINT [PKSysInfoSingleRow] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
