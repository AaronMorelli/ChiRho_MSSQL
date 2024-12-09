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

	FILE NAME: ServerEye_systraces.Table.sql

	TABLE NAME: ServerEye_systraces

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.systraces (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_systraces(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[id] [int] NOT NULL,
	[status] [int] NOT NULL,
	[path] [nvarchar](260) NULL,
	[max_size] [bigint] NULL,
	[stop_time] [datetime] NULL,
	[max_files] [int] NULL,
	[is_rowset] [bit] NULL,
	[is_rollover] [bit] NULL,
	[is_shutdown] [bit] NULL,
	[is_default] [bit] NULL,
	[buffer_count] [int] NULL,
	[buffer_size] [int] NULL,
	[file_position] [bigint] NULL,
	[reader_spid] [int] NULL,
	[start_time] [datetime] NULL,
	[last_event_time] [datetime] NULL,
	[event_count] [bigint] NULL,
	[dropped_event_count] [int] NULL,
 CONSTRAINT [PKsystraces] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO