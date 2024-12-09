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

	FILE NAME: ServerEye_DBFileStats.Table.sql

	TABLE NAME: ServerEye_DBFileStats

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots DBFileStats (in Medium-frequency metrics)
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DBFileStats(
	[UTCCaptureTime]		[datetime] NOT NULL,
	[LocalCaptureTime]		[datetime] NOT NULL,
	[database_id]			[int] NOT NULL,
	[file_id]				[int] NOT NULL,
	[name]					[sysname] NOT NULL,
	[type_desc]				[nvarchar](60) NULL,
	[state_desc]			[nvarchar](60) NULL,
	[is_media_read_only]	[bit] NOT NULL,
	[is_read_only]			[bit] NOT NULL,
	[mf_size_pages]			[int] NOT NULL,	--size from sys.master_files
	[df_size_pages]			[int] NOT NULL,	--size from sys.database_files
	[pages_used]			[int] NULL,
	[DataSpaceName]			[nvarchar](128) NULL,
	[DataSpaceType]			[nvarchar](60) NULL,
	[DataSpaceIsDefault]	[bit] NULL,
	[FGIsReadOnly]			[bit] NULL
 CONSTRAINT [PKDBFileStats] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[database_id] ASC,
	[file_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO