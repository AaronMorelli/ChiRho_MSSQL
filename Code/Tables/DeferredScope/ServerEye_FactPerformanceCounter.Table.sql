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

	FILE NAME: ServerEye_FactPerformanceCounter.Table.sql

	TABLE NAME: ServerEye_FactPerformanceCounter

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots FactPerformanceCounter (in both Hi- and Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_FactPerformanceCounter(
	[UTCCaptureTime] [datetime] NOT NULL,
	[DimPerformanceCounterID] [int] NOT NULL,
	[cntr_value] [bigint] NOT NULL,
 CONSTRAINT [PKFactPerformanceCounter] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[DimPerformanceCounterID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO