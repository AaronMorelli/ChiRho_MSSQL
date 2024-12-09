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

	FILE NAME: ServerEye_DimPerformanceCounter.Table.sql

	TABLE NAME: ServerEye_DimPerformanceCounter

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores a unique listing of performance counters and how frequently they are called
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimPerformanceCounter(
	[DimPerformanceCounterID]	[int] IDENTITY(1,1) NOT NULL,
	[object_name]				[nvarchar](128) NOT NULL,
	[counter_name]				[nvarchar](128) NOT NULL,
	[instance_name]				[nvarchar](128) NOT NULL,	--set to empty string if NULL in DMV
	[cntr_type]					[int] NOT NULL,
	[CounterFrequency]			[tinyint] NOT NULL CONSTRAINT [DF_DimPerfCounter_CounterFrequency]  DEFAULT ((0)),
		--0=never collected, 1 = high freq, 2 = medium, 3 = low		don't really need batch counter collection category
		--The user can adjust these based on what they see or need.
		--The presentation procs will need to be written such that even if it is normal for a certain counter to be Hi-freq,
		-- there may not be a collection for that counter at that time and the presentation proc will just have to display blank.
PRIMARY KEY NONCLUSTERED 
(
	[DimPerformanceCounterID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimPerformanceCounter  WITH CHECK ADD  CONSTRAINT [CK_DimPerformanceCounterCounterFrequency] CHECK  (([CounterFrequency]=0 OR [CounterFrequency]=1 OR [CounterFrequency]=2 OR [CounterFrequency]=3))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimPerformanceCounter CHECK CONSTRAINT [CK_DimPerformanceCounterCounterFrequency]
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKDimPerformanceCounter] ON @@CHIRHO_SCHEMA@@.ServerEye_DimPerformanceCounter
(
	[object_name],
	[counter_name],
	[instance_name]
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE CLUSTERED INDEX CL_CounterFrequency ON @@CHIRHO_SCHEMA@@.ServerEye_DimPerformanceCounter
(
	[CounterFrequency]		--we cluster by the frequency so that the collector procs don't have to wait through the large number of counters every time they access this table
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO