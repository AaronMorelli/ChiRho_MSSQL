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

	FILE NAME: AutoWho_LockDetails.Table.sql

	TABLE NAME: AutoWho_LockDetails

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds data from sys.dm_os_tran_locks gathered by the @@CHIRHO_SCHEMA@@.AutoWho_Collector.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LockDetails(
	[CollectionInitiatorID] [tinyint] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,
	[SPIDCaptureTime] [datetime] NOT NULL,
	[request_session_id] [smallint] NOT NULL,
	[request_request_id] [smallint] NULL,
	[TimeIdentifier] [datetime] NOT NULL,
	[request_exec_context_id] [smallint] NULL,
	[request_owner_type] [tinyint] NULL,
	[request_owner_id] [bigint] NULL,
	[request_owner_guid] [nvarchar](40) NULL,
	[resource_type] [nvarchar](60) NULL,
	[resource_subtype] [nvarchar](60) NULL,
	[resource_database_id] [int] NULL,
	[resource_description] [nvarchar](256) NULL,
	[resource_associated_entity_id] [bigint] NULL,
	[resource_lock_partition] [int] NULL,
	[request_mode] [nvarchar](60) NULL,
	[request_type] [nvarchar](60) NULL,
	[request_status] [nvarchar](60) NULL,
	[RecordCount] [bigint] NULL
) ON [PRIMARY]
GO
--No, this table does not currently have a primary key. I'm not sure one is possible
-- given the nature of the DMV it stores.
CREATE CLUSTERED INDEX [CL_UTCCaptureTime] ON @@CHIRHO_SCHEMA@@.AutoWho_LockDetails
(
	[CollectionInitiatorID] ASC,
	[UTCCaptureTime] ASC,
	[request_session_id] ASC,
	[request_request_id] ASC,
	[TimeIdentifier] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
