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

	FILE NAME: ServerEye_dm_os_memory_nodes.Table.sql

	TABLE NAME: ServerEye_dm_os_memory_nodes

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_os_memory_nodes (in High-frequency metrics)
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_os_memory_nodes(
	[UTCCaptureTime]				[datetime] NOT NULL,
	[LocalCaptureTime]				[datetime] NOT NULL,
	[memory_node_id]				[smallint] NOT NULL,
	[virtual_address_space_reserved_kb] [bigint] NOT NULL,
	[virtual_address_space_committed_kb] [bigint] NOT NULL,
	[locked_page_allocations_kb]	[bigint] NOT NULL,
	[pages_kb]						[bigint] NOT NULL,
	[shared_memory_reserved_kb]		[bigint] NOT NULL,
	[shared_memory_committed_kb]	[bigint] NOT NULL,
	[cpu_affinity_mask]				[bigint] NOT NULL,
	[online_scheduler_mask]			[bigint] NOT NULL,
	[processor_group]				[smallint] NOT NULL,
	[foreign_committed_kb]			[bigint] NOT NULL,
 CONSTRAINT [PKdm_os_memory_nodes] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[memory_node_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


