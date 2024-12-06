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

	FILE NAME: AutoWho_DimWaitType.Table.sql

	TABLE NAME: AutoWho_DimWaitType

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds the distinct list of wait types (in either sys.dm_exec_requests
	or sys.dm_os_waiting_tasks) observed by @@CHIRHO_SCHEMA@@.AutoWho_Collector.
	Note that ServerEye uses its own table for storing sys.dm_os_wait_stats info.
	This is to keep the # of rows in @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType very low (perhaps even
	on just 1 page) so that the @@CHIRHO_SCHEMA@@.AutoWho_Collector proc stays as lean as possible.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType(
	[DimWaitTypeID] [smallint] IDENTITY(30,1) NOT NULL,
	[wait_type] [nvarchar](60) NOT NULL,
	[wait_type_short] [nvarchar](60) NOT NULL,
	[latch_subtype] [nvarchar](100) NOT NULL,
	[TimeAdded] [datetime] NOT NULL,
	[TimeAddedUTC] [datetime] NOT NULL,
 CONSTRAINT [PK_AutoWho_DimWaitType] PRIMARY KEY CLUSTERED 
(
	[DimWaitTypeID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE UNIQUE NONCLUSTERED INDEX [AK_AutoWho_DimWaitType] ON @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType
(
	[wait_type] ASC,
	[wait_type_short] ASC,
	[latch_subtype] ASC
)
INCLUDE ( 	[DimWaitTypeID],
	[TimeAdded],
	[TimeAddedUTC]
) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType ADD  CONSTRAINT [DF_AutoWho_DimWaitType_TimeAdded]  DEFAULT (GETDATE()) FOR [TimeAdded]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType ADD  CONSTRAINT [DF_AutoWho_DimWaitType_TimeAddedUTC]  DEFAULT (GETUTCDATE()) FOR [TimeAddedUTC]
GO