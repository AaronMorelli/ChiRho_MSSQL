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

	FILE NAME: AutoWho_CaptureTimes.Table.sql

	TABLE NAME: AutoWho_CaptureTimes

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds 1 row for each run of the @@CHIRHO_SCHEMA@@.AutoWho_Collector
	procedure, identifying the time and basic stats of the run.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes (
	[CollectionInitiatorID]			[tinyint] NOT NULL,
	[UTCCaptureTime]				[datetime] NOT NULL,
	[SPIDCaptureTime]				[datetime] NOT NULL,
	[RunWasSuccessful]				[tinyint] NOT NULL,
	[PrevSuccessfulUTCCaptureTime]	[datetime] NULL,		--stores the most recent UTCCaptureTime where RunWasSuccessful=1
	[SpidsCaptured]					[int] NULL,
	[PostProcessed_StmtStats]		[tinyint] NOT NULL,
	[PostProcessed_Latch]			[tinyint] NOT NULL,
	[PostProcessed_Lock]			[tinyint] NOT NULL,
	[PostProcessed_NodeStatus]		[tinyint] NOT NULL,
	[ExtractedForDW]				[tinyint] NOT NULL,
	[CaptureSummaryPopulated]		[tinyint] NOT NULL,
	[CaptureSummaryDeltaPopulated]	[tinyint] NOT NULL,
	[AutoWhoDuration_ms]			[int] NOT NULL,
	[DurationBreakdown]				[varchar](1000) NULL,
	
 CONSTRAINT [PKAutoWhoCaptureTimes] PRIMARY KEY CLUSTERED 
(
	[CollectionInitiatorID] ASC,
	[UTCCaptureTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
CREATE UNIQUE NONCLUSTERED INDEX [UNCL_RunWasSuccessful_OTHERS] ON @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes
(
	[RunWasSuccessful] ASC,
	[CaptureSummaryPopulated] ASC,
	[CollectionInitiatorID] ASC,
	[SPIDCaptureTime] ASC
)
INCLUDE ( 	[AutoWhoDuration_ms]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UNCL_SPIDCaptureTime_OTHERS] ON @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes
(
	[CollectionInitiatorID] ASC,
	[SPIDCaptureTime] ASC
)
INCLUDE ( 	
	[UTCCaptureTime],
	[RunWasSuccessful],
	[SpidsCaptured],
	[PostProcessed_StmtStats],
	[PostProcessed_Latch],
	[PostProcessed_Lock],
	[PostProcessed_NodeStatus],
	[ExtractedForDW],
	[CaptureSummaryPopulated],
	[CaptureSummaryDeltaPopulated],
	[AutoWhoDuration_ms],
	[DurationBreakdown]
) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
