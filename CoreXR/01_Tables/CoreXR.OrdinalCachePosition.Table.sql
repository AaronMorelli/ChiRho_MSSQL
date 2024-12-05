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

	FILE NAME: CoreXR.OrdinalCachePosition.Table.sql

	TABLE NAME: CoreXR.OrdinalCachePosition

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds the current ordinal position within a given cache from the
	CaptureOrdinalCache table. An ordinal cache is identified by the combination
	of columns: StartTime/EndTime/session_id, and the CurrentPosition is valid
	for the range of ordinals found in CaptureOrdinalCache for the matching
	start/end/session_id.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@COREXR_SCHEMA@@.OrdinalCachePosition(
	[Utility] [nvarchar](30) NOT NULL,
	[CollectionInitiatorID] [tinyint] NOT NULL,
	[StartTime] [datetime] NOT NULL,
	[EndTime] [datetime] NOT NULL,
	[session_id] [smallint] NOT NULL,
	[CurrentPosition] [int] NOT NULL,
	[LastOptionsHash] [varbinary](64) NOT NULL,
 CONSTRAINT [PKOrdinalCachePosition] PRIMARY KEY CLUSTERED 
(
	[Utility] ASC,
	[CollectionInitiatorID] ASC,
	[StartTime] ASC,
	[EndTime] ASC,
	[session_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
