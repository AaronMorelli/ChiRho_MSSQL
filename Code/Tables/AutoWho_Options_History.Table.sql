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

	FILE NAME: AutoWho_Options_History.Table.sql

	TABLE NAME: AutoWho_Options_History

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Populated by triggers on the @@CHIRHO_SCHEMA@@.AutoWho_Options table every time
	any option value changes.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_Options_History(
	[HistoryInsertDate] [datetime] NOT NULL,
	[HistoryInsertDateUTC] [datetime] NOT NULL,
	[LastModifiedUser] [nvarchar](128) NOT NULL,
	[TriggerAction] [nvarchar](40) NOT NULL,
	[RowID] [int] NOT NULL,
	[AutoWhoEnabled] [nchar](1) NOT NULL,
	[BeginTime] [time](0) NOT NULL,
	[EndTime] [time](0) NOT NULL,
	[BeginEndIsUTC] [nchar](1) NOT NULL,
	[IntervalLength] [smallint] NOT NULL,
	[IncludeIdleWithTran] [nchar](1) NOT NULL,
	[IncludeIdleWithoutTran] [nchar](1) NOT NULL,
	[DurationFilter] [int] NOT NULL,
	[IncludeDBs] [nvarchar](4000) NOT NULL,
	[ExcludeDBs] [nvarchar](4000) NOT NULL,
	[HighTempDBThreshold] [int] NOT NULL,
	[CollectSystemSpids] [nchar](1) NOT NULL,
	[HideSelf] [nchar](1) NOT NULL,
	[ObtainBatchText] [nchar](1) NOT NULL,
	[ObtainQueryPlanForStatement] [nchar](1) NOT NULL,
	[ObtainQueryPlanForBatch] [nchar](1) NOT NULL,
	[ObtainLocksForBlockRelevantThreshold] [int] NOT NULL,
	[InputBufferThreshold] [int] NOT NULL,
	[ParallelWaitsThreshold] [int] NOT NULL,
	[QueryPlanThreshold] [int] NOT NULL,
	[QueryPlanThresholdBlockRel] [int] NOT NULL,
	[BlockingChainThreshold] [int] NOT NULL,
	[BlockingChainDepth] [tinyint] NOT NULL,
	[TranDetailsThreshold] [int] NOT NULL,
	[MediumDurationThreshold] [int] NOT NULL,
	[HighDurationThreshold] [int] NOT NULL,
	[BatchDurationThreshold] [int] NOT NULL,
	[LongTransactionThreshold] [int] NOT NULL,
	[Retention_IdleSPIDs_NoTran] [int] NOT NULL,
	[Retention_IdleSPIDs_WithShortTran] [int] NOT NULL,
	[Retention_IdleSPIDs_WithLongTran] [int] NOT NULL,
	[Retention_IdleSPIDs_HighTempDB] [int] NOT NULL,
	[Retention_ActiveLow] [int] NOT NULL,
	[Retention_ActiveMedium] [int] NOT NULL,
	[Retention_ActiveHigh] [int] NOT NULL,
	[Retention_ActiveBatch] [int] NOT NULL,
	[Retention_CaptureTimes] [int] NOT NULL,
	[DebugSpeed] [nchar](1) NOT NULL,
	[ThresholdFilterRefresh] [smallint] NOT NULL,
	[SaveBadDims] [nchar](1) NOT NULL,
	[Enable8666] [nchar](1) NOT NULL,
	[ResolvePageLatches] [nchar](1) NOT NULL,
	[ResolveLockWaits] [nchar](1) NOT NULL,
	[PurgeUnextractedData] [nchar](1) NOT NULL,
 CONSTRAINT [PKAutoWhoOptions_History] PRIMARY KEY CLUSTERED 
(
	[HistoryInsertDate] ASC,
	[TriggerAction] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
