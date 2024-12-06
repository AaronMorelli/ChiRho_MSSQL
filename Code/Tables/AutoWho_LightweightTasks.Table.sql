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

	FILE NAME: AutoWho_LightweightTasks.Table.sql

	TABLE NAME: AutoWho_LightweightTasks

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds data from dm_os_tasks and dm_os_waiting_tasks when
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
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LightweightTasks(
	[SPIDCaptureTime] [datetime] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,		--unlike TAW, we need a UTC field because lightweight captures are not recorded in @@CHIRHO_SCHEMA@@.AutoWho_CaptureTime
	[task__task_address] [varbinary](8) NOT NULL,
	[task__task_state] [nvarchar](60) NULL,
	[task__context_switches_count] [int] NULL,
	[task__pending_io_count] [int] NULL,
	[task__pending_io_byte_count] [bigint] NULL,
	[task__pending_io_byte_average] [int] NULL,
	[task__scheduler_id] [int] NOT NULL,
	[task__session_id] [smallint] NULL,
	[task__exec_context_id] [int] NULL,
	[task__request_id] [int] NULL,
	[task__worker_address] [varbinary](8) NULL,
	[task__host_address] [varbinary](8) NOT NULL,
	[task__parent_task_address] [varbinary](8) NULL,
	[taskusage__is_remote_task] [bit] NULL,
	[taskusage__user_objects_alloc_page_count] [bigint] NULL,
	[taskusage__user_objects_dealloc_page_count] [bigint] NULL,
	[taskusage__internal_objects_alloc_page_count] [bigint] NULL,
	[taskusage__internal_objects_dealloc_page_count] [bigint] NULL,
	[wait_duration_ms] [bigint] NULL,
	[wait_type] [nvarchar](60) NULL,
	[resource_address] [varbinary](8) NULL,
	[blocking_task_address] [varbinary](8) NULL,
	[blocking_session_id] [smallint] NULL,
	[blocking_exec_context_id] [int] NULL,
	[resource_description] [nvarchar](3072) NULL
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
