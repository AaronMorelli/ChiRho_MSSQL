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

	FILE NAME: AutoWho_CaptureSummary.Table.sql

	TABLE NAME: AutoWho_CaptureSummary

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds the aggregated results from the AutoWho core tables
	for time ranges resulting from sp_XR_SessionSummary calls.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary(
	[CollectionInitiatorID] [tinyint] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,
	[SPIDCaptureTime] [datetime] NOT NULL,
	[CapturedSPIDs] [int] NOT NULL,
	[Active] [int] NOT NULL,
	[ActLongest_ms] [bigint] NULL,
	[ActAvg_ms] [bigint] NULL,
	[Act0to1] [int] NULL,
	[Act1to5] [int] NULL,
	[Act5to10] [int] NULL,
	[Act10to30] [int] NULL,
	[Act30to60] [int] NULL,
	[Act60to300] [int] NULL,
	[Act300plus] [int] NULL,
	[IdleWithOpenTran] [int] NOT NULL,
	[IdlOpTrnLongest_ms] [bigint] NULL,
	[IdlOpTrnAvg_ms] [bigint] NULL,
	[IdlOpTrn0to1] [int] NULL,
	[IdlOpTrn1to5] [int] NULL,
	[IdlOpTrn5to10] [int] NULL,
	[IdlOpTrn10to30] [int] NULL,
	[IdlOpTrn30to60] [int] NULL,
	[IdlOpTrn60to300] [int] NULL,
	[IdlOpTrn300plus] [int] NULL,
	[WithOpenTran] [int] NOT NULL,
	[TranDurLongest_ms] [bigint] NULL,
	[TranDurAvg_ms] [bigint] NULL,
	[TranDur0to1] [int] NULL,
	[TranDur1to5] [int] NULL,
	[TranDur5to10] [int] NULL,
	[TranDur10to30] [int] NULL,
	[TranDur30to60] [int] NULL,
	[TranDur60to300] [int] NULL,
	[TranDur300plus] [int] NULL,
	[Blocked] [int] NOT NULL,
	[BlockedLongest_ms] [bigint] NULL,
	[BlockedAvg_ms] [bigint] NULL,
	[Blocked0to1] [int] NULL,
	[Blocked1to5] [int] NULL,
	[Blocked5to10] [int] NULL,
	[Blocked10to30] [int] NULL,
	[Blocked30to60] [int] NULL,
	[Blocked60to300] [int] NULL,
	[Blocked300plus] [int] NULL,
	[WaitingSPIDs] [int] NOT NULL,
	[WaitingTasks] [int] NOT NULL,
	[WaitingTaskLongest_ms] [bigint] NULL,
	[WaitingTaskAvg_ms] [bigint] NULL,
	[WaitingTask0to1] [int] NULL,
	[WaitingTask1to5] [int] NULL,
	[WaitingTask5to10] [int] NULL,
	[WaitingTask10to30] [int] NULL,
	[WaitingTask30to60] [int] NULL,
	[WaitingTask60to300] [int] NULL,
	[WaitingTask300plus] [int] NULL,
	[AllocatedTasks] [int] NOT NULL,
	[QueryMemoryRequested_KB] [bigint] NOT NULL,
	[QueryMemoryGranted_KB] [bigint] NOT NULL,
	[LargestMemoryGrant_KB] [bigint] NULL,
	[TempDB_pages] [bigint] NOT NULL,
	[LargestTempDBConsumer_pages] [bigint] NULL,
	[CPUused] [bigint] NOT NULL,
	[CPUDelta] [bigint] NULL,
	[LargestCPUConsumer] [bigint] NULL,
	[WritesDone] [bigint] NOT NULL,
	[WritesDelta] [bigint] NULL,
	[LargestWriter] [bigint] NULL,
	[LogicalReadsDone] [bigint] NOT NULL,
	[LogicalReadsDelta] [bigint] NULL,
	[LargestLogicalReader] [bigint] NULL,
	[PhysicalReadsDone] [bigint] NOT NULL,
	[PhysicalReadsDelta] [bigint] NULL,
	[LargestPhysicalReader] [bigint] NULL,
	[TlogUsed_bytes] [bigint] NULL,
	[LargestLogWriter_bytes] [bigint] NULL,
	[BlockingGraph] [bit] NOT NULL,
	[LockDetails] [bit] NOT NULL,
	[TranDetails] [bit] NOT NULL,
 CONSTRAINT [PKAutoWhoCaptureSummary] PRIMARY KEY CLUSTERED 
(
	[CollectionInitiatorID] ASC,
	[UTCCaptureTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
