SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[PrePopulateDimensions]
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

	FILE NAME: ServerEye.PrePopulateDimensions.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.PrePopulateDimensions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Adds new rows (if any are found) to various dimension tables so that those values are present when
		the various ServerEye collection queries run.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.PrePopulateDimensions

*/
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE
		@lv__nullstring						NVARCHAR(8),
		@lv__nullint						INT,
		@lv__nullsmallint					SMALLINT;

	SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" 
											-- would collide with a DMV value
	SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
	SET @lv__nullsmallint = -929;			-- overlapping with some special system value

	IF OBJECT_ID('tempdb..#DistinctWaitTypes1') IS NOT NULL
	BEGIN
		DROP TABLE #DistinctWaitTypes1;
	END
	SELECT w.wait_type
	INTO #DistinctWaitTypes1
	FROM sys.dm_os_wait_stats w;

	INSERT INTO ServerEye.DimWaitType (
		wait_type, 
		isBenign
	)
	SELECT DISTINCT 
		w.wait_type, 
		[isBenign] = 0	--TODO: set this logic appropriately
	FROM #DistinctWaitTypes1 w
	WHERE NOT EXISTS (
		SELECT * FROM ServerEye.DimWaitType dwt
		WHERE dwt.wait_type = w.wait_type
	);

	INSERT INTO ServerEye.DimLatchClass (
		latch_class,
		[IsBenign]
	)
	SELECT DISTINCT 
		ls.latch_class, 
		0
	FROM sys.dm_os_latch_stats ls
	WHERE NOT EXISTS (
		SELECT * FROM ServerEye.DimLatchClass l
		WHERE l.latch_class = ls.latch_class
	);

	INSERT INTO [ServerEye].[DimSpinlock] (
		[SpinlockName],
		[IsBenign]
	)
	SELECT DISTINCT
		s.name,
		0
	FROM sys.dm_os_spinlock_stats s
	WHERE NOT EXISTS (
		SELECT * FROM ServerEye.DimSpinlock dsl
		WHERE dsl.SpinlockName = s.name
	);

	INSERT INTO [ServerEye].[DimDBVolume](
		[volume_id],
		[volume_mount_point],
		[logical_volume_name],
		[file_system_type],
		[supports_compression],
		[supports_alternate_streams],
		[supports_sparse_files],
		[is_read_only],
		[is_compressed]
	)
	SELECT 
		ss.volume_id,
		ss.volume_mount_point,
		ss.logical_volume_name,
		ss.file_system_type,
		ss.supports_compression,
		ss.supports_alternate_streams,
		ss.supports_sparse_files,
		ss.is_read_only,
		ss.is_compressed
	FROM (
		SELECT DISTINCT
			[volume_id] = ISNULL(vs.volume_id,N'<null>'),
			[volume_mount_point] = ISNULL(vs.volume_mount_point,N'<null>'),
			[logical_volume_name] = ISNULL(vs.logical_volume_name,N'<null>'),
			[file_system_type] = ISNULL(vs.file_system_type,N'<null>'),
			[supports_compression] = ISNULL(vs.supports_compression,255),
			[supports_alternate_streams] = ISNULL(vs.supports_alternate_streams,255),
			[supports_sparse_files] = ISNULL(vs.supports_sparse_files,255),
			[is_read_only] = ISNULL(vs.is_read_only,255),
			[is_compressed] = ISNULL(vs.is_compressed,255)
		FROM sys.master_files mf
			CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
	) ss
	WHERE NOT EXISTS (
		SELECT * 
		FROM ServerEye.DimDBVolume dbv
		WHERE ss.volume_id = dbv.volume_id
		AND ss.volume_mount_point = dbv.volume_mount_point
		AND ss.logical_volume_name = dbv.logical_volume_name
		AND ss.file_system_type = dbv.file_system_type
		AND ss.supports_compression = dbv.supports_compression
		AND ss.supports_alternate_streams = dbv.supports_alternate_streams
		AND ss.supports_sparse_files = dbv.supports_sparse_files
		AND ss.is_read_only = dbv.is_read_only
		AND ss.is_compressed = dbv.is_compressed
	);

	/* Populate ServerEye.DimMemoryTracker from these DMVs

		sys.dm_os_memory_clerks
		sys.dm_os_memory_cache_clock_hands
		sys.dm_os_memory_cache_counters
		sys.dm_os_memory_cache_hash_tables
		sys.dm_os_memory_pools
		sys.dm_os_hosts

	*/
	IF OBJECT_ID('tempdb..#MemoryTrackers') IS NOT NULL DROP TABLE #MemoryTrackers;
	CREATE TABLE #MemoryTrackers (
		MemoryTrackerType NVARCHAR(128) NOT NULL,
		MemoryTrackerName NVARCHAR(128) NOT NULL,
		IsInClerks INT NOT NULL,
		IsInClockHands INT NOT NULL,
		IsInCacheCounters INT NOT NULL,
		IsInCacheHashTables INT NOT NULL,
		IsInPools INT NOT NULL,
		IsInHosts INT NOT NULL
	);
	
	INSERT INTO #MemoryTrackers (
		MemoryTrackerType,
		MemoryTrackerName,
		IsInClerks,
		IsInClockHands,
		IsInCacheCounters,
		IsInCacheHashTables,
		IsInPools,
		IsInHosts
	)
	SELECT 
		cl.type,
		cl.name,
		[IsInClerks] = 1,
		[IsInClockHands] = 0,
		[IsInCacheCounters] = 0,
		[IsInCacheHashTables] = 0,
		[IsInPools] = 0,
		[IsInHosts] = 0
	FROM (
		SELECT DISTINCT
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END
		FROM sys.dm_os_memory_clerks t
	) cl

	UNION ALL 

	SELECT 
		ch.type, 
		ch.name,
		[IsInClerks] = 0,
		[IsInClockHands] = 1,
		[IsInCacheCounters] = 0,
		[IsInCacheHashTables] = 0,
		[IsInPools] = 0,
		[IsInHosts] = 0
	FROM (
		SELECT DISTINCT
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END
		FROM sys.dm_os_memory_cache_clock_hands t
	) ch

	UNION ALL

	SELECT 
		cc.type, 
		cc.name,
		[IsInClerks] = 0,
		[IsInClockHands] = 0,
		[IsInCacheCounters] = 1,
		[IsInCacheHashTables] = 0,
		[IsInPools] = 0,
		[IsInHosts] = 0
	FROM (
		SELECT DISTINCT
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END
		FROM sys.dm_os_memory_cache_counters t
	) cc

	UNION ALL

	SELECT 
		ht.type, 
		ht.name,
		[IsInClerks] = 0,
		[IsInClockHands] = 0,
		[IsInCacheCounters] = 0,
		[IsInCacheHashTables] = 1,
		[IsInPools] = 0,
		[IsInHosts] = 0
	FROM (
		SELECT DISTINCT
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END
		FROM sys.dm_os_memory_cache_hash_tables t
	) ht

	UNION ALL

	SELECT 
		mp.type, 
		mp.name,
		[IsInClerks] = 0,
		[IsInClockHands] = 0,
		[IsInCacheCounters] = 0,
		[IsInCacheHashTables] = 0,
		[IsInPools] = 1,
		[IsInHosts] = 0
	FROM (
		SELECT DISTINCT
			t.type, 
			t.name
		FROM sys.dm_os_memory_pools t
	) mp

	UNION ALL 

	SELECT 
		h.type, 
		h.name,
		[IsInClerks] = 0,
		[IsInClockHands] = 0,
		[IsInCacheCounters] = 0,
		[IsInCacheHashTables] = 0,
		[IsInPools] = 0,
		[IsInHosts] = 1
	FROM (
		SELECT DISTINCT
			h.type,
			h.name
		FROM sys.dm_os_hosts h
	) h;

		
	MERGE [ServerEye].[DimMemoryTracker] AS tgt
	USING (
		SELECT 
			t.MemoryTrackerType,
			t.MemoryTrackerName,
			[IsInClerks] = MAX(t.IsInClerks),
			[IsInClockHands] = MAX(t.IsInClockHands),
			[IsInCacheCounters] = MAX(t.IsInCacheCounters),
			[IsInCacheHashTables] = MAX(t.IsInCacheHashTables),
			[IsInPools] = MAX(t.IsInPools),
			[IsInHosts] = MAX(t.IsInHosts)
		FROM #MemoryTrackers t
		GROUP BY t.MemoryTrackerType,
			t.MemoryTrackerName
	) src
		ON src.MemoryTrackerType = tgt.type
		AND src.MemoryTrackerName = tgt.name
	WHEN NOT MATCHED BY TARGET THEN INSERT (
		[type],
		[name],

		[IsInClerks],
		[IsInClockHands],
		[IsInCacheCounters],
		[IsInCacheHashTables],
		[IsInPools],
		[IsInHosts]
		)
	VALUES (
		src.MemoryTrackerType,
		src.MemoryTrackerName,
		src.IsInClerks,
		src.IsInClockHands,
		src.IsInCacheCounters,
		src.IsInCacheHashTables,
		src.IsInPools,
		src.IsInHosts
	)
	WHEN MATCHED 
	AND (
		tgt.IsInClerks <> src.IsInClerks
		OR tgt.IsInClockHands <> src.IsInClockHands
		OR tgt.IsInCacheCounters <> src.IsInCacheCounters
		OR tgt.IsInCacheHashTables <> src.IsInCacheHashTables
		OR tgt.IsInPools <> src.IsInPools
		OR tgt.IsInHosts <> src.IsInHosts
	)
	THEN UPDATE 
	SET tgt.IsInClerks = src.IsInClerks,
		tgt.IsInClockHands = src.IsInClockHands,
		tgt.IsInCacheCounters = src.IsInCacheCounters,
		tgt.IsInCacheHashTables = src.IsInCacheHashTables,
		tgt.IsInPools = src.IsInPools,
		tgt.IsInHosts = src.IsInHosts;


	INSERT INTO [ServerEye].[DimPerformanceCounter](
		[object_name],
		[counter_name],
		[instance_name],
		[cntr_type],
		[CounterFrequency]
	)
	SELECT 
		LTRIM(RTRIM(pc.object_name)),
		LTRIM(RTRIM(pc.counter_name)),
		LTRIM(RTRIM(ISNULL(pc.instance_name,N''))),
		pc.cntr_type,
		[CounterFrequency] = 0
	FROM sys.dm_os_performance_counters pc
	WHERE NOT EXISTS (
		SELECT * 
		FROM ServerEye.DimPerformanceCounter dpc
		WHERE dpc.object_name = pc.object_name
		AND dpc.counter_name = pc.counter_name
		AND dpc.instance_name = ISNULL(pc.instance_name,N'')
	);

	--Set to Hi-freq
	UPDATE targ 
	SET CounterFrequency = 1
	FROM ServerEye.DimPerformanceCounter targ
	WHERE targ.CounterFrequency = 0
	AND (
		object_name = N'SQLServer:Batch Resp Statistics'

		OR (
			object_name = N'SQLServer:Buffer Manager'
			AND counter_name IN (
				N'Background writer pages/sec',
				N'Checkpoint pages/sec',
				N'Free list stalls/sec',
				N'Lazy writes/sec',
				N'Page lookups/sec',
				N'Page reads/sec',
				N'Page writes/sec',
				N'Readahead pages/sec',
				N'Readahead time/sec'
				)
		)
		OR (
			object_name = N'SQLServer:Buffer Node'
			AND counter_name IN (
				N'Local node page lookups/sec',
				N'Remote node page lookups/sec'
			)
		)
		OR (
			object_name = N'SQLServer:Databases'
			AND counter_name IN (
				N'Active Transactions',
				N'Backup/Restore Throughput/sec',
				N'Bulk Copy Rows/sec',
				N'Bulk Copy Throughput/sec',
				N'DBCC Logical Scan Bytes/sec',
				N'Log Bytes Flushed/sec',
				N'Log Flush Wait Time',
				N'Log Flush Waits/sec',
				N'Log Flush Write Time (ms)',
				N'Log Flushes/sec',
				N'Tracked transactions/sec',
				N'Transactions/sec',
				N'Write Transactions/sec'
			)
		)
		OR (
			object_name = N'SQLServer:General Statistics'
			AND counter_name IN (
				N'Connection Reset/sec',
				N'Logins/sec',
				N'Logouts/sec',
				N'Processes blocked',
				N'Transactions'
			)
		)
		OR (
			object_name = N'SQLServer:Latches'
			AND counter_name IN (
				N'Average Latch Wait Time (ms)',
				N'Average Latch Wait Time Base',
				N'Latch Waits/sec',
				N'Total Latch Wait Time (ms)'
			)
		)
		OR (
			object_name = N'SQLServer:Locks'
			AND counter_name IN (N'Lock Requests/sec', N'Lock Timeouts (timeout > 0)/sec', N'Lock Timeouts/sec', N'Number of Deadlocks/sec' )
			AND instance_name = N'_Total'
		)
		OR (
			object_name = N'SQLServer:Memory Broker Clerks'
			AND counter_name IN (N'Periodic evictions (pages)', N'Pressure evictions (pages/sec)')
		)
		OR (
			object_name = N'SQLServer:Resource Pool Stats'
			AND counter_name IN (
				N'Avg Disk Read IO (ms)',
				N'Avg Disk Read IO (ms) Base',
				N'CPU control effect %',
				N'CPU usage %',
				N'CPU usage target %',
				N'Disk Read Bytes/sec',
				N'Disk Read IO Throttled/sec',
				N'Disk Read IO/sec',
				N'Disk Write Bytes/sec',
				N'Disk Write IO Throttled/sec',
				N'Disk Write IO/sec',
				N'Memory grant timeouts/sec',
				N'Memory grants/sec'
			)
		)
		OR (
			object_name = N'SQLServer:SQL Errors'
		)
		OR (
			object_name = N'SQLServer:SQL Statistics'
		)
		OR (
			object_name = N'SQLServer:Transactions'
			AND counter_name IN (
				N'NonSnapshot Version Transactions',
				N'Snapshot Transactions',
				N'Transactions',
				N'Update Snapshot Transactions',
				N'Version Cleanup rate (KB/s)',
				N'Version Generation rate (KB/s)'
			)
		)
		OR (
			object_name = N'SQLServer:Workload Group Stats'
			AND counter_name IN (
				N'Active parallel threads',
				N'Active requests',
				N'Blocked tasks',
				N'CPU usage %',
				N'CPU usage % base',
				N'Query optimizations/sec',
				N'Queued requests',
				N'Requests completed/sec'
			)
		)
	);

	--Set to Med-Freq
	UPDATE targ 
	SET CounterFrequency = 2
	FROM ServerEye.DimPerformanceCounter targ
	WHERE targ.CounterFrequency = 0
	AND (
		(
			object_name = N'SQLServer:Access Methods'
			AND counter_name IN (
				N'Extent Deallocations/sec',
				N'Extents Allocated/sec',
				N'Forwarded Records/sec',
				N'Mixed page allocations/sec',
				N'Page compression attempts/sec',
				N'Page Deallocations/sec',
				N'Pages Allocated/sec',
				N'Pages compressed/sec',
				N'Probe Scans/sec',
				N'Range Scans/sec',
				N'Skipped Ghosted Records/sec',
				N'Workfiles Created/sec',
				N'Worktables Created/sec',
				N'Worktables From Cache Base',
				N'Worktables From Cache Ratio'
				)
		)
		OR (
			object_name = N'SQLServer:Buffer Manager'
			AND counter_name IN (
				N'Buffer cache hit ratio',
				N'Buffer cache hit ratio base',
				N'Database pages',
				N'Page life expectancy',
				N'Target pages'
			)
		)
		OR (
			object_name = N'SQLServer:Buffer Node'
			AND counter_name IN (
				N'Database pages',
				N'Page life expectancy'
			)
		)
		OR (
			object_name = N'SQLServer:Catalog Metadata'
			AND counter_name = N'Cache Entries Count'
			AND instance_name = N'_Total'
		)
		OR (
			object_name = N'SQLServer:CLR'
		)
		OR (
			object_name = N'SQLServer:Cursor Manager by Type'
			AND counter_name IN (N'Active cursors', N'Cached Cursor Counts', N'Cursor memory usage')
			AND instance_name = N'_Total'
		)
		OR (
			object_name = N'SQLServer:Databases'
			AND counter_name IN (
				N'Commit table entries',
				N'Group Commit Time/sec'
			)
		)
		OR (
			object_name = N'SQLServer:Exec Statistics'
			AND counter_name IN (
				N'Distributed Query',
				N'DTC calls',
				N'Extended Procedures',
				N'OLEDB calls'
			)
		)
		OR (
			object_name = N'SQLServer:General Statistics'
			AND counter_name IN (
				N'Active Temp Tables',
				N'Logical Connections',
				N'Temp Tables Creation Rate',
				N'Temp Tables For Destruction',
				N'User Connections'
			)
		)
		OR (
			object_name = N'SQLServer:Latches'
			AND counter_name IN (
				N'SuperLatch Demotions/sec',
				N'SuperLatch Promotions/sec'
			)
		)
		OR (
			object_name = N'SQLServer:Memory Manager'
		)
		OR (
			object_name = N'SQLServer:Memory Node'
		)
		OR (
			object_name = N'SQLServer:Plan Cache'
			AND counter_name IN (
				N'Cache Object Counts', N'Cache Pages'
			)
			AND instance_name = N'_Total'
		)
		OR (
			object_name = N'SQLServer:Transactions'
			AND counter_name IN (
				N'Free Space in tempdb (KB)',
				N'Longest Transaction Running Time',
				N'Version Store Size (KB)'
			)
		)
		OR (
			object_name = N'SQLServer:Workload Group Stats'
			AND counter_name IN (
				N'Max request cpu time (ms)',
				N'Max request memory grant (KB)',
				N'Reduced memory grants/sec',
				N'Suboptimal plans/sec'
			)
		)
	);

	/*
	--Set to Lo-Freq
	UPDATE targ 
	SET CounterFrequency = 3
	FROM ServerEye.DimPerformanceCounter targ
	WHERE targ.CounterFrequency = 0
	;

	SELECT *
	FROM ServerEye.DimPerformanceCounter dpc
	WHERE dpc.CounterFrequency = 0
	ORDER BY dpc.object_name, dpc.counter_name, dpc.instance_name
	*/

	ALTER INDEX [CL_CounterFrequency] ON ServerEye.DimPerformanceCounter REBUILD;
	ALTER INDEX [AKDimPerformanceCounter] ON ServerEye.DimPerformanceCounter REBUILD;

	RETURN 0;
END
GO
