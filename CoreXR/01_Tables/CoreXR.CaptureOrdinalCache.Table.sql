/*
   Copyright 2024 Aaron Morelli

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

	FILE NAME: CoreXR.CaptureOrdinalCache.Table.sql

	TABLE NAME: CoreXR.CaptureOrdinalCache

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds a list of capture times (e.g. for captures by the AutoWho or ServerEye components)
	and each capture time's order number (both ascending and descending) within the overall range. The
	front-end UI procs populate this table when requested by a user call, for a given start/end range,
	and then refer to it as they iterate over the capture times.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@COREXR_SCHEMA@@.CaptureOrdinalCache(
	[Utility] [nvarchar](30) NOT NULL,
	[CollectionInitiatorID] [tinyint] NOT NULL,
	[StartTime] [datetime] NOT NULL,		--We don't have UTC versions of these 2 time fields because we expect the user
	[EndTime] [datetime] NOT NULL,			--to always enter time locally (how most people think). If they enter a time between
											--1am and 2am on a DST "fall back" day, they'll get records for both UTC time windows.
											--If they enter a time between 2am and 3am on a DST "leap forward" day, they won't
											--get anything.
	[Ordinal] [int] NOT NULL,
	[OrdinalNegative] [int] NOT NULL,
	[CaptureTime] [datetime] NOT NULL,
	[CaptureTimeUTC] [datetime] NOT NULL,
	[TimePopulated] [datetime] NOT NULL,
	[TimePopulatedUTC] [datetime] NOT NULL,
 CONSTRAINT [PKCaptureOrdinalCache] PRIMARY KEY CLUSTERED 
(
	[Utility] ASC,
	[CollectionInitiatorID] ASC,
	[StartTime] ASC,
	[EndTime] ASC,
	[Ordinal] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
CREATE UNIQUE NONCLUSTERED INDEX [UNCL_OrdinalNegative] ON @@COREXR_SCHEMA@@.CaptureOrdinalCache
(
	[Utility] ASC,
	[CollectionInitiatorID] ASC,
	[StartTime] ASC,
	[EndTime] ASC,
	[OrdinalNegative] ASC
)
INCLUDE ( 	[Ordinal],
	[CaptureTime],
	[CaptureTimeUTC],
	[TimePopulated]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, 
		IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
ALTER TABLE @@COREXR_SCHEMA@@.CaptureOrdinalCache ADD  CONSTRAINT [DF_CoreXR_CaptureOrdinalCache_TimePopulated]  DEFAULT (GETDATE()) FOR [TimePopulated]
GO
ALTER TABLE @@COREXR_SCHEMA@@.CaptureOrdinalCache ADD  CONSTRAINT [DF_CoreXR_CaptureOrdinalCache_TimePopulatedUTC]  DEFAULT (GETUTCDATE()) FOR [TimePopulatedUTC]
GO