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

	FILE NAME: ServerEye_dm_os_sys_info_stable.Table.sql

	TABLE NAME: ServerEye_dm_os_sys_info_stable

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds data from dm_os_sys_info that doesn't change very often.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_os_sys_info_stable(
	[osisID] [int] IDENTITY(1,1) NOT NULL,
	[EffectiveStartTimeUTC] [datetime] NOT NULL,
	[EffectiveEndTimeUTC] [datetime] NULL,
	[EffectiveStartTime] [datetime] NOT NULL,
	[EffectiveEndTime] [datetime] NULL,
	[sqlserver_start_time_ms_ticks] [bigint] NOT NULL,
	[sqlserver_start_time] [datetime] NOT NULL,
	[cpu_count] [int] NOT NULL,
	[hyperthread_ratio] [int] NOT NULL,
	[physical_memory_in_bytes] [bigint] NULL,
	[physical_memory_kb] [bigint] NULL,
	[virtual_memory_in_bytes] [bigint] NULL,
	[virtual_memory_kb] [bigint] NULL,
	[stack_size_in_bytes] [int] NOT NULL,
	[os_quantum] [bigint] NOT NULL,
	[os_error_mode] [int] NOT NULL,
	[os_priority_class] [int] NULL,
	[max_workers_count] [int] NOT NULL,
	[scheduler_count] [int] NOT NULL,
	[scheduler_total_count] [int] NOT NULL,
	[deadlock_monitor_serial_number] [int] NOT NULL,
	[affinity_type] [int] NOT NULL,
	[affinity_type_desc] [varchar](60) NOT NULL,
	[time_source] [int] NOT NULL,
	[time_source_desc] [nvarchar](60) NOT NULL,
	[virtual_machine_type] [int] NOT NULL,
	[virtual_machine_type_desc] [nvarchar](60) NOT NULL,
 CONSTRAINT [PK_os_sys_info_stable] PRIMARY KEY CLUSTERED 
(
	[osisID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
CREATE NONCLUSTERED INDEX [NCL_EffectiveEndTimeUTC] ON @@CHIRHO_SCHEMA@@.ServerEye_dm_os_sys_info_stable
(
	[EffectiveEndTimeUTC] ASC
)
INCLUDE ( 	[osisID]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO


