SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[ResetUserCollectionOptions] 
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

	FILE NAME: ServerEye.ResetUserCollectionOptions.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.ResetUserCollectionOptions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Deletes the rows in ServerEye.UserCollectionsOptions and re-inserts a row based on default values

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.ResetUserCollectionOptions

SELECT * FROM ServerEye.UserCollectionOptions
*/
AS
BEGIN
	SET NOCOUNT ON;

	--Since we are resetting the values back to install defaults, we persist
	-- anything that was there previously. (On initial install, this INSERT
	-- will have no effect since the table was just created and is empty).

	INSERT INTO [ServerEye].[UserCollectionOptions_History](
		[HistoryInsertDate],
		[HistoryInsertDateUTC],
		[TriggerAction],
		[LastModifiedUser],

		[OptionSet],
		[IncludeDBs],
		[ExcludeDBs],
		[DebugSpeed]
	)
	SELECT 
		GETDATE(),
		GETUTCDATE(),
		'Reset',
		SUSER_SNAME(),
		[OptionSet],
		[IncludeDBs],
		[ExcludeDBs],
		[DebugSpeed]
	FROM ServerEye.UserCollectionOptions
	;

	DISABLE TRIGGER ServerEye.trgDEL_ServerEyeUserCollectionOptions ON ServerEye.UserCollectionOptions;

	DELETE FROM ServerEye.UserCollectionOptions;

	ENABLE TRIGGER ServerEye.trgDEL_ServerEyeUserCollectionOptions ON ServerEye.UserCollectionOptions;


	/* TODO: figure this out later once I have viewer procs to support user collection for
	INSERT [ServerEye].[UserCollectionOptions] (
		[OptionSet],					--1
		[IncludeIdleWithTran], 
		[IncludeIdleWithoutTran], 
		[DurationFilter], 
		[IncludeDBs],					--5
		[ExcludeDBs], 
		[HighTempDBThreshold], 
		[CollectSystemSpids], 
		[HideSelf], 
		[ObtainBatchText],				--10
		[ObtainQueryPlanForStatement], 
		[ObtainQueryPlanForBatch], 
		[ObtainLocksForBlockRelevantThreshold], 
		[InputBufferThreshold], 
		[ParallelWaitsThreshold],		--15
		[QueryPlanThreshold], 
		[QueryPlanThresholdBlockRel], 
		[BlockingChainThreshold], 
		[BlockingChainDepth], 
		[TranDetailsThreshold],			--20
		[DebugSpeed], 
		[SaveBadDims], 
		[Enable8666], 
		[ResolvePageLatches], 
		[ResolveLockWaits],				--25
		[UseBackgroundThresholdIgnore]
	) 
	SELECT 
		N'SessionViewerCommonFeatures', N'Y', N'N', 0, N'',		--5
		N'', 64000, N'Y', N'Y', N'N',	--10
		N'Y', N'N', 120000, 0, 0,		--15
		0, 0, 0, 4, 0,					--20
		N'Y', N'Y', N'N', N'N', N'N',	--25
		N'Y' UNION ALL

	SELECT 
		N'SessionViewerFull', N'Y', N'Y', 0, N'', 
		N'', 64000, N'Y', N'Y', N'Y', 
		N'Y', N'Y', 0, 0, 0, 
		0, 0, 0, 10, 0, 
		N'Y', N'Y', N'N', N'Y', N'Y', 
		N'N' UNION ALL

	SELECT
		N'SessionViewerInfrequentFeatures', N'Y', N'Y', 0, N'', 
		N'', 64000, N'Y', N'Y', N'N', 
		N'Y', N'N', 120000, 0, 0, 
		0, 0, 0, 10, 0, 
		N'Y', N'Y', N'N', N'Y', N'Y', 
		N'Y' UNION ALL

	SELECT 
		N'SessionViewerMinimal', N'Y', N'N', 0, N'', 
		N'', 64000, N'Y', N'Y', N'N', 
		N'Y', N'N', 120000, 60000, 60000, 
		60000, 60000, 60000, 4, 10000, 
		N'Y', N'Y', N'N', N'N', N'N', 
		N'Y'
	;
	*/

	RETURN 0;
END
GO
