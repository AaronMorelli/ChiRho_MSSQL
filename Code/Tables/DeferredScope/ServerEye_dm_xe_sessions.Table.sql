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

	FILE NAME: ServerEye_dm_xe_sessions.Table.sql

	TABLE NAME: ServerEye_dm_xe_sessions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_xe_sessions (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_xe_sessions(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[address] [varbinary](8) NOT NULL,
	[name] [nvarchar](256) NOT NULL,
	[pending_buffers] [int] NOT NULL,
	[total_regular_buffers] [int] NOT NULL,
	[regular_buffer_size] [bigint] NOT NULL,
	[total_large_buffers] [int] NOT NULL,
	[large_buffer_size] [bigint] NOT NULL,
	[total_buffer_size] [bigint] NOT NULL,
	[buffer_policy_flags] [int] NOT NULL,
	[buffer_policy_desc] [nvarchar](256) NOT NULL,
	[flags] [int] NOT NULL,
	[flag_desc] [nvarchar](256) NOT NULL,
	[dropped_event_count] [int] NOT NULL,
	[dropped_buffer_count] [int] NOT NULL,
	[blocked_event_fire_time] [int] NOT NULL,
	[create_time] [datetime] NOT NULL,
	[largest_event_dropped_size] [int] NOT NULL,
	[session_source] [nvarchar](256) NOT NULL,
 CONSTRAINT [PKdm_xe_sessions] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO