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

	FILE NAME: CoreXR_InputBufferStore.Table.sql

	TABLE NAME: CoreXR_InputBufferStore

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: A central store for all input buffers captured by any component
	in the ChiRho system. (AutoWho is the only populator/consumer at this point)
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore(
	[PKInputBufferStoreID]		[bigint] IDENTITY(1,1) NOT NULL,
	[AWBufferHash]				[varbinary](64) NOT NULL,
	[InputBuffer]				[nvarchar](4000) NOT NULL,
	[InsertedBy_UTCCaptureTime]	[datetime] NOT NULL,	--In AutoWho, these 2 fields map to UTCCaptureTime in AutoWho.CaptureTimes,
	[LastTouchedBy_UTCCaptureTime] [datetime] NOT NULL,
 CONSTRAINT [PKInputBufferStore] PRIMARY KEY CLUSTERED 
(
	[PKInputBufferStoreID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [AKInputBufferStore] ON @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore
(
	[AWBufferHash] ASC,
	[PKInputBufferStoreID] ASC
)
INCLUDE ([InputBuffer]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
CREATE NONCLUSTERED INDEX [NCL_LastTouched] ON @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore
(
	[LastTouchedBy_UTCCaptureTime] ASC
)
INCLUDE ( 	[PKInputBufferStoreID],
	[AWBufferHash],
	[InputBuffer]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
