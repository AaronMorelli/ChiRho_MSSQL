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

	FILE NAME: ServerEye_UserCollectionOptions_History.Table.sql

	TABLE NAME: ServerEye_UserCollectionOptions_History

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Populated by triggers on the ServerEye_UserCollectionOptions table every time any option value changes.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_UserCollectionOptions_History(
	[HistoryInsertDate] [datetime] NOT NULL,
	[HistoryInsertDateUTC] [datetime] NOT NULL,
	[LastModifiedUser] [nvarchar](128) NOT NULL,
	[TriggerAction] [nvarchar](40) NOT NULL,
	[OptionSet] [nvarchar](50) NOT NULL,
	[IncludeDBs] [nvarchar](4000) NOT NULL,
	[ExcludeDBs] [nvarchar](4000) NOT NULL,
	[DebugSpeed] [nchar](1) NOT NULL,
 CONSTRAINT [PKSEUserCollectionOptions_History] PRIMARY KEY CLUSTERED 
(
	[HistoryInsertDate] ASC,
	[TriggerAction] ASC,
	[OptionSet] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
