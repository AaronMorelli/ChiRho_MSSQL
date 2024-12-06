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

	FILE NAME: ServerEye_dm_resource_governor_resource_pool_volumes.Table.sql

	TABLE NAME: ServerEye_dm_resource_governor_resource_pool_volumes

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_resource_governor_resource_pool_volumes (in Med-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_resource_governor_resource_pool_volumes(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[pool_id] [int] NOT NULL,
	[volume_name] [nvarchar](256) NOT NULL,
	[read_io_queued_total] [int] NOT NULL,
	[read_io_issued_total] [int] NOT NULL,
	[read_io_completed_total] [int] NOT NULL,
	[read_io_throttled_total] [int] NOT NULL,
	[read_bytes_total] [bigint] NOT NULL,
	[read_io_stall_total_ms] [bigint] NOT NULL,
	[read_io_stall_queued_ms] [bigint] NOT NULL,
	[write_io_queued_total] [int] NOT NULL,
	[write_io_issued_total] [int] NOT NULL,
	[write_io_completed_total] [int] NOT NULL,
	[write_io_throttled_total] [int] NOT NULL,
	[write_bytes_total] [bigint] NOT NULL,
	[write_io_stall_total_ms] [bigint] NOT NULL,
	[write_io_stall_queued_ms] [bigint] NOT NULL,
	[io_issue_violations_total] [int] NOT NULL,
	[io_issue_delay_total_ms] [bigint] NOT NULL,
 CONSTRAINT [PKdm_resource_governor_resource_pool_volumes] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[pool_id] ASC,
	[volume_name]
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO