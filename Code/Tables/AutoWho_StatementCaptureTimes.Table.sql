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

	FILE NAME: AutoWho_StatementCaptureTimes.Table.sql

	TABLE NAME: AutoWho_StatementCaptureTimes

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Marks start and end times for user statements and batches observed by @@CHIRHO_SCHEMA@@.AutoWho_
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_StatementCaptureTimes (
	--Identifier columns
	[session_id]			[smallint] NOT NULL,
	[request_id]			[smallint] NOT NULL,
	[TimeIdentifier]		[datetime] NOT NULL,
	[UTCCaptureTime]		[datetime] NOT NULL,
	[SPIDCaptureTime]		[datetime] NOT NULL,

	--attribute cols
	[StatementFirstCaptureUTC] [datetime] NOT NULL,	--The first UTCCaptureTime for the statement that this row belongs to. This acts as a grouping
													--field (that is also ascending as statements run for the batch! a nice property)
	[PreviousCaptureTimeUTC]	[datetime] NULL,
	[StatementSequenceNumber] [int] NOT NULL,		--statement # within the batch. We use this instead of PKSQLStmtStoreID b/c that could be revisited

	[PKSQLStmtStoreID]		[bigint] NOT NULL,		--TODO: still need to implement TMR wait logic. Note that for TMR waits, the current plan is to 
													--*always* assume it is a new statement even if the calc__tmr_wait value matches between the 
													--most recent SPIDCaptureTime in this table and the "current" statement.

	[PKQueryPlanStmtStoreID] [bigint] NULL,

	[rqst__query_hash]		[binary](8) NULL,		--storing this makes some presentation procs more quickly able to find high-frequency queries.
	[sess__database_id]		[smallint] NOT NULL,	--this is -1 if we can't find a valid DBID in SAR

	--These fields start at 0 and are only set to 1 when we KNOW that a row is the first and/or last of a statement or batch.
	--Thus, once set to 1 they should never change.
	[IsStmtFirstCapture]	[bit] NOT NULL,
	[IsStmtLastCapture]		[bit] NOT NULL,
	[IsBatchFirstCapture]	[bit] NOT NULL,
	[IsBatchLastCapture]	[bit] NOT NULL,

	--This is set to 1 when we consider a batch still be active (i.e. a run of our post-processing proc finds it still in closing set).
	--This allows us to find this row quickly on a future post-processing run, and then include it in the "working set".
	[IsCurrentLastRowOfBatch]	[bit] NOT NULL,
 CONSTRAINT [PKAutoWhoStatementCaptureTimes] PRIMARY KEY CLUSTERED 
(
	[session_id] ASC,
	[request_id] ASC,
	[TimeIdentifier] ASC,
	[UTCCaptureTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
--We keep the PK cols in this NCL key to support merge joins on the commonly-joined cols (after a seek on IsCurrentLastRowOfBatch=1)
CREATE NONCLUSTERED INDEX [NCL_ActiveBatchFinalRow] ON @@CHIRHO_SCHEMA@@.AutoWho_StatementCaptureTimes
(
	[IsCurrentLastRowOfBatch] ASC,
	[session_id] ASC,
	[request_id] ASC,
	[TimeIdentifier] ASC,
	[UTCCaptureTime] ASC
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [NCL_StatementFirstCaptureUTC] ON @@CHIRHO_SCHEMA@@.AutoWho_StatementCaptureTimes
(
	[StatementFirstCaptureUTC] ASC
)
INCLUDE (
	session_id,
	request_id,
	TimeIdentifier,
	UTCCaptureTime,
	SPIDCaptureTime,
	PreviousCaptureTimeUTC,
	StatementSequenceNumber,
	PKSQLStmtStoreID,
	PKQueryPlanStmtStoreID,
	rqst__query_hash,
	sess__database_id,
	IsStmtFirstCapture,
	IsStmtLastCapture,
	IsBatchFirstCapture,
	IsBatchLastCapture,
	IsCurrentLastRowOfBatch
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
