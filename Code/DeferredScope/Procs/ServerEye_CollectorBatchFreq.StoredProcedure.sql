SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[CollectorBatchFreq]
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

	FILE NAME: ServerEye.CollectorBatchFreq.StoredProcedure.sql

	PROCEDURE NAME: CollectorBatchFreq.Collector

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs on a schedule (or initiated by a user via a viewer proc) and calls various sub-procs to gather miscellaneous 
		server-level DMV data. Collects data for metrics that do not need to be captured very frequently (by default every 30 minutes)

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------

*/
(
	@init				TINYINT,
	@LocalCaptureTime	DATETIME, 
	@UTCCaptureTime		DATETIME,
	@SQLServerStartTime	DATETIME
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	

	IF EXISTS (
		SELECT * 
		FROM sys.databases d
			INNER JOIN ServerEye.DatabaseInclusion dbi
				ON d.name = dbi.DBName
		WHERE dbi.InclusionType = 'IndexStats'
	)
	BEGIN
		INSERT INTO [ServerEye].[dm_db_index_usage_stats](
			[UTCCaptureTime],
			[LocalCaptureTime],
			[database_id],
			[object_id],
			[index_id],
			[user_seeks],
			[user_scans],
			[user_lookups],
			[user_updates],
			[last_user_seek],
			[last_user_scan],
			[last_user_lookup],
			[last_user_update],
			[system_seeks],
			[system_scans],
			[system_lookups],
			[system_updates],
			[last_system_seek],
			[last_system_scan],
			[last_system_lookup],
			[last_system_update]
		)
		SELECT 
			@UTCCaptureTime,
			@LocalCaptureTime,
			u.[database_id],
			[object_id],
			[index_id],
			[user_seeks],
			[user_scans],
			[user_lookups],
			[user_updates],
			[last_user_seek],
			[last_user_scan],
			[last_user_lookup],
			[last_user_update],
			[system_seeks],
			[system_scans],
			[system_lookups],
			[system_updates],
			[last_system_seek],
			[last_system_scan],
			[last_system_lookup],
			[last_system_update]
		FROM sys.databases d
			INNER JOIN ServerEye.DatabaseInclusion dbi
				ON d.name = dbi.DBName
			INNER JOIN sys.dm_db_index_usage_stats u
				ON d.database_id = u.database_id
		WHERE dbi.InclusionType = 'IndexStats';


		INSERT INTO [ServerEye].[dm_db_index_operational_stats](
			[UTCCaptureTime],
			[LocalCaptureTime],
			[database_id],
			[object_id],
			[index_id],
			[partition_number],
			[leaf_insert_count],
			[leaf_delete_count],
			[leaf_update_count],
			[leaf_ghost_count],
			[nonleaf_insert_count],
			[nonleaf_delete_count],
			[nonleaf_update_count],
			[leaf_allocation_count],
			[nonleaf_allocation_count],
			[leaf_page_merge_count],
			[nonleaf_page_merge_count],
			[range_scan_count],
			[singleton_lookup_count],
			[forwarded_fetch_count],
			[lob_fetch_in_pages],
			[lob_fetch_in_bytes],
			[lob_orphan_create_count],
			[lob_orphan_insert_count],
			[row_overflow_fetch_in_pages],
			[row_overflow_fetch_in_bytes],
			[column_value_push_off_row_count],
			[column_value_pull_in_row_count],
			[row_lock_count],
			[row_lock_wait_count],
			[row_lock_wait_in_ms],
			[page_lock_count],
			[page_lock_wait_count],
			[page_lock_wait_in_ms],
			[index_lock_promotion_attempt_count],
			[index_lock_promotion_count],
			[page_latch_wait_count],
			[page_latch_wait_in_ms],
			[page_io_latch_wait_count],
			[page_io_latch_wait_in_ms],
			[tree_page_latch_wait_count],
			[tree_page_latch_wait_in_ms],
			[tree_page_io_latch_wait_count],
			[tree_page_io_latch_wait_in_ms],
			[page_compression_attempt_count],
			[page_compression_success_count]
		)
		SELECT 
			@UTCCaptureTime,
			@LocalCaptureTime,
			ixop.[database_id],
			[object_id],
			[index_id],
			[partition_number],
			[leaf_insert_count],
			[leaf_delete_count],
			[leaf_update_count],
			[leaf_ghost_count],
			[nonleaf_insert_count],
			[nonleaf_delete_count],
			[nonleaf_update_count],
			[leaf_allocation_count],
			[nonleaf_allocation_count],
			[leaf_page_merge_count],
			[nonleaf_page_merge_count],
			[range_scan_count],
			[singleton_lookup_count],
			[forwarded_fetch_count],
			[lob_fetch_in_pages],
			[lob_fetch_in_bytes],
			[lob_orphan_create_count],
			[lob_orphan_insert_count],
			[row_overflow_fetch_in_pages],
			[row_overflow_fetch_in_bytes],
			[column_value_push_off_row_count],
			[column_value_pull_in_row_count],
			[row_lock_count],
			[row_lock_wait_count],
			[row_lock_wait_in_ms],
			[page_lock_count],
			[page_lock_wait_count],
			[page_lock_wait_in_ms],
			[index_lock_promotion_attempt_count],
			[index_lock_promotion_count],
			[page_latch_wait_count],
			[page_latch_wait_in_ms],
			[page_io_latch_wait_count],
			[page_io_latch_wait_in_ms],
			[tree_page_latch_wait_count],
			[tree_page_latch_wait_in_ms],
			[tree_page_io_latch_wait_count],
			[tree_page_io_latch_wait_in_ms],
			[page_compression_attempt_count],
			[page_compression_success_count]
		FROM sys.databases d
				INNER JOIN ServerEye.DatabaseInclusion dbi
					ON d.name = dbi.DBName
				CROSS APPLY sys.dm_db_index_operational_stats(d.database_id, NULL, NULL, NULL) ixop
		WHERE dbi.InclusionType = 'IndexStats';
	END

	INSERT INTO [ServerEye].[MissingIndexes](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[group_handle],
		[index_handle],
		[database_id],
		[object_id],
		[equality_columns],
		[inequality_columns],
		[included_columns],
		[unique_compiles],
		[user_seeks],
		[user_scans],
		[last_user_seek],
		[last_user_scan],
		[avg_total_user_cost],
		[avg_user_impact],
		[system_seeks],
		[system_scans],
		[last_system_seek],
		[last_system_scan],
		[avg_total_system_cost],
		[avg_system_impact]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[group_handle],
		g.[index_handle],
		[database_id],
		[object_id],
		[equality_columns],
		[inequality_columns],
		[included_columns],
		[unique_compiles],
		[user_seeks],
		[user_scans],
		[last_user_seek],
		[last_user_scan],
		[avg_total_user_cost],
		[avg_user_impact],
		[system_seeks],
		[system_scans],
		[last_system_seek],
		[last_system_scan],
		[avg_total_system_cost],
		[avg_system_impact]
	FROM sys.dm_db_missing_index_groups g
		INNER JOIN sys.dm_db_missing_index_group_stats gs
			ON g.index_group_handle = gs.group_handle
		INNER JOIN sys.dm_db_missing_index_details i
			ON i.index_handle = g.index_handle;



	--Probably need a way to turn this off for larger systems.
	INSERT INTO [ServerEye].[BufDescriptors] (
		[UTCCaptureTime],
		[database_id],
		[file_id],
		[allocation_unit_id],
		[page_type],
		[numa_node],
		[NumModified],
		[SumRowCount],
		[SumFreeSpaceInBytes],
		[NumRows]
	)
	SELECT 
		@UTCCaptureTime,
		database_id,
		file_id,
		allocation_unit_id,
		page_type,
		numa_node,
		NumModified = SUM(CASE WHEN is_modified = 1 THEN CONVERT(INT,1) ELSE CONVERT(INT,0) END),
		SumRowCount = SUM(CONVERT(BIGINT,row_count)),
		SumFreeSpaceInBytes = SUM(CONVERT(BIGINT,free_space_in_bytes)),
		NumRows = COUNT(*)
	FROM (
		SELECT 
			database_id = ISNULL(buf.database_id,-1),
			file_id = ISNULL(buf.file_id,-1),
			allocation_unit_id = CASE WHEN buf.database_id = 2 THEN -5 ELSE ISNULL(buf.allocation_unit_id,-1) END,
			page_type = ISNULL(buf.page_type,''),
			numa_node = ISNULL(buf.numa_node,-1),
			buf.is_modified,
			buf.row_count,
			buf.free_space_in_bytes
		FROM sys.dm_os_buffer_descriptors buf
		WHERE buf.database_id NOT IN (1, 3, 4)
		AND buf.page_type NOT IN ('BOOT_PAGE','FILEHEADER_PAGE','SYSCONFIG_PAGE')
	) ss
	GROUP BY database_id,
		file_id,
		allocation_unit_id,
		page_type,
		numa_node
	HAVING COUNT(*) > 10*128;		--Num MB * 128 (pages) to filter down to just alloc units that are larger memory hogs. This should be a config option



	RETURN 0;
END
GO