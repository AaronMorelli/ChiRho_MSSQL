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

	FILE NAME: ServerEye_dm_os_memory_cache_clock_hands.Table.sql

	TABLE NAME: ServerEye_dm_os_memory_cache_clock_hands

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_os_memory_cache_clock_hands (in Med-frequency metrics)
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_os_memory_cache_clock_hands(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[DimMemoryTrackerID] [smallint],
	[memory_node_id] [smallint] NOT NULL,
	[clock_hand] [nvarchar](60) NOT NULL,
	[NumUniqueRows] [int] NOT NULL,
	[sum_status_is_suspended] [int] NULL,
	[sum_status_is_running] [int] NULL,
	[sum_rounds_count] [bigint] NULL,
	[sum_removed_all_rounds_count] [bigint] NULL,
	[sum_updated_last_round_count] [bigint] NULL,
	[sum_removed_last_round_count] [bigint] NULL,
 CONSTRAINT [PKdm_os_memory_cache_clock_hands] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[DimMemoryTrackerID] ASC,
	[memory_node_id] ASC,
	[clock_hand] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO


