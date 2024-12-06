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

	FILE NAME: ServerEye_DatabaseStats.Table.sql

	TABLE NAME: ServerEye_DatabaseStats

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots DatabaseStats (in Medium-frequency metrics)
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DatabaseStats(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[database_id] [int] NOT NULL,
	[user_access_desc] [nvarchar](128) NOT NULL,
	[state_desc] [nvarchar](128) NOT NULL,
	[LogSizeMB] [decimal](21,8) NULL,
	[LogPctUsed] [decimal](11,8) NULL,
 CONSTRAINT [PKDatabaseStats] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[database_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO