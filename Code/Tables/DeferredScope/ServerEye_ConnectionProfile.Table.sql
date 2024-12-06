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

	FILE NAME: ServerEye_ConnectionProfile.Table.sql

	TABLE NAME: ServerEye_ConnectionProfile

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores a unique combo of session attributes, essentially as a junk dimension
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_ConnectionProfile(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[DimUserProfileConnID] [int] NOT NULL,
	[DimUserProfileProgramID] [int] NOT NULL,
	[DimUserProfileLoginID]	[int] NOT NULL,
	[NumRows] [int] NOT NULL,
	[conn__connect_time_min] [datetime] NOT NULL,
	[conn__connect_time_max] [datetime] NOT NULL,
	[conn__num_reads_sum] [bigint] NULL,
	[conn__num_reads_max] [bigint] NULL,
	[conn__num_writes_sum] [bigint] NULL,
	[conn__num_writes_max] [bigint] NULL,
	[conn__last_read_min] [datetime] NULL,
	[conn__last_read_max] [datetime] NULL,
	[conn__last_write_min] [datetime] NULL,
	[conn__last_write_max] [datetime] NULL,
	[sess__login_time_min] [datetime] NOT NULL,
	[sess__login_time_max] [datetime] NOT NULL,
	[sess__last_request_start_time_min] [datetime] NOT NULL,
	[sess__last_request_start_time_max] [datetime] NOT NULL,
	[sess__last_request_end_time_min] [datetime] NULL,
	[sess__last_request_end_time_max] [datetime] NULL,
	[sess__cpu_time_sum] [bigint] NOT NULL,
	[sess__cpu_time_max] [bigint] NOT NULL,
	[sess__reads_sum] [bigint] NOT NULL,
	[sess__reads_max] [bigint] NOT NULL,
	[sess__writes_sum] [bigint] NOT NULL,
	[sess__writes_max] [bigint] NOT NULL,
	[sess__logical_reads_sum] [bigint] NOT NULL,
	[sess__logical_reads_max] [bigint] NOT NULL,
	[rqst__start_time_min] [datetime] NULL,
	[rqst__start_time_max] [datetime] NULL
) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKConnectionProfile] ON @@CHIRHO_SCHEMA@@.ServerEye_ConnectionProfile(
	[UTCCaptureTime],
	[LocalCaptureTime],
	[DimUserProfileConnID],
	[DimUserProfileProgramID],
	[DimUserProfileLoginID]
);
GO