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

	FILE NAME: ServerEye_dm_db_index_operational_stats.Table.sql

	TABLE NAME: ServerEye_dm_db_index_operational_stats

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Snapshots sys.dm_db_index_operational_stats (in Batch-frequency metrics)
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_dm_db_index_operational_stats(
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[database_id] [smallint] NOT NULL,
	[object_id] [int] NOT NULL,
	[index_id] [int] NOT NULL,
	[partition_number] [int] NOT NULL,
	[leaf_insert_count] [bigint] NOT NULL,
	[leaf_delete_count] [bigint] NOT NULL,
	[leaf_update_count] [bigint] NOT NULL,
	[leaf_ghost_count] [bigint] NOT NULL,
	[nonleaf_insert_count] [bigint] NOT NULL,
	[nonleaf_delete_count] [bigint] NOT NULL,
	[nonleaf_update_count] [bigint] NOT NULL,
	[leaf_allocation_count] [bigint] NOT NULL,
	[nonleaf_allocation_count] [bigint] NOT NULL,
	[leaf_page_merge_count] [bigint] NOT NULL,
	[nonleaf_page_merge_count] [bigint] NOT NULL,
	[range_scan_count] [bigint] NOT NULL,
	[singleton_lookup_count] [bigint] NOT NULL,
	[forwarded_fetch_count] [bigint] NOT NULL,
	[lob_fetch_in_pages] [bigint] NOT NULL,
	[lob_fetch_in_bytes] [bigint] NOT NULL,
	[lob_orphan_create_count] [bigint] NOT NULL,
	[lob_orphan_insert_count] [bigint] NOT NULL,
	[row_overflow_fetch_in_pages] [bigint] NOT NULL,
	[row_overflow_fetch_in_bytes] [bigint] NOT NULL,
	[column_value_push_off_row_count] [bigint] NOT NULL,
	[column_value_pull_in_row_count] [bigint] NOT NULL,
	[row_lock_count] [bigint] NOT NULL,
	[row_lock_wait_count] [bigint] NOT NULL,
	[row_lock_wait_in_ms] [bigint] NOT NULL,
	[page_lock_count] [bigint] NOT NULL,
	[page_lock_wait_count] [bigint] NOT NULL,
	[page_lock_wait_in_ms] [bigint] NOT NULL,
	[index_lock_promotion_attempt_count] [bigint] NOT NULL,
	[index_lock_promotion_count] [bigint] NOT NULL,
	[page_latch_wait_count] [bigint] NOT NULL,
	[page_latch_wait_in_ms] [bigint] NOT NULL,
	[page_io_latch_wait_count] [bigint] NOT NULL,
	[page_io_latch_wait_in_ms] [bigint] NOT NULL,
	[tree_page_latch_wait_count] [bigint] NOT NULL,
	[tree_page_latch_wait_in_ms] [bigint] NOT NULL,
	[tree_page_io_latch_wait_count] [bigint] NOT NULL,
	[tree_page_io_latch_wait_in_ms] [bigint] NOT NULL,
	[page_compression_attempt_count] [bigint] NOT NULL,
	[page_compression_success_count] [bigint] NOT NULL,
 CONSTRAINT [PKdm_db_index_operational_stats] PRIMARY KEY CLUSTERED 
(
	[UTCCaptureTime] ASC,
	[database_id] ASC,
	[object_id] ASC,
	[index_id] ASC,
	[partition_number] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO