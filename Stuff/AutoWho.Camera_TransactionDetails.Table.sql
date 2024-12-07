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

	FILE NAME: AutoWho_Camera_TransactionDetails.Table.sql

	TABLE NAME: AutoWho.Camera_TransactionDetails

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds the tran details data for the sp_XR_QueryCamera functionality
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [AutoWho].[Camera_TransactionDetails](
	[SPIDCaptureTime] [datetime] NOT NULL,
	[session_id] [smallint] NOT NULL,
	[dtat_transaction_id] [bigint] NOT NULL,
	[dtat_name] [nvarchar](32) NULL,
	[dtat_transaction_begin_time] [datetime] NULL,
	[dtat_transaction_type] [smallint] NULL,
	[dtat_transaction_uow] [uniqueidentifier] NULL,
	[dtat_transaction_state] [smallint] NULL,
	[dtat_dtc_state] [smallint] NULL,
	[dtst_enlist_count] [smallint] NULL,
	[dtst_is_user_transaction] [bit] NULL,
	[dtst_is_local] [bit] NULL,
	[dtst_is_enlisted] [bit] NULL,
	[dtst_is_bound] [bit] NULL,
	[dtdt_database_id] [int] NULL,
	[dtdt_database_transaction_begin_time] [datetime] NULL,
	[dtdt_database_transaction_type] [smallint] NULL,
	[dtdt_database_transaction_state] [smallint] NULL,
	[dtdt_database_transaction_log_record_count] [bigint] NULL,
	[dtdt_database_transaction_log_bytes_used] [bigint] NULL,
	[dtdt_database_transaction_log_bytes_reserved] [bigint] NULL,
	[dtdt_database_transaction_log_bytes_used_system] [int] NULL,
	[dtdt_database_transaction_log_bytes_reserved_system] [int] NULL,
	[dtasdt_tran_exists] [bit] NULL,
	[dtasdt_transaction_sequence_num] [bigint] NULL,
	[dtasdt_commit_sequence_num] [bigint] NULL,
	[dtasdt_is_snapshot] [smallint] NULL,
	[dtasdt_first_snapshot_sequence_num] [bigint] NULL,
	[dtasdt_max_version_chain_traversed] [int] NULL,
	[dtasdt_average_version_chain_traversed] [real] NULL,
	[dtasdt_elapsed_time_seconds] [bigint] NULL
) ON [PRIMARY]

GO
CREATE CLUSTERED INDEX [CL_SpidCaptureTime] ON [AutoWho].[Camera_TransactionDetails]
(
	[SPIDCaptureTime] ASC,
	[session_id] ASC,
	[dtat_transaction_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
