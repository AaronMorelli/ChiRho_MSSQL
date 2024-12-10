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

	FILE NAME: AutoWho_UserCollectionOptions.Table.sql

	TABLE NAME: AutoWho_UserCollectionOptions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores sets of config options that control what the Collector gathers when run through user-initiated traces.
			Having multiple sets of config options allows AutoWho to balance the performance of the Collector with
			the parameters chosen by the user.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions(
	[OptionSet] [nvarchar](50) NOT NULL CONSTRAINT [DF_UserCollectionOptions_OptionSet]  DEFAULT (N'QueryProgress'),
	[IncludeIdleWithTran] [nchar](1) NOT NULL,
	[IncludeIdleWithoutTran] [nchar](1) NOT NULL,
	[DurationFilter] [int] NOT NULL,
	[IncludeDBs] [nvarchar](4000) NOT NULL,
	[ExcludeDBs] [nvarchar](4000) NOT NULL,
	[HighTempDBThreshold] [int] NOT NULL,
	[CollectSystemSpids] [nchar](1) NOT NULL,
	[HideSelf] [nchar](1) NOT NULL,
	[ObtainBatchText] [nchar](1) NOT NULL,
	[ObtainQueryPlanForStatement] [nchar](1) NOT NULL,
	[ObtainQueryPlanForBatch] [nchar](1) NOT NULL,
	[ObtainLocksForBlockRelevantThreshold] [int] NOT NULL,
	[InputBufferThreshold] [int] NOT NULL,
	[ParallelWaitsThreshold] [int] NOT NULL,
	[QueryPlanThreshold] [int] NOT NULL,
	[QueryPlanThresholdBlockRel] [int] NOT NULL,
	[BlockingChainThreshold] [int] NOT NULL,
	[BlockingChainDepth] [tinyint] NOT NULL,
	[TranDetailsThreshold] [int] NOT NULL,
	[DebugSpeed] [nchar](1) NOT NULL,
	[SaveBadDims] [nchar](1) NOT NULL,
	[Enable8666] [nchar](1) NOT NULL,
	[ResolvePageLatches] [nchar](1) NOT NULL,
	[ResolveLockWaits] [nchar](1) NOT NULL,
	[UseBackgroundThresholdIgnore] [nchar](1) NOT NULL CONSTRAINT [DF_UserCollectionOptions_UseBackgroundThresholdIgnore]  DEFAULT (N'Y'),
 CONSTRAINT [PKUserCollectionOptions] PRIMARY KEY CLUSTERED 
(
	[OptionSet] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptions_OptionSet] CHECK  (([OptionSet]=N'SessionViewerFull' OR [OptionSet]=N'SessionViewerCommonFeatures' OR [OptionSet]=N'SessionViewerInfrequentFeatures' OR [OptionSet]=N'SessionViewerMinimal' OR [OptionSet]=N'QueryProgress'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptions_OptionSet]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsBlockingChainDepth] CHECK  (([BlockingChainDepth]>=(0) AND [BlockingChainDepth]<=(10)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsBlockingChainDepth]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsBlockingChainThreshold] CHECK  (([BlockingChainThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsBlockingChainThreshold]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsCollectSystemSpids] CHECK  (([CollectSystemSpids]=N'N' OR [CollectSystemSpids]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsCollectSystemSpids]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsDebugSpeed] CHECK  (([DebugSpeed]=N'Y' OR [DebugSpeed]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsDebugSpeed]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsDurationFilter] CHECK  (([DurationFilter]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsDurationFilter]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsEnable8666] CHECK  (([Enable8666]=N'Y' OR [Enable8666]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsEnable8666]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsHideSelf] CHECK  (([HideSelf]=N'Y' OR [HideSelf]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsHideSelf]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsHighTempDBThreshold] CHECK  (([HighTempDBThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsHighTempDBThreshold]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsIncludeIdleWithoutTran] CHECK  (([IncludeIdleWithoutTran]=N'N' OR [IncludeIdleWithoutTran]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsIncludeIdleWithoutTran]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsIncludeIdleWithTran] CHECK  (([IncludeIdleWithTran]=N'N' OR [IncludeIdleWithTran]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsIncludeIdleWithTran]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsInputBufferThreshold] CHECK  (([InputBufferThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsInputBufferThreshold]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsObtainBatchText] CHECK  (([ObtainBatchText]=N'Y' OR [ObtainBatchText]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsObtainBatchText]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsObtainLocksForBlockRelevantThreshold] CHECK  (([ObtainLocksForBlockRelevantThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsObtainLocksForBlockRelevantThreshold]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsObtainQueryPlanForBatch] CHECK  (([ObtainQueryPlanForBatch]=N'Y' OR [ObtainQueryPlanForBatch]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsObtainQueryPlanForBatch]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsObtainQueryPlanForStatement] CHECK  (([ObtainQueryPlanForStatement]=N'N' OR [ObtainQueryPlanForStatement]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsObtainQueryPlanForStatement]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsParallelWaitsThreshold] CHECK  (([ParallelWaitsThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsParallelWaitsThreshold]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsQPBvsQP] CHECK  (([QueryPlanThresholdBlockRel]<=[QueryPlanThreshold]))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsQPBvsQP]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsQueryPlanThreshold] CHECK  (([QueryPlanThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsQueryPlanThreshold]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsQueryPlanThresholdBlockRel] CHECK  (([QueryPlanThresholdBlockRel]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsQueryPlanThresholdBlockRel]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsResolveLockWaits] CHECK  (([ResolveLockWaits]=N'Y' OR [ResolveLockWaits]=N'N'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsResolveLockWaits]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsResolvePageLatches] CHECK  (([ResolvePageLatches]=N'N' OR [ResolvePageLatches]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsResolvePageLatches]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsSaveBadDims] CHECK  (([SaveBadDims]=N'N' OR [SaveBadDims]=N'Y'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsSaveBadDims]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions  WITH CHECK ADD  CONSTRAINT [CK_UserCollectionOptionsTranDetailsThreshold] CHECK  (([TranDetailsThreshold]>=(0)))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions CHECK CONSTRAINT [CK_UserCollectionOptionsTranDetailsThreshold]
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Enables sp_XR_SessionViewer and sp_XR_QueryProgress to have their own collection configurations of varying completeness and performance.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'OptionSet'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to collect sessions that are not actively running a batch but DO have an open transaction.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'IncludeIdleWithTran'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to collect sessions that are completely idle (no running batch, no open transactions)' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'IncludeIdleWithoutTran'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'When > 0, filters out spids whose "effective duration" (in milliseconds) is < this duration. For running SPIDs, the "effective duration" is the duration of the current batch (based on request start_time). For idle SPIDs, it is the time since the last_request_end_time value, aka the time the spid has been idle. Takes a number between 0 and max(int)' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'DurationFilter'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A comma-delimited list of database names to INCLUDE (this is the context DB of the SPID, not necessarily the object DB of the proc/function/trigger/etc). SPIDs with a context DB other than in this list will be excluded unless they are blockers of an included SPID.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'IncludeDBs'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A comma-delimited list of database names to EXCLUDE (this is the context DB of the SPID, not necessarily the object DB of the proc/function/trigger/etc). SPIDs with a context DB in this list will be excluded unless they are blockers of an included SPID.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ExcludeDBs'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The threshold (in # of 8KB pages) at which point a SPID becomes a High TempDB user. SPIDs with TempDB usage above this threshold are always captured, regardless of whether they are idle or have open trans or not.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'HighTempDBThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to collect system spids (typically session_id <=50, but not always). Takes "Y" or "N". If "Y", only "interesting" system spids (those not in their normal wait/idle state) will be captured.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'CollectSystemSpids'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to hide the session that is running AutoWho. Takes "Y" or "N". "Y" is typically only useful when debugging AutoWho performance or resource utilization.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'HideSelf'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether the complete T-SQL batch is obtained. Takes "Y" or "N". Regardless of this value, the text of the current statement for active spids is always obtained.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ObtainBatchText'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether statement-level query plans are obtained for the statements currently executed by running spids. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ObtainQueryPlanForStatement'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether query plans are obtained for the complete batch a spid is running. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ObtainQueryPlanForBatch'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of a milliseconds that an active spid must be blocked before a special query is run to grab info about what locks are held by all blocking-relevant (blocked and blockers) spids. Takes a number between 0 and max(smallint)' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ObtainLocksForBlockRelevantThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of milliseconds a spid must be running its current batch or be idle w/open tran before the Input Buffer is obtained for it. Takes a number between 0 and max(int)' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'InputBufferThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of milliseconds a batch running in parallel must be running before all of its tasks/waiting tasks DMV info is saved off to the TasksAndWaits table. The "top wait/top task" is always saved, regardless of the duration of the batch. Takes a number between 0 and max(int)' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ParallelWaitsThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of milliseconds that an active SPID must be running before its query plan will be captured.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'QueryPlanThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of seconds that an active SPID that is block-relevant must be running before its query plan will be captured.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'QueryPlanThresholdBlockRel'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The # of a milliseconds that an active spid must be blocked before the blocking chain code is executed. Note that the spids are not excluded from the Bchain, regardless of their duration, once the Bchain logic is triggered. Rather, this parameter just defines what kind of blocking duration must be seen for the Bchain logic to trigger.Takes a number between 0 and max(smallint)' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'BlockingChainThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'If the blocking chain code is executed, how many blocking-levels deep are collected and stored. Takes a number between 0 and 10 inclusive. 0 means "off", and the Bchain logic will never be executed' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'BlockingChainDepth'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'If an active spid has been running this long (unit=milliseconds), or an idle w/tran spid has been idle this long, its transaction data will be captured from the tran DMVs. Note that tran data is also captured for spids with sys.dm_exec_sessions.open_transaction_count > 0, regardless of duration.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'TranDetailsThreshold'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether to capture duration info for each significant statement in the AutoWho procedure and write that duration info to a table.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'DebugSpeed'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Saves spid records that could not be mapped to dimension keys to a separate table.' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'SaveBadDims'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether the AutoWho process will enable (undocumented) TF 8666; enabling this flag causes "InternalInfo" nodes to be added to the XML showplans that are captured by @@CHIRHO_SCHEMA@@.AutoWho_. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'Enable8666'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether the AutoWho procedure will attempt to resolve page and pageio latch strings into which object/index they map to via DBCC PAGE. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ResolvePageLatches'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Whether the AutoWho procedure will attempt to resolve page and pageio latch strings into which object/index they map to via DBCC PAGE. Takes "Y" or "N"' , @level0type=N'SCHEMA',@level0name=N'AutoWho', @level1type=N'TABLE',@level1name=N'UserCollectionOptions', @level2type=N'COLUMN',@level2name=N'ResolveLockWaits'
GO
