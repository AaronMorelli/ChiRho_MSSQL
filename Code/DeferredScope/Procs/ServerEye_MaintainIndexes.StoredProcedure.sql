SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[MaintainIndexes] 
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

	FILE NAME: ServerEye.MaintainIndexes.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.MaintainIndexes

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Evaluates ServerEye indexes for whether they should be rebuilt or not. 

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.MaintainIndexes
*/
AS
BEGIN
	-- EXEC [ServerEye].[MaintainIndexes] 
	SET NOCOUNT ON;
	SET DEADLOCK_PRIORITY LOW;

	DECLARE @lv__ErrorMessage NVARCHAR(4000),
			@lv__ErrorState INT,
			@lv__ErrorSeverity INT,
			@lv__ErrorLoc NVARCHAR(100),
			@lv__RowCount BIGINT;

	--Cursor variables
	DECLARE @SchemaName sysname,
		@TableName sysname,
		@IndexName sysname,
		@index_id int,
		@alloc_unit_type_desc nvarchar(60),
		@avg_fragment_size_in_pages float,
		@avg_fragmentation_in_percent float,
		@avg_page_space_used_in_percent float,
		@forwarded_record_count bigint,
		@ghost_record_count bigint,
		@page_count bigint,
		@record_count bigint,
		@version_ghost_record_count bigint,
		@min_record_size_in_bytes int,
		@max_record_size_in_bytes int,
		@avg_record_size_in_bytes int;

	--Variables used when calculating the rebuild score per index.
	DECLARE @CurrentRebuildScore INT,
			@NumBadRows BIGINT,
			@RatioBadRows FLOAT;

	--Variables relevant to the rebuild section
	DECLARE @DynSQL						VARCHAR(8000),
		@OriginalRebuildStartTimeUTC	DATETIME,
		@RebuildStartTimeUTC			DATETIME,
		@RebuildEndTimeUTC				DATETIME, 
		@FinalRebuildEndTimeUTC			DATETIME,
		@LastSleepTimeUTC				DATETIME,
		@LogMessage						NVARCHAR(4000),
		@ErrorNumber					INT;

BEGIN TRY
	SET @lv__ErrorLoc = N'Create TT';
	CREATE TABLE #ServerEyeIndexToEval (
		[SchemaName] [sysname] NOT NULL,
		[TableName] [sysname] NOT NULL,
		[IndexName] [sysname] NULL,
		[index_id] [int] NOT NULL,
		[alloc_unit_type_desc] [nvarchar](60) NULL,
		[avg_fragment_size_in_pages] [float] NULL,
		[avg_fragmentation_in_percent] [float] NULL,
		[avg_page_space_used_in_percent] [float] NULL,
		[forwarded_record_count] [bigint] NULL,
		[ghost_record_count] [bigint] NULL,
		[page_count] [bigint] NULL,
		[record_count] [bigint] NULL,
		[version_ghost_record_count] [bigint] NULL,
		[min_record_size_in_bytes] [int] NULL,
		[max_record_size_in_bytes] [int] NULL,
		[avg_record_size_in_bytes] [int] NULL
	);

	CREATE TABLE #ServerEyeIndexRebuildScore (
		[SchemaName] [sysname] NOT NULL,
		[TableName] [sysname] NOT NULL,
		[IndexName] [sysname] NULL,
		[RebuildScore] [int] NOT NULL
	);

		/* This works in SQL 2012 and later, but not in 2008 R2 or prev
	INSERT INTO #ServerEyeIndexToEval (
		[SchemaName],
		[TableName],
		[IndexName],
		[index_id],
		[alloc_unit_type_desc],
		[avg_fragment_size_in_pages],
		[avg_fragmentation_in_percent],
		[avg_page_space_used_in_percent],
		[forwarded_record_count],
		[ghost_record_count],
		[page_count],
		[record_count],
		[version_ghost_record_count],
		[min_record_size_in_bytes],
		[max_record_size_in_bytes],
		[avg_record_size_in_bytes]
	)
	SELECT s.name as SchemaName, 
		o.name as TableName, 
		i.name as IndexName, 
		i.index_id, 
		ps.alloc_unit_type_desc, 
		ps.avg_fragment_size_in_pages,
		ps.avg_fragmentation_in_percent,
		ps.avg_page_space_used_in_percent,
		ps.forwarded_record_count,
		ps.ghost_record_count, 
		ps.page_count,
		ps.record_count,
		ps.version_ghost_record_count,
		ps.min_record_size_in_bytes, 
		ps.max_record_size_in_bytes, 
		ps.avg_record_size_in_bytes
	FROM sys.objects o 
		INNER JOIN sys.schemas s
			ON o.schema_id = s.schema_id
		INNER JOIN sys.indexes i
			ON o.object_id = i.object_id
		CROSS APPLY sys.dm_db_index_physical_stats(db_id(), 
			o.object_id, i.index_id, null, 'DETAILED') ps
	WHERE o.type = 'U'
	AND o.schema_id IN (schema_id('ServerEye'))
	AND ps.index_level = 0
	AND i.index_id <> 0
	;
	*/
	
	--BEGIN SQL 2008 R2 and before logic BEGIN
	SET @lv__ErrorLoc = N'Obtain objects';
	INSERT INTO #ServerEyeIndexToEval (
		[SchemaName],
		[TableName],
		[IndexName],
		[index_id]
	)
	SELECT s.name as SchemaName, 
		o.name as TableName, 
		i.name as IndexName, 
		i.index_id
	FROM sys.objects o 
		INNER JOIN sys.schemas s
			ON o.schema_id = s.schema_id
		INNER JOIN sys.indexes i
			ON o.object_id = i.object_id
	WHERE o.type = 'U'
	AND o.schema_id IN (schema_id('ServerEye'))
	AND i.index_id <> 0;
	
	SET @lv__ErrorLoc = N'Iterate indexes';
	DECLARE @ObjID INT;
	DECLARE ObtainPhysStats CURSOR FOR
	SELECT t.SchemaName,
		t.TableName,
		t.IndexName,
		t.index_id
	FROM #ServerEyeIndexToEval t
	ORDER BY 1,2,3;
	
	OPEN ObtainPhysStats;
	FETCH ObtainPhysStats INTO @SchemaName,
		@TableName,
		@IndexName,
		@index_id;
	
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @ObjID = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName));
	
		UPDATE targ 
		SET alloc_unit_type_desc = ss.alloc_unit_type_desc,
			avg_fragment_size_in_pages = ss.avg_fragment_size_in_pages,
			avg_fragmentation_in_percent = ss.avg_fragmentation_in_percent,
			avg_page_space_used_in_percent = ss.avg_page_space_used_in_percent,
			forwarded_record_count = ss.forwarded_record_count,
			ghost_record_count = ss.ghost_record_count,
			page_count = ss.page_count,
			record_count = ss.record_count,
			version_ghost_record_count = ss.version_ghost_record_count,
			min_record_size_in_bytes = ss.min_record_size_in_bytes,
			max_record_size_in_bytes = ss.max_record_size_in_bytes,
			avg_record_size_in_bytes = ss.avg_record_size_in_bytes
		FROM #ServerEyeIndexToEval targ 
			INNER JOIN (
				SELECT *
				FROM sys.dm_db_index_physical_stats(db_id(), @ObjID, @index_id, null, 'DETAILED') ps
				WHERE ps.index_level = 0
			) ss
				ON targ.SchemaName = @SchemaName
				AND targ.TableName = @TableName
				AND targ.IndexName = @IndexName
				AND targ.index_id = @index_id
		;
	
		FETCH ObtainPhysStats INTO @SchemaName,
			@TableName,
			@IndexName,
			@index_id;
	END
	
	CLOSE ObtainPhysStats;
	DEALLOCATE ObtainPhysStats;
	--END SQL 2008 R2 and before logic END

	/* debug
	SELECT * 
	FROM #ServerEyeIndexToEval
	WHERE TableName = 'InputBufferStore'
	ORDER BY SchemaName, TableName, IndexName, alloc_unit_type_desc;
	*/
	SET @lv__ErrorLoc = N'INSERT #ServerEyeIndexRebuildScore';
	INSERT INTO #ServerEyeIndexRebuildScore (
		[SchemaName],
		[TableName],
		[IndexName],
		[RebuildScore]
	)
	SELECT DISTINCT SchemaName, TableName, IndexName, 0
	FROM #ServerEyeIndexToEval;

	SET @lv__ErrorLoc = N'cursor iterateServerEyeIndexes';
	DECLARE iterateServerEyeIndexes CURSOR LOCAL FAST_FORWARD FOR
	SELECT 
		t.SchemaName,
		t.TableName,
		t.IndexName,
		t.alloc_unit_type_desc, 
		t.page_count,
		t.avg_fragmentation_in_percent, 
		t.avg_page_space_used_in_percent, 
		t.avg_fragment_size_in_pages, 
		t.record_count,
		t.forwarded_record_count,
		t.ghost_record_count, 
		t.version_ghost_record_count,
		t.min_record_size_in_bytes,
		t.max_record_size_in_bytes,
		t.avg_record_size_in_bytes
	FROM #ServerEyeIndexToEval t
	WHERE t.page_count > 0
	ORDER BY t.SchemaName, t.TableName, t.index_id, t.alloc_unit_type_desc;

	OPEN iterateServerEyeIndexes;
	FETCH iterateServerEyeIndexes INTO @SchemaName,
		@TableName,
		@IndexName,
		@alloc_unit_type_desc, 
		@page_count,
		@avg_fragmentation_in_percent, 
		@avg_page_space_used_in_percent, 
		@avg_fragment_size_in_pages, 
		@record_count,
		@forwarded_record_count,
		@ghost_record_count, 
		@version_ghost_record_count,
		@min_record_size_in_bytes,
		@max_record_size_in_bytes,
		@avg_record_size_in_bytes;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @CurrentRebuildScore = 0;
		SET @NumBadRows = ISNULL(@forwarded_record_count,0) + 
						ISNULL(@ghost_record_count,0) + 
						ISNULL(@version_ghost_record_count,0);

		IF @record_count <= 0
		BEGIN
			SET @RatioBadRows = @NumBadRows;
		END
		ELSE
		BEGIN
			SET @RatioBadRows = ( @NumBadRows * 1.0 ) / ( @record_count * 1.0 ); 
		END

		IF @page_count = 1
		BEGIN
			--the only reason to rebuild w/1 page is if we have "undesirable" rows on the page or there are 0 rows total. (Does rebuild ever deallocate down to 0 pages?)
			IF @NumBadRows > 0
				OR @record_count = 0
			BEGIN
				SET @CurrentRebuildScore = 5;
			END
			ELSE
			BEGIN
				SET @CurrentRebuildScore = -99
			END
		END
		ELSE IF @page_count <= 4
		BEGIN
			--If index size is 4 pages or less, essentially disqualify from a rebuild UNLESS 
			--the page used space is < 50%
			--OR the ghost+forwarded+version_ghost is > 10% of the rows AND the page used space is < 75%
			IF @avg_page_space_used_in_percent < 50.0
				OR (@avg_page_space_used_in_percent < 75.0 
					AND @RatioBadRows >= 0.1)
			BEGIN 
				--small table is cheap and current status is pretty inefficient. Rebuild it
				SET @CurrentRebuildScore = @CurrentRebuildScore + 5;
			END
			ELSE
			BEGIN
				--essentially disable a rebuild
				SET @CurrentRebuildScore = -99;
			END
		END		--IF @page_count <= 4
		ELSE
		BEGIN
			--@page_count > 4

			--Avoid buffer pool wasted space... rebuild when pages are not very full.
			IF @avg_page_space_used_in_percent < 60.0
			BEGIN
				SET @CurrentRebuildScore += 5;
			END
			ELSE IF @avg_page_space_used_in_percent < 70.0
			BEGIN
				SET @CurrentRebuildScore += 3;
			END
			ELSE IF @avg_page_space_used_in_percent < 80.0
			BEGIN
				SET @CurrentRebuildScore += 1;
			END
			
			IF @RatioBadRows >= 0.25
			BEGIN
				SET @CurrentRebuildScore += 3;
			END
			ELSE IF @RatioBadRows >= 0.15
			BEGIN
				SET @CurrentRebuildScore += 2;
			END
			ELSE IF @RatioBadRows >= 0.10
			BEGIN
				SET @CurrentRebuildScore += 1;
			END

			IF @page_count >= 128	--1 MB
			BEGIN
				--large enough to care (at least a little) about how contiguous the pages are
				IF @avg_fragment_size_in_pages < 2.0
				BEGIN
					SET @CurrentRebuildScore += 3;
				END
				ELSE IF @avg_fragment_size_in_pages  < 4.0
				BEGIN
					SET @CurrentRebuildScore += 2;
				END
				ELSE IF @avg_fragment_size_in_pages  < 6.0
				BEGIN
					SET @CurrentRebuildScore += 1;
				END
			END

			IF @page_count >= 128000	--1 GB
			BEGIN
				--index is large enough that we might actually care about the commonly-used metric
				IF @avg_fragmentation_in_percent > 75.0
				BEGIN
					SET @CurrentRebuildScore += 3;
				END
				ELSE IF @avg_fragmentation_in_percent > 50.0
				BEGIN
					SET @CurrentRebuildScore += 2;
				END
				ELSE IF @avg_fragmentation_in_percent > 40.0
				BEGIN
					SET @CurrentRebuildScore += 2;
				END
			END
		END

		SET @lv__ErrorLoc = N'Update #ServerEyeIndexRebuildScore';
		UPDATE #ServerEyeIndexRebuildScore
		SET RebuildScore = RebuildScore + @CurrentRebuildScore		--multiple alloc units per index means we need to
																	-- take multiple loop iterations per index into account.
		WHERE SchemaName = @SchemaName
		AND TableName = @TableName
		AND IndexName = @IndexName;

		FETCH iterateServerEyeIndexes INTO @SchemaName,
			@TableName,
			@IndexName,
			@alloc_unit_type_desc, 
			@page_count,
			@avg_fragmentation_in_percent, 
			@avg_page_space_used_in_percent, 
			@avg_fragment_size_in_pages, 
			@record_count,
			@forwarded_record_count,
			@ghost_record_count, 
			@version_ghost_record_count,
			@min_record_size_in_bytes,
			@max_record_size_in_bytes,
			@avg_record_size_in_bytes;
	END

	CLOSE iterateServerEyeIndexes;
	DEALLOCATE iterateServerEyeIndexes;

	/*
	--for debugging
	SELECT *
	FROM #ServerEyeIndexRebuildScore
	WHERE TableName = 'InputBufferStore'
	order by SchemaName, TableName, IndexName;
	*/


	SET @lv__ErrorLoc = N'cursor iterateScores';
	DECLARE iterateScores CURSOR LOCAL FAST_FORWARD FOR
	SELECT SchemaName, TableName, IndexName
	FROM #ServerEyeIndexRebuildScore t
	WHERE t.RebuildScore >= 5;

	OPEN iterateScores
	FETCH iterateScores INTO @SchemaName, @TableName, @IndexName;

	SET @OriginalRebuildStartTimeUTC = GETUTCDATE();
	SET @LastSleepTimeUTC = GETUTCDATE();

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @DynSQL = 'ALTER INDEX ' + QUOTENAME(@IndexName) 
			+ ' ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' REBUILD;'

		--PRINT @DynSQL

		SET @RebuildStartTimeUTC = GETUTCDATE();
		BEGIN TRY
			SET @lv__ErrorLoc = N'Execute DynSQL';
			EXEC (@DynSQL);

			SET @LogMessage = N'Successfully rebuilt index ' + QUOTENAME(@IndexName) + ' on table ' + 
				QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);

			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='After dynamic index rebuild', @Message=@LogMessage;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @ErrorNumber = ERROR_NUMBER();
			SET @LogMessage = 'Error ' + CONVERT(VARCHAR(20), ERROR_NUMBER()) + ' occurred while attempting to rebuild
				index ' + QUOTENAME(@IndexName) + ' on table ' + 
				QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '. State: ' + CONVERT(varchar(20),ERROR_STATE()) +
				'; Severity: ' + CONVERT(varchar(20),ERROR_SEVERITY()) + ' Message: ' + ERROR_MESSAGE();

			EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='CATCH dynamic index rebuild', @Message=@LogMessage;
		END CATCH

		SET @RebuildEndTimeUTC = GETUTCDATE(); 


		IF DATEDIFF(second, @RebuildStartTimeUTC, @RebuildEndTimeUTC) >= 5 
			OR DATEDIFF(second, @LastSleepTimeUTC, @RebuildEndTimeUTC) >= 15
		BEGIN
			--If the last index rebuild actually took some time, then we may be inhibiting ServerEye. 
			--Waiting 3 seconds before we go to the next index gives ServerEye time (if it was blocked) to finish its run and go back to sleep
			WAITFOR DELAY '00:00:03';
			SET @LastSleepTimeUTC = GETUTCDATE();
		END

		FETCH iterateScores INTO @SchemaName, @TableName, @IndexName;
	END

	SET @FinalRebuildEndTimeUTC = GETUTCDATE();

	CLOSE iterateScores;
	DEALLOCATE iterateScores;

	RETURN 0;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @lv__ErrorState = ERROR_STATE();
	SET @lv__ErrorSeverity = ERROR_SEVERITY();

	SET @lv__ErrorMessage = N'Exception occurred at location ("' + ISNULL(@lv__ErrorLoc,N'<null>') + '"). Error #: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()), N'<null>') +
		N'; Severity: ' + ISNULL(CONVERT(NVARCHAR(20),@lv__ErrorSeverity), N'<null>') + 
		N'; State: ' + ISNULL(CONVERT(NVARCHAR(20),@lv__ErrorState),N'<null>') + 
		N'; Message: ' + ISNULL(ERROR_MESSAGE(),N'<null>');

	EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@lv__ErrorMessage;

	RAISERROR(@lv__ErrorMessage, @lv__ErrorSeverity, @lv__ErrorState);
	RETURN -999;
END CATCH

	RETURN 0;
END
GO
