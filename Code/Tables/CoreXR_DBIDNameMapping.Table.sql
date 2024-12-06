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

	FILE NAME: CoreXR_DBIDNameMapping.Table.sql

	TABLE NAME: CoreXR_DBIDNameMapping

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: The various components of ChiRho typically store just the DBID.
	This table provides a mapping and serves as a type-2 dimension, handling
	changes over time.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.CoreXR_DBIDNameMapping(
	[DBID]					[int] NOT NULL,
	[DBName]				[nvarchar](256) NOT NULL,
	[EffectiveStartTimeUTC] [datetime] NOT NULL,
	[EffectiveEndTimeUTC]	[datetime] NULL,
	[EffectiveStartTime]	[datetime] NOT NULL,
	[EffectiveEndTime]		[datetime] NULL,
 CONSTRAINT [PKDBIDNameMapping] PRIMARY KEY CLUSTERED 
(
	[DBName] ASC,
	[EffectiveStartTimeUTC] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING ON

GO
CREATE UNIQUE NONCLUSTERED INDEX [AKDBIDNameMapping] ON @@CHIRHO_SCHEMA@@.CoreXR_DBIDNameMapping
(
	[DBID] ASC,
	[EffectiveStartTimeUTC] ASC
)
INCLUDE ( 	[DBName],
	[EffectiveEndTimeUTC],
	[EffectiveStartTime],
	[EffectiveEndTime]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
