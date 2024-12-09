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

	FILE NAME: ServerEye_DimDBVolume.Table.sql

	TABLE NAME: ServerEye_DimDBVolume

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores the volumes observed through dm_os_volume_stats
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimDBVolume(
	[DimDBVolumeID]			[smallint] IDENTITY(1,1) NOT NULL,
	[volume_id]				[nvarchar](256) NOT NULL,
	[volume_mount_point]	[nvarchar](256) NOT NULL,
	[logical_volume_name]	[nvarchar](256) NOT NULL,
	[file_system_type]		[nvarchar](256) NOT NULL,
	[supports_compression]	[tinyint] NOT NULL,
	[supports_alternate_streams] [tinyint] NOT NULL,
	[supports_sparse_files] [tinyint] NOT NULL,
	[is_read_only]			[tinyint] NOT NULL,
	[is_compressed]			[tinyint] NOT NULL,
	[TimeAdded]				[datetime] NOT NULL  CONSTRAINT [DF_DimDBVolume_TimeAdded]  DEFAULT (GETDATE()),
	[TimeAddedUTC]			[datetime] NOT NULL CONSTRAINT [DF_DimDBVolume_TimeAddedUTC]  DEFAULT (GETUTCDATE()),
PRIMARY KEY CLUSTERED 
(
	[DimDBVolumeID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKDimDBVolume] ON @@CHIRHO_SCHEMA@@.ServerEye_DimDBVolume
(
	[volume_id] ASC,
	[volume_mount_point] ASC,
	[logical_volume_name] ASC,
	[file_system_type] ASC,
	[supports_compression] ASC,
	[supports_alternate_streams] ASC,
	[supports_sparse_files] ASC, 
	[is_read_only] ASC,
	[is_compressed] ASC
)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO