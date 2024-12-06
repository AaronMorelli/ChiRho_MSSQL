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

	FILE NAME: AutoWho_BlockingGraphs.Table.sql

	TABLE NAME: AutoWho_BlockingGraphs

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds a tabular, intermediate representation of the Blocking Graph functionality
	displayed by sp_XR_SessionViewer.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs(
	[CollectionInitiatorID]		[tinyint] NOT NULL,
	[UTCCaptureTime]			[datetime] NOT NULL,
	[SPIDCaptureTime]			[datetime] NOT NULL,
	[session_id]				[smallint] NOT NULL,
	[request_id]				[smallint] NOT NULL,
	[exec_context_id]			[smallint] NULL,
	[calc__blocking_session_Id] [smallint] NULL,
	[wait_type]					[nvarchar](60) NULL,
	[wait_duration_ms]			[bigint] NULL,
	[resource_description]		[nvarchar](500) NULL,
	[FKInputBufferStoreID]		[bigint] NULL,
	[FKSQLStmtStoreID]			[bigint] NULL,
	[sort_value]				[nvarchar](400) NULL,
	[block_group]				[smallint] NULL,
	[levelindc]					[smallint] NOT NULL,
	[rn]						[smallint] NOT NULL
) ON [PRIMARY]
GO
--This table is more of an intermediate dump for processing data into an
-- indented string format. May re-evaluate whether a primary key 
-- or unique index can work here at a later time. 
CREATE CLUSTERED INDEX [CL_UTCCaptureTime] ON @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs
(
	[CollectionInitiatorID] ASC,
	[UTCCaptureTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
