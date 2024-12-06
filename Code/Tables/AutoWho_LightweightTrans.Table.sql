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

	FILE NAME: AutoWho_LightweightTrans.Table.sql

	TABLE NAME: AutoWho_LightweightTrans

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds data from the transaction-based DMVs when
	the @@CHIRHO_SCHEMA@@.AutoWho_Collector proc runs longer than a certain duration or fails.
	It represents an attempt to just grab a dump of the contents of the DMVs
	using loop joins (i.e. no mem requirements) if the more complicated logic
	of the Collector doesn't work or doesn't work quickly.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING OFF
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LightweightTrans(
	[SPIDCaptureTime] [datetime] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,		--unlike SAR, we need a UTC field because lightweight captures are not recorded in @@CHIRHO_SCHEMA@@.AutoWho_CaptureTime
	[dtat__transaction_id] [bigint] NOT NULL,
	[dtat__transaction_name] [nvarchar](32) NOT NULL,
	[dtat__transaction_begin_time] [datetime] NOT NULL,
	[dtat__transaction_type] [int] NOT NULL,
	[dtat__transaction_uow] [uniqueidentifier] NULL,
	[dtat__transaction_state] [int] NOT NULL,
	[dtat__transaction_status] [int] NOT NULL,
	[dtat__transaction_status2] [int] NOT NULL,
	[dtat__dtc_state] [int] NOT NULL,
	[dtat__dtc_status] [int] NOT NULL,
	[dtat__dtc_isolation_level] [int] NOT NULL,
	[dtat__filestream_transaction_id] [varbinary](128) NULL,
	[dtst__session_id] [int] NULL,
	[dtst__transaction_descriptor] [binary](8) NULL,
	[dtst__enlist_count] [int] NULL,
	[dtst__is_user_transaction] [bit] NULL,
	[dtst__is_local] [bit] NULL,
	[dtst__is_enlisted] [bit] NULL,
	[dtst__is_bound] [bit] NULL,
	[dtst__open_transaction_count] [int] NULL,
	[dtdt__database_id] [int] NULL,
	[dtdt__database_transaction_begin_time] [datetime] NULL,
	[dtdt__database_transaction_type] [int] NULL,
	[dtdt__database_transaction_state] [int] NULL,
	[dtdt__database_transaction_status] [int] NULL,
	[dtdt__database_transaction_status2] [int] NULL,
	[dtdt__database_transaction_log_record_count] [bigint] NULL,
	[dtdt__database_transaction_replicate_record_count] [int] NULL,
	[dtdt__database_transaction_log_bytes_used] [bigint] NULL,
	[dtdt__database_transaction_log_bytes_reserved] [bigint] NULL,
	[dtdt__database_transaction_log_bytes_used_system] [int] NULL,
	[dtdt__database_transaction_log_bytes_reserved_system] [int] NULL,
	[dtdt__database_transaction_begin_lsn] [numeric](25, 0) NULL,
	[dtdt__database_transaction_last_lsn] [numeric](25, 0) NULL,
	[dtdt__database_transaction_most_recent_savepoint_lsn] [numeric](25, 0) NULL,
	[dtdt__database_transaction_commit_lsn] [numeric](25, 0) NULL,
	[dtdt__database_transaction_last_rollback_lsn] [numeric](25, 0) NULL,
	[dtdt__database_transaction_next_undo_lsn] [numeric](25, 0) NULL
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
