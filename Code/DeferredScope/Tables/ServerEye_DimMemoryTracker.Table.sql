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

	FILE NAME: ServerEye_DimMemoryTracker.Table.sql

	TABLE NAME: ServerEye_DimMemoryTracker

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Many of the important memory DMVs have a "type" and "name" column identifying the memory store for which the
		data is being collected. There is much overlap between the DMVs in type/name values. This Dim table stores a superset
		of the type/name values encountered, and also has flag fields to show which DMVs that type/name was found.

		Here are the DMVs that are served by this Dim table:

		sys.dm_os_memory_clerks
		sys.dm_os_memory_cache_clock_hands
		sys.dm_os_memory_cache_counters
		sys.dm_os_memory_cache_hash_tables
		sys.dm_os_memory_pools
		sys.dm_os_hosts

*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimMemoryTracker(
	[DimMemoryTrackerID] [smallint] IDENTITY(1,1) NOT NULL,
	[type] [nvarchar](128) NOT NULL,
	[name] [nvarchar](128) NOT NULL,

	--By tracking which memory stores are in which DMVs, we can limit our collection queries
	--to just the Dim values that matter
	[IsInClerks] [bit] NOT NULL,
	[IsInClockHands] [bit] NOT NULL,
	[IsInCacheCounters] [bit] NOT NULL,
	[IsInCacheHashTables] [bit] NOT NULL,
	[IsInPools] [bit] NOT NULL,
	[IsInHosts] [bit] NOT NULL,

	[TimeAdded] [datetime] NOT NULL CONSTRAINT [DF_DimMemoryTracker_TimeAdded]  DEFAULT (GETDATE()),
	[TimeAddedUTC] [datetime] NOT NULL CONSTRAINT [DF_DimMemoryTracker_TimeAddedUTC]  DEFAULT (GETUTCDATE()),
PRIMARY KEY CLUSTERED 
(
	[DimMemoryTrackerID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKLatchClass] ON @@CHIRHO_SCHEMA@@.ServerEye_DimMemoryTracker
(
	[type],		--It is common for the same type/name value to appear multiple times
	[name]		--in one or more DMVs, just with different addresses. We aggregate metrics for these together
				--so that the whole collection appears as just 1 row.
)
INCLUDE ( 	
	[DimMemoryTrackerID],

	[IsInClerks],
	[IsInClockHands],
	[IsInCacheCounters],
	[IsInCacheHashTables],
	[IsInPools],
	[IsInHosts],

	[TimeAdded],
	[TimeAddedUTC]
) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
