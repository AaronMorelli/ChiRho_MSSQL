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

	FILE NAME: AutoWho_Log.Table.sql

	TABLE NAME: AutoWho_Log

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds error and informational log messages from various AutoWho
	procedures
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_Log(
	[LogDT] [datetime2](7) NOT NULL,
	[LogDTUTC] [datetime2](7) NOT NULL,
	[TraceID] [int] NULL,
	[ProcID] [int] NULL,
	[ProcName] [nvarchar](256) NULL,
	[NestLevel] [tinyint] NULL,
	[RowCount] [bigint] NULL,
	[AutoWhoCode] [int] NOT NULL,
	[LocationTag] [nvarchar](100) NOT NULL,
	[LogMessage] [nvarchar](max) NOT NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
CREATE CLUSTERED INDEX [CL_LogDT] ON @@CHIRHO_SCHEMA@@.AutoWho_Log
(
	[LogDT] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [NCL_LogDTUTC] ON @@CHIRHO_SCHEMA@@.AutoWho_Log
(
	[LogDTUTC] ASC
)
INCLUDE (
	[LogDT],
	[TraceID],
	[ProcID],
	[ProcName],
	[NestLevel],
	[RowCount],
	[AutoWhoCode],
	[LocationTag],
	[LogMessage]
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
