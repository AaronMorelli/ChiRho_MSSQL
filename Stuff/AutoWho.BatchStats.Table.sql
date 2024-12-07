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

	FILE NAME: AutoWho_BatchStats.Table.sql

	TABLE NAME: AutoWho.BatchStats

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds aggregated statistics about user batches that have been observed by AutoWho
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [AutoWho].[BatchStats] (
	[session_id]			[smallint] NOT NULL,
	[request_id]			[smallint] NOT NULL,
	[TimeIdentifier]		[datetime] NOT NULL,
	
	[IsActive]				[bit] NOT NULL,
	[NumCapturesSeen]		[int] NULL,
	[sess__database_id]		[smallint] NULL,

	[count_status_running]	[int] NULL,		--rqst__status_code = 1
	[count_status_runnable]	[int] NULL,		--rqst__status_code = 2
	[count_status_sleeping]	[int] NULL,		--rqst__status_code = 3
	[count_status_suspended] [int] NULL,	--rqst__status_code = 4

	[CapturesBlocked]		[int] NULL,
	[CapturesBlocker]		[int] NULL,

	[SumOpenTransactionCount] [int] NULL,		--use this, along with NumCapturesSeen to derive an "average tran count" which can help us
												--see variability in tran nesting depth
	[MaxOpenTransactionCount] [int] NULL,
	[rqst__cpu_time]		[int] NULL,
	[rqst__reads]			[bigint] NULL,
	[rqst__writes]			[bigint] NULL,
	[rqst__logical_reads]	[bigint] NULL,
	[count_tranisolevel_1]	[int] NULL,		--rqst__transaction_isolation_level = 1
	[count_tranisolevel_2]	[int] NULL,
	[count_tranisolevel_3]	[int] NULL,
	[count_tranisolevel_4]	[int] NULL,
	[count_tranisolevel_5]	[int] NULL,

	/* The below fields allow us to calc:
		- the net effect (sess end - sess start) of the batch on session tempdb usage
		- the max amount of tempdb usage (summing max sess + max task)
		- the average amount of tempdb usage (sum / NumCapturesSeen)

		We don't store data to distinguish between user and internal or alloc and dealloc. 
		If that level of detail is needed, SAR must be consulted.
	*/
	[tempdb__start__sess_allocated_pages] [bigint] NULL,		--all of these include both user and internal
	[tempdb__end__sess_allocated_pages] [bigint] NULL,
	[tempdb__start__task_allocated_pages] [bigint] NULL,
	[tempdb__end__task_allocated_pages] [bigint] NULL,
	[tempdb__max__sess_allocated_pages] [bigint] NULL,
	[tempdb__max__task_allocated_pages] [bigint] NULL,
	[tempdb__sum__sess_allocated_pages] [bigint] NULL,		--based on the stmt stats table
	[tempdb__sum__task_allocated_pages] [bigint] NULL,


	[tempdb__max_CalculatedNumberOfTasks] [smallint] NULL,
	[tempdb__sum_CalculatedNumberOfTasks] [int] NULL,

	[mgrant__sum_grant_wait_ms]			[bigint] NULL,		--calc'd off the datediff of mgrant__request_time and grant_time
															--this is based on the stmt stats table

	[mgrant__requested_memory_kb] [bigint] NULL,
	[mgrant__required_memory_kb] [bigint] NULL,
	[mgrant__granted_memory_kb] [bigint] NULL,
	[mgrant__used_memory_kb] [bigint] NULL,
	[mgrant__max_used_memory_kb] [bigint] NULL,
	[mgrant__dop] [smallint] NULL,
	[calc__record_priority] [tinyint] NULL,
	[calc__is_compiling] [bit] NULL,
	[calc__duration_ms] [bigint] NULL,
	[calc__blocking_session_id] [smallint] NULL,
	[calc__block_relevant] [tinyint] NULL,
	[calc__wait_details] [nvarchar](max) NULL,
	[calc__return_to_user] [smallint] NULL,
	[calc__is_blocker] [bit] NULL,
	[calc__sysspid_isinteresting] [bit] NULL,
	[calc__tmr_wait] [tinyint] NULL,
	[calc__threshold_ignore] [bit] NULL,
	[calc__node_info] [nvarchar](40) NOT NULL,
	[calc__status_info] [nvarchar](20) NOT NULL,

	[FKInputBufferStoreID] [bigint] NULL,
 CONSTRAINT [PKAutoWhoBatchStats] PRIMARY KEY CLUSTERED 
(
	[session_id] ASC,
	[request_id] ASC,
	[TimeIdentifier] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING OFF
GO
