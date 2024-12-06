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

	FILE NAME: ServerEye_dm_os_memory_broker_clerks.Table.sql

	TABLE NAME: ServerEye_dm_os_memory_broker_clerks

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots dm_os_memory_broker_clerks (in Hi-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_os_memory_broker_clerks(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[clerk_name] [nvarchar](256) NOT NULL,
	[total_kb] [bigint] NOT NULL,
	[simulated_kb] [bigint] NOT NULL,
	[simulation_benefit] [float] NOT NULL,
	[internal_benefit] [float] NOT NULL,
	[external_benefit] [float] NOT NULL,
	[value_of_memory] [float] NOT NULL,
	[periodic_freed_kb] [bigint] NOT NULL,
	[internal_freed_kb] [bigint] NOT NULL,
 CONSTRAINT [PKdm_os_memory_broker_clerks] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[clerk_name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO