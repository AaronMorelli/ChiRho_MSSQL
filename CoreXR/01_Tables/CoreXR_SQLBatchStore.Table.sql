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

	FILE NAME: CoreXR_SQLBatchStore.Table.sql

	TABLE NAME: CoreXR_SQLBatchStore

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: A centralized store for all batch-level statement text collected by
	the various components in the ChiRho system
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore(
	[PKSQLBatchStoreID]			[bigint] IDENTITY(1,1) NOT NULL,
	[sql_handle]				[varbinary](64) NOT NULL,
	[dbid]						[smallint] NOT NULL,
	[objectid]					[int] NOT NULL,
	[fail_to_obtain]			[bit] NOT NULL,
	[batch_text]				[nvarchar](max) NOT NULL,
	[InsertedBy_UTCCaptureTime]	[datetime] NOT NULL,	--In AutoWho, these 2 fields map to UTCCaptureTime in AutoWho.CaptureTimes,
	[LastTouchedBy_UTCCaptureTime] [datetime] NOT NULL,
 CONSTRAINT [PKSQLBatchStore] PRIMARY KEY CLUSTERED 
(
	[PKSQLBatchStoreID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
SET ANSI_PADDING ON

GO
CREATE NONCLUSTERED INDEX [NCL_LastTouched] ON @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore
(
	[LastTouchedBy_UTCCaptureTime] ASC
)
INCLUDE ( 	[sql_handle],
	[PKSQLBatchStoreID]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [AKSQLBatchStore] ON @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore
(
	[sql_handle] ASC
)
INCLUDE ( 	[fail_to_obtain],
	[PKSQLBatchStoreID]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
