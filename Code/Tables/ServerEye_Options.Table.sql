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

	FILE NAME: ServerEye_Options.Table.sql

	TABLE NAME: ServerEye_Options

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores just 1 row, with 1 column per Server option.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options(
	[RowID] [int] NOT NULL CONSTRAINT [DF_SEOptions_RowID]  DEFAULT ((1)),
	[ServerEyeEnabled] [nchar](1) NOT NULL CONSTRAINT [DF_SEOptions_ServerEyeEnabled]  DEFAULT (N'Y'),
	[BeginTime] [time](0) NOT NULL CONSTRAINT [DF_SEOptions_BeginTime]  DEFAULT (('00:00:00')),
	[EndTime] [time](0) NOT NULL CONSTRAINT [DF_SEOptions_EndTime]  DEFAULT (('23:59:30')),
	[BeginEndIsUTC] [nchar](1) NOT NULL CONSTRAINT [DF_SEOptions_BeginEndIsUTC]  DEFAULT (N'N'),
	[IntervalLength] [smallint] NOT NULL CONSTRAINT [DF_SEOptions_IntervalLength]  DEFAULT ((1)),
	[IncludeDBs] [nvarchar](4000) NOT NULL CONSTRAINT [DF_SEOptions_IncludeDBs]  DEFAULT (N''),
	[ExcludeDBs] [nvarchar](4000) NOT NULL CONSTRAINT [DF_SEOptions_ExcludeDBs]  DEFAULT (N''),
	[Retention_Days] [int] NOT NULL CONSTRAINT [DF_SEOptions_Retention_IdleSPIDs_NoTran]  DEFAULT ((30)),
	[DebugSpeed] [nchar](1) NOT NULL CONSTRAINT [DF_SEOptions_DebugSpeed]  DEFAULT (N'Y'),
	[PurgeUnextractedData] [nchar](1) NOT NULL CONSTRAINT [DF_SEOptions_PurgeUnextractedData]  DEFAULT (N'Y'),
 CONSTRAINT [PKServerEyeOptions] PRIMARY KEY CLUSTERED 
(
	[RowID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsForce1Row] CHECK  (([RowID]=(1)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsForce1Row]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsServerEyeEnabled] CHECK  (([ServerEyeEnabled]=N'Y' OR [ServerEyeEnabled]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsServerEyeEnabled]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsBeginEndTime] CHECK  ([BeginTime]<>[EndTime])
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsBeginEndTime]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsBeginEndIsUTC] CHECK  (([BeginEndIsUTC]=N'Y' OR [BeginEndIsUTC]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsBeginEndIsUTC]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsIntervalLength] CHECK  (([IntervalLength] IN (1, 2, 5)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsIntervalLength]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsRetention_Days] CHECK  (([Retention_Days]>=(3)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsRetention_Days]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsDebugSpeed] CHECK  (([DebugSpeed]=N'Y' OR [DebugSpeed]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsDebugSpeed]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options  WITH CHECK ADD  CONSTRAINT [CK_SEOptionsPurgeUnextractedData] CHECK  (([PurgeUnextractedData]=N'N' OR [PurgeUnextractedData]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_Options CHECK CONSTRAINT [CK_SEOptionsPurgeUnextractedData]
GO
--
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Enforces just 1 row in the table' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'RowID'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Master on/off switch for the ServerEye tracing portion of ChiRho. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'ServerEyeEnabled'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The time at which to start running the ServerEye trace.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'BeginTime'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The time at which to stop running the ServerEye trace.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'EndTime'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether BeginTime and EndTime are specified in UTC or not.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'BeginEndIsUTC'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The length, in minutes, of each interval. If ServerEye collects its data almost instantaneously, this is the time between ServerEye executions. However, if ServerEye runs several seconds or more, the idle duration is adjusted so that the next ServerEye execution falls roughly on a 1 minute boundary point' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'IntervalLength'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A comma-delimited list of database names to INCLUDE in various metric captures. DBs not in this list will not be included for DB-level metrics.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'IncludeDBs'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A comma-delimited list of database names to EXCLUDE in various metric captures.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'ExcludeDBs'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of days to retain data captured by the ServerEye_Collector procedure.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'Retention_Days'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to capture duration info for each significant statement in the ServerEye_Collector procedure and write that duration info to a table.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'DebugSpeed'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether purge is allowed to delete data for capture times rows (in ServerEye_CaptureTimes) that has not been extracted for the DW yet. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'Options', @level2type=N'COLUMN',@level2name=N'PurgeUnextractedData'
GO