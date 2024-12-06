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

	FILE NAME: ServerEye_dm_db_index_usage_stats.Table.sql

	TABLE NAME: ServerEye_dm_db_index_usage_stats

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_db_index_usage_stats (in Batch-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_db_index_usage_stats(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[database_id] [smallint] NOT NULL,
	[object_id] [int] NOT NULL,
	[index_id] [int] NOT NULL,
	[user_seeks] [bigint] NOT NULL,
	[user_scans] [bigint] NOT NULL,
	[user_lookups] [bigint] NOT NULL,
	[user_updates] [bigint] NOT NULL,
	[last_user_seek] [datetime] NULL,
	[last_user_scan] [datetime] NULL,
	[last_user_lookup] [datetime] NULL,
	[last_user_update] [datetime] NULL,
	[system_seeks] [bigint] NOT NULL,
	[system_scans] [bigint] NOT NULL,
	[system_lookups] [bigint] NOT NULL,
	[system_updates] [bigint] NOT NULL,
	[last_system_seek] [datetime] NULL,
	[last_system_scan] [datetime] NULL,
	[last_system_lookup] [datetime] NULL,
	[last_system_update] [datetime] NULL,
 CONSTRAINT [PKdm_db_index_usage_stats] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[database_id] ASC,
	[object_id] ASC,
	[index_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO