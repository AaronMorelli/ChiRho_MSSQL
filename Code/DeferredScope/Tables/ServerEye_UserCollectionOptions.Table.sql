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

	FILE NAME: ServerEye_UserCollectionOptions.Table.sql

	TABLE NAME: ServerEye_UserCollectionOptions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores sets of config options that control what the Collector gathers when run through user-initiated traces.
			Having multiple sets of config options allows ServerEye to balance the performance of the Collector with
			the parameters chosen by the user.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_UserCollectionOptions(
	[OptionSet] [nvarchar](50) NOT NULL,
	[IncludeDBs] [nvarchar](4000) NOT NULL,
	[ExcludeDBs] [nvarchar](4000) NOT NULL,
	[DebugSpeed] [nchar](1) NOT NULL,
 CONSTRAINT [PKSEUserCollectionOptions] PRIMARY KEY CLUSTERED 
(
	[OptionSet] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
--ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_SEUserCollectionOptions_OptionSet] CHECK  (([OptionSet]=N'SessionViewerFull' OR [OptionSet]=N'SessionViewerCommonFeatures' OR [OptionSet]=N'SessionViewerInfrequentFeatures' OR [OptionSet]=N'SessionViewerMinimal' OR [OptionSet]=N'QueryProgress'))
--GO
--ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_UserCollectionOptions CHECK CONSTRAINT [CK_SEUserCollectionOptions_OptionSet]
--GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_SEUserCollectionOptionsDebugSpeed] CHECK  (([DebugSpeed]=N'Y' OR [DebugSpeed]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_UserCollectionOptions CHECK CONSTRAINT [CK_SEUserCollectionOptionsDebugSpeed]
GO
--TODO: EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Enables sp_XR_SessionViewer and sp_XR_QueryProgress to have their own collection configurations of varying completeness and performance.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'OptionSet'
--GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A comma-delimited list of database names to INCLUDE (this is the context DB of the SPID, not necessarily the object DB of the proc/function/trigger/etc). SPIDs with a context DB other than in this list will be excluded unless they are blockers of an included SPID.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'IncludeDBs'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A comma-delimited list of database names to EXCLUDE (this is the context DB of the SPID, not necessarily the object DB of the proc/function/trigger/etc). SPIDs with a context DB in this list will be excluded unless they are blockers of an included SPID.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ExcludeDBs'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to capture duration info for each significant statement in the ServerEye_Collector procedure and write that duration info to a table.' , @level0type=N'SCHEMA',@level0name=N'ServerEye', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'DebugSpeed'
GO