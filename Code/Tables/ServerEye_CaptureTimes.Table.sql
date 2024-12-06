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

	FILE NAME: ServerEye_CaptureTimes.Table.sql

	TABLE NAME: ServerEye_CaptureTimes

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Holds 1 row for each run of the ServerEye_Collector procedure, identifying the time and basic stats of the run.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_CaptureTimes (
	[CollectionInitiatorID]			[tinyint] NOT NULL,
	[UTCCaptureTime]				[datetime] NOT NULL,
	[LocalCaptureTime]				[datetime] NOT NULL,
	
	[HighFrequencySuccessful]		[smallint] NOT NULL,		-- -1 when fails, 1 when successful. (Can't be 0 as it always runs)
	[MediumFrequencySuccessful]		[smallint] NOT NULL,		-- -1 when fails, 0 when didn't run, 1 when successful
	[LowFrequencySuccessful]		[smallint] NOT NULL,		-- ditto
	[BatchFrequencySuccessful]		[smallint] NOT NULL,		-- ditto

	[RunWasSuccessful]				[smallint] NOT NULL,		--this is 1 when High, Medium, Low, and Batch are all successful (or didn't run). Otherwise, 0
	
	[PrevSuccessfulUTCCaptureTime]	[datetime] NULL,		--stores the most recent UTCCaptureTime where RunWasSuccessful=1
	[PrevSuccessfulMedium]			[datetime] NULL,		--stores the most recent UTCCaptureTime where RunWasSuccesful=1 AND MediumFrequencySuccessful=1
	[PrevSuccessfulLow]				[datetime] NULL,		--stores the most recent UTCCaptureTime where RunWasSuccesful=1 AND LowFrequencySuccessful=1
	[PrevSuccessfulBatch]			[datetime] NULL,		--stores the most recent UTCCaptureTime where RunWasSuccesful=1 AND BatchFrequencySuccessful=1
	
	[ExtractedForDW]				[tinyint] NOT NULL,
	[ServerEyeDuration_ms]			[int] NOT NULL,
	[DurationBreakdown]				[varchar](1000) NULL,
	
 CONSTRAINT [PKServerEyeCaptureTimes] PRIMARY KEY CLUSTERED 
(
	[CollectionInitiatorID] ASC,
	[UTCCaptureTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
CREATE UNIQUE NONCLUSTERED INDEX [UNCL_LocalCaptureTime_OTHERS] ON @@CHIRHO_SCHEMA@@.ServerEye_CaptureTimes
(
	[CollectionInitiatorID] ASC,
	[LocalCaptureTime] ASC
)
INCLUDE ( 	
	[UTCCaptureTime],
	[RunWasSuccessful],
	[PrevSuccessfulUTCCaptureTime],
	[HighFrequencySuccessful],
	[MediumFrequencySuccessful],
	[LowFrequencySuccessful],
	[BatchFrequencySuccessful],
	[ExtractedForDW],
	[ServerEyeDuration_ms],
	[DurationBreakdown]
) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
