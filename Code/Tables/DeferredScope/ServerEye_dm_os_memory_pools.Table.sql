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

	FILE NAME: ServerEye_dm_os_memory_pools.Table.sql

	TABLE NAME: ServerEye_dm_os_memory_pools

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_os_memory_pools (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_os_memory_pools(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[DimMemoryTrackerID] [smallint] NOT NULL,
	[memory_node_id] [smallint] NOT NULL,
	[NumUniqueRows] [int] NOT NULL,
	[sum_max_free_entries_count] [bigint] NULL,
	[sum_free_entries_count] [bigint] NULL,
	[sum_removed_in_all_rounds_count] [bigint] NULL,
 CONSTRAINT [PKdm_os_memory_pools] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[DimMemoryTrackerID] ASC,
	[memory_node_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


