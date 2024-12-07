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

	FILE NAME: AutoWho_StmtStats.Table.sql

	TABLE NAME: AutoWho.StmtStats

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds aggregated statistics about user statements that have been observed by AutoWho
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [AutoWho].[StmtStats] (
	--Identifier columns
	[session_id]			[smallint] NOT NULL,
	[request_id]			[smallint] NOT NULL,
	[TimeIdentifier]		[datetime] NOT NULL,
	[PKSQLStmtStoreID]		[bigint] NOT NULL,		--we set this to -1 if it is NULL in SAR. (This is typically TMR waits, I think)
	[StatementSequenceNumber] [int] NOT NULL,		--statement # within the batch. We need this b/c the same PKSQLStmtStoreID could be revisited
	
	--Important metadata
	[IsActive]				[bit] NOT NULL,
	[IsFirstInBatch]		[bit] NOT NULL,		--useful for deriving stats from this table to the AutoWho.BatchStats table
	[FirstCaptureTime]		[datetime] NOT NULL,
	[LastCaptureTime]		[datetime] NOT NULL,	--for stuff still running, we keep updating this until we've closed the statement.
	[PreviousCaptureTime]	[datetime] NULL,	--points to the SPIDCaptureTime for this batch (spid/request/TimeIdentifier) that 
												--immediately precedes FirstCaptureTime. This helps us calculate many of the metric fields

	[NumCapturesSeen]		[int] NULL,


	[ContextDBID]		[smallint] NULL,	--The sess__database_id value at FirstCaptureTime

	[count_status_running]	[int] NULL,		--rqst__status_code = 1
	[count_status_runnable]	[int] NULL,		--rqst__status_code = 2
	[count_status_sleeping]	[int] NULL,		--rqst__status_code = 3
	[count_status_suspended] [int] NULL,	--rqst__status_code = 4

	[CapturesBlocked]		[int] NULL,		--number of captures where the request was blocked
	[CapturesBlocker]		[int] NULL,		--or blocking (calc__blocking_session_id and calc__is_blocker)

	[SumOpenTransactionCount] [int] NULL,		--use this, along with NumCapturesSeen to derive an "average tran count" which can help us
												--see variability in tran nesting depth
	[MaxOpenTransactionCount] [int] NULL,
	[count_tranisolevel_1]	[int] NULL,		--Num of captures where rqst__transaction_isolation_level = 1
	[count_tranisolevel_2]	[int] NULL,
	[count_tranisolevel_3]	[int] NULL,
	[count_tranisolevel_4]	[int] NULL,
	[count_tranisolevel_5]	[int] NULL,

	[rqst__cpu_time]		[int] NULL,		--"rqst__cpu_time at LastCaptureTime" - "ISNULL(rqst__cpu_time at PreviousCaptureTime, 0)"
	[rqst__reads]			[bigint] NULL,	--these other fields are calculated similarly.
	[rqst__writes]			[bigint] NULL,
	[rqst__logical_reads]	[bigint] NULL,

	/* The below fields allow us to calc:
		- the growth of task usage over the course of the statement
		- the max amount of tempdb usage during the statement execution ( max of both task and sess)
		- the average amount of tempdb usage (sum of both task and sess / NumCapturesSeen)

		We don't store data to distinguish between user and internal or alloc and dealloc. 
		If that level of detail is needed, SAR must be consulted.
	*/
	[tempdb__start__task_allocated_pages] [bigint] NULL,	--all of these include both user and internal
	[tempdb__end__task_allocated_pages] [bigint] NULL,
	[tempdb__max__task_allocated_pages] [bigint] NULL,
	[tempdb__max__sess_allocated_pages] [bigint] NULL,
	[tempdb__sum__task_allocated_pages] [bigint] NULL,		--allows us to calc an average
	[tempdb__sum__sess_allocated_pages] [bigint] NULL,

	[tempdb__max_CalculatedNumberOfTasks] [smallint] NULL,	--Per statement, essentially letting us see the impact of DOP
	[tempdb__sum_CalculatedNumberOfTasks] [int] NULL,		--allows us to calc an average

	[mgrant__grant_wait_ms]				[int] NULL,		--calc'd off the datediff of mgrant__request_time and grant_time
															--from the last capture for each statement
	[mgrant__requested_memory_kb] [bigint] NULL,		--base these off the last capture for each statement
	[mgrant__granted_memory_kb] [bigint] NULL,
	[mgrant__used_memory_kb] [bigint] NULL,
	[mgrant__max_used_memory_kb] [bigint] NULL,
	[mgrant__dop] [smallint] NULL,

	[calc__duration_ms] [bigint] NULL,				--calculated similarly to the cpu/read/write metrics above

	--[calc__tmr_wait] [tinyint] NULL,		may add logic for these fields later
	--[calc__node_info] [nvarchar](40) NOT NULL,
	--[calc__status_info] [nvarchar](20) NOT NULL,

	[FKInputBufferStoreID] [bigint] NULL,			--we store the first non-NULL value for the statement.
	[FKQueryPlanStmtStoreID] [bigint] NULL,			--we store the first non-NULL value for the statement.

	--Stuff from TAW. We join in the TAW records between FirstCaptureTime and LastCaptureTime for each statement.
	[context_switches_count] [bigint] NULL,
	[total_wait_duration_ms] [bigint] NULL,
	[cxp_wait_duration_ms] [bigint] NULL,
	[wait_details] [nvarchar](1000) NULL,
	[count_tstate_suspended] [int] NULL,
	[count_tstate_running] [int] NULL,
	[count_tstate_runnable] [int] NULL,
	[count_tstate_pending] [int] NULL,
	[count_tstate_spinloop] [int] NULL,

 CONSTRAINT [PKAutoWhoStmtStats] PRIMARY KEY CLUSTERED 
(
	[session_id] ASC,
	[request_id] ASC,
	[TimeIdentifier] ASC,
	[PKSQLStmtStoreID] ASC,
	[StatementSequenceNumber] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
