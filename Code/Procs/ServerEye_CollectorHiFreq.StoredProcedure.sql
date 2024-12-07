SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[CollectorHiFreq]
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

	FILE NAME: ServerEye.CollectorHiFreq.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.CollectorHiFreq

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs on a schedule (or initiated by a user via a viewer proc) and calls various sub-procs to gather miscellaneous 
		server-level DMV data. Collects data for metrics that we want captured at a high frequency (by default every 1 minute)

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

	DECLARE @errorloc NVARCHAR(100),
			@err__ErrorSeverity INT, 
			@err__ErrorState INT, 
			@err__ErrorText NVARCHAR(4000),
			@lv__osisNULLID INT,
			@lv__CurrentOsisID INT,
			@lv__scratchint INT;


BEGIN TRY
	--sys.dm_os_sys_info. Find the row for our "Current" time window
	SET @errorloc = 'osis1'
	SELECT @lv__osisNULLID = d.osisID
	FROM ServerEye.dm_os_sys_info_stable d
	WHERE d.EffectiveEndTimeUTC IS NULL;

	IF @lv__osisNULLID IS NULL
	BEGIN
		--no rows exist here yet. Insert
		SET @errorloc = 'osis2'
		INSERT INTO ServerEye.dm_os_sys_info_stable (
			EffectiveStartTimeUTC,
			EffectiveEndTimeUTC,
			EffectiveStartTime,
			EffectiveEndTime,
			sqlserver_start_time_ms_ticks,
			sqlserver_start_time,
			cpu_count,
			hyperthread_ratio,
			--physical_memory_in_bytes,
			physical_memory_kb,
			--virtual_memory_in_bytes,
			virtual_memory_kb,
			stack_size_in_bytes,
			os_quantum,
			os_error_mode,
			os_priority_class,
			max_workers_count,
			scheduler_count,
			scheduler_total_count,
			deadlock_monitor_serial_number,
			affinity_type,
			affinity_type_desc,
			time_source,
			time_source_desc,
			virtual_machine_type,
			virtual_machine_type_desc
		)
		SELECT
			[EffectiveStartTimeUTC] = @UTCCaptureTime, 
			[EffectiveEndTimeUTC] = NULL,  
			[EffectiveStartTime] = @LocalCaptureTime, 
			[EffectiveEndTime] = NULL, 
			sqlserver_start_time_ms_ticks,
			sqlserver_start_time,
			cpu_count,
			hyperthread_ratio,
			--physical_memory_in_bytes,
			physical_memory_kb,
			--virtual_memory_in_bytes,
			virtual_memory_kb,
			stack_size_in_bytes,
			os_quantum,
			os_error_mode,
			os_priority_class,
			max_workers_count,
			scheduler_count,
			scheduler_total_count,
			deadlock_monitor_serial_number,
			affinity_type,
			affinity_type_desc,
			time_source,
			time_source_desc,
			virtual_machine_type,
			virtual_machine_type_desc
		FROM sys.dm_os_sys_info dosi;

		SET @lv__CurrentOsisID = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		--rows exist, and we have the ID of the "current status" row.
		-- Compare to see if the DMV contents are different. 
		SET @errorloc = 'osis3'
		INSERT INTO ServerEye.dm_os_sys_info_stable (
			EffectiveStartTimeUTC,
			EffectiveEndTimeUTC,
			EffectiveStartTime,
			EffectiveEndTime,
			sqlserver_start_time_ms_ticks,
			sqlserver_start_time,
			cpu_count,
			hyperthread_ratio,
			--physical_memory_in_bytes,
			physical_memory_kb,
			--virtual_memory_in_bytes,
			virtual_memory_kb,
			stack_size_in_bytes,
			os_quantum,
			os_error_mode,
			os_priority_class,
			max_workers_count,
			scheduler_count,
			scheduler_total_count,
			deadlock_monitor_serial_number,
			affinity_type,
			affinity_type_desc,
			time_source,
			time_source_desc,
			virtual_machine_type,
			virtual_machine_type_desc
		)
		SELECT 
			[EffectiveStartTimeUTC] = @UTCCaptureTime, 
			[EffectiveEndTimeUTC] = NULL, 
			[EffectiveStartTime] = @LocalCaptureTime, 
			[EffectiveEndTime] = NULL, 
			sqlserver_start_time_ms_ticks,
			sqlserver_start_time,
			cpu_count,
			hyperthread_ratio,
			--physical_memory_in_bytes,
			physical_memory_kb,
			--virtual_memory_in_bytes,
			virtual_memory_kb,
			stack_size_in_bytes,
			os_quantum,
			os_error_mode,
			os_priority_class,
			max_workers_count,
			scheduler_count,
			scheduler_total_count,
			deadlock_monitor_serial_number,
			affinity_type,
			affinity_type_desc,
			time_source,
			time_source_desc,
			virtual_machine_type,
			virtual_machine_type_desc
		FROM sys.dm_os_sys_info dosi
		WHERE NOT EXISTS (
			SELECT *
			FROM ServerEye.dm_os_sys_info_stable osis
			WHERE osisID = @lv__osisNULLID
			AND osis.sqlserver_start_time_ms_ticks = dosi.sqlserver_start_time_ms_ticks
			AND osis.sqlserver_start_time = dosi.sqlserver_start_time
			AND osis.cpu_count = dosi.cpu_count
			AND osis.hyperthread_ratio = dosi.hyperthread_ratio
			--AND osis.physical_memory_in_bytes = dosi.physical_memory_in_bytes
			AND osis.physical_memory_kb = dosi.physical_memory_kb
			--AND osis.virtual_memory_in_bytes = dosi.virtual_memory_in_bytes
			AND osis.virtual_memory_kb = dosi.virtual_memory_kb
			AND osis.stack_size_in_bytes = dosi.stack_size_in_bytes
			AND osis.os_quantum = dosi.os_quantum
			AND osis.os_error_mode = dosi.os_error_mode
			AND ISNULL(osis.os_priority_class,-555) = ISNULL(dosi.os_priority_class,-555)
			AND osis.max_workers_count = dosi.max_workers_count
			AND osis.scheduler_count = dosi.scheduler_count
			AND osis.scheduler_total_count = dosi.scheduler_total_count
			AND osis.deadlock_monitor_serial_number = dosi.deadlock_monitor_serial_number
			AND osis.affinity_type = dosi.affinity_type
			AND osis.affinity_type_desc = dosi.affinity_type_desc
			AND osis.time_source = dosi.time_source
			AND osis.time_source_desc = dosi.time_source_desc
			AND osis.virtual_machine_type = dosi.virtual_machine_type
			AND osis.virtual_machine_type_desc = dosi.virtual_machine_type_desc
		);

		SET @lv__scratchint = @@ROWCOUNT;

		IF @lv__scratchint > 0
		BEGIN
			SET @lv__CurrentOsisID = SCOPE_IDENTITY();

			SET @errorloc = 'osis4'
			UPDATE ServerEye.dm_os_sys_info_stable
			SET EffectiveEndTimeUTC = @UTCCaptureTime,
				EffectiveEndTime = @LocalCaptureTime
			WHERE osisID = @lv__osisNULLID;
		END
		ELSE
		BEGIN
			SET @lv__CurrentOsisID = @lv__osisNULLID;
		END
	END	--IF @osisNULL IS NULL

	SET @errorloc = 'osis5'
	INSERT INTO [ServerEye].[SysInfoSingleRow](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[StableOSIID],

		--metrics from sys.dm_os_sys_info (that are volatile enough to not be in ServerEye.dm_os_sys_info)
		[cpu_ticks],
		[ms_ticks],
		[committed_kb],
		--[bpool_committed],
		[committed_target_kb],
		--[bpool_commit_target],
		[visible_target_kb],
		--[bpool_visible],
		[process_kernel_time_ms],
		[process_user_time_ms],

		--columns from sys.dm_os_process_memory
		[physical_memory_in_use_kb],
		[large_page_allocations_kb],
		[locked_page_allocations_kb],
		[total_virtual_address_space_kb],
		[virtual_address_space_reserved_kb],
		[virtual_address_space_committed_kb],
		[virtual_address_space_available_kb],
		[page_fault_count],
		[memory_utilization_percentage],
		[available_commit_limit_kb],
		[process_physical_memory_low],
		[process_virtual_memory_low],

		--columns from sys.dm_os_sys_memory
		[total_physical_memory_kb],
		[available_physical_memory_kb],
		[total_page_file_kb],
		[available_page_file_kb],
		[system_cache_kb],
		[kernel_paged_pool_kb],
		[kernel_nonpaged_pool_kb],
		[system_high_memory_signal_state],
		[system_low_memory_signal_state],
		[system_memory_state_desc],

		--data from sys.dm_os_tasks, just for background tasks, aggregated to a single row
		[NumBackgroundTasks],
		[task__context_switches_count],
		[task__pending_io_count],
		[task__pending_io_byte_count],

		--data from sys.dm_os_threads, for all threads, aggregated to a single row
		[NumThreads],
		[NumThreadsStartedBySQLServer],
		[SumKernelTime],
		[SumUsermodeTime],
		[SumStackBytesCommitted],
		[SumStackBytesUsed],

		--data from sys.dm_db_session_space_usage, just for background spids, aggregated to a single row
		[bkgdsess__user_objects_alloc_page_count],
		[bkgdsess__user_objects_dealloc_page_count],
		[bkgdsess__internal_objects_alloc_page_count],
		[bkgdsess__internal_objects_dealloc_page_count],
		[bkgdsess__user_objects_deferred_dealloc_page_count],

		--data from sys.dm_db_task_space_usage, just for background tasks, aggregate to a single row
		[bkgdtask__user_objects_alloc_page_count],
		[bkgdtask__user_objects_dealloc_page_count],
		[bkgdtask__internal_objects_alloc_page_count],
		[bkgdtask__internal_objects_dealloc_page_count]
	)
	SELECT 
		@UTCCaptureTime, 
		@LocalCaptureTime, 
		@lv__CurrentOsisID,

		--metrics from sys.dm_os_sys_info (that are volatile enough to not be in ServerEye.dm_os_sys_info)
		i.cpu_ticks, 
		i.ms_ticks, 
		i.committed_kb, 
		--i.bpool_committed, 
		i.committed_target_kb,
		--i.bpool_commit_target, 
		i.visible_target_kb, 
		--i.bpool_visible, 
		i.process_kernel_time_ms, 
		i.process_user_time_ms,
		
		--columns from sys.dm_os_process_memory
		pm.physical_memory_in_use_kb,
		pm.large_page_allocations_kb,
		pm.locked_page_allocations_kb,
		pm.total_virtual_address_space_kb,
		pm.virtual_address_space_reserved_kb,
		pm.virtual_address_space_committed_kb,
		pm.virtual_address_space_available_kb,
		pm.page_fault_count,
		pm.memory_utilization_percentage,
		pm.available_commit_limit_kb,
		pm.process_physical_memory_low,
		pm.process_virtual_memory_low,

		--columns from sys.dm_os_sys_memory
		sysm.total_physical_memory_kb,
		sysm.available_physical_memory_kb,
		sysm.total_page_file_kb,
		sysm.available_page_file_kb,
		sysm.system_cache_kb,
		sysm.kernel_paged_pool_kb,
		sysm.kernel_nonpaged_pool_kb,
		sysm.system_high_memory_signal_state,
		sysm.system_low_memory_signal_state,
		sysm.system_memory_state_desc,

		--data from sys.dm_os_tasks, just for background tasks, aggregated to a single row
		tsk.NumBackgroundTasks,
		tsk.task__context_switches_count,
		tsk.task__pending_io_count,
		tsk.task__pending_io_byte_count,

		--data from sys.dm_os_threads, for all threads, aggregated to a single row
		thr.NumThreads,
		thr.NumThreadsStartedBySQLServer,
		thr.SumKernelTime,
		thr.SumUsermodeTime,
		thr.SumStackBytesCommitted,
		thr.SumStackBytesUsed,

		--data from sys.dm_db_session_space_usage, just for background spids, aggregated to a single row
		su.bkgdsess__user_objects_alloc_page_count,
		su.bkgdsess__user_objects_dealloc_page_count,
		su.bkgdsess__internal_objects_alloc_page_count,
		su.bkgdsess__internal_objects_dealloc_page_count,
		su.bkgdsess__user_objects_deferred_dealloc_page_count,

		--data from sys.dm_db_task_space_usage, just for background tasks, aggregate to a single row
		tu.bkgdtask__user_objects_alloc_page_count,
		tu.bkgdtask__user_objects_dealloc_page_count,
		tu.bkgdtask__internal_objects_alloc_page_count,
		tu.bkgdtask__internal_objects_dealloc_page_count
	FROM sys.dm_os_sys_info i
		CROSS JOIN sys.dm_os_process_memory pm
		CROSS JOIN sys.dm_os_sys_memory sysm
		CROSS JOIN (
			SELECT 
				[NumBackgroundTasks] = COUNT(*),
				[task__context_switches_count] = SUM(t.context_switches_count),
				[task__pending_io_count] = SUM(t.pending_io_count),
				[task__pending_io_byte_count] = SUM(t.pending_io_byte_count)
			FROM sys.dm_os_tasks t
				LEFT OUTER JOIN sys.dm_exec_sessions se
					ON t.session_id = se.session_id
			WHERE (t.session_id IS NULL
				OR se.is_user_process = 0)
			AND t.task_state <> 'DONE'
		) tsk
		CROSS JOIN (
			SELECT 
				[NumThreads] = COUNT(*),
				[NumThreadsStartedBySQLServer] = SUM(CASE WHEN t.started_by_sqlservr = 1 THEN 1 ELSE 0 END),
				[SumKernelTime] = SUM(t.kernel_time),
				[SumUsermodeTime] = SUM(t.usermode_time),
				[SumStackBytesCommitted] = SUM(t.stack_bytes_committed),
				[SumStackBytesUsed] = SUM(t.stack_bytes_used)
			FROM sys.dm_os_threads t
		) thr
		CROSS JOIN (
			SELECT 
				[bkgdsess__user_objects_alloc_page_count] = SUM(su.user_objects_alloc_page_count),
				[bkgdsess__user_objects_dealloc_page_count] = SUM(su.user_objects_dealloc_page_count),
				[bkgdsess__internal_objects_alloc_page_count] = SUM(su.internal_objects_alloc_page_count),
				[bkgdsess__internal_objects_dealloc_page_count] = SUM(su.internal_objects_dealloc_page_count),
				[bkgdsess__user_objects_deferred_dealloc_page_count] = SUM(su.user_objects_deferred_dealloc_page_count)
			FROM sys.dm_db_session_space_usage su
				INNER JOIN sys.dm_exec_sessions se
					ON se.session_id = su.session_id
			WHERE se.is_user_process = 0
			AND su.database_id = 2
		) su
		CROSS JOIN (
			SELECT 
				[bkgdtask__user_objects_alloc_page_count] = SUM(t.user_objects_alloc_page_count),
				[bkgdtask__user_objects_dealloc_page_count] = SUM(t.user_objects_dealloc_page_count),
				[bkgdtask__internal_objects_alloc_page_count] = SUM(t.internal_objects_alloc_page_count),
				[bkgdtask__internal_objects_dealloc_page_count] = SUM(t.internal_objects_dealloc_page_count)
			FROM sys.dm_db_task_space_usage t
				INNER JOIN sys.dm_exec_sessions se
					ON se.session_id = t.session_id
			WHERE se.is_user_process = 0
			AND t.database_id = 2
		) tu;





	SET @errorloc = 'dm_db_file_space_usage';
	INSERT INTO [ServerEye].[dm_db_file_space_usage]
	(
		UTCCapturetime,
		LocalCaptureTime,
		database_id, 
		file_id,
		filegroup_id, 
		total_page_count, 
		allocated_extent_page_count, 
		unallocated_extent_page_count, 
		version_store_reserved_page_count, 
		user_object_reserved_page_count, 
		internal_object_reserved_page_count, 
		mixed_extent_page_count
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		database_id, 
		file_id,
		filegroup_id, 
		total_page_count, 
		allocated_extent_page_count, 
		unallocated_extent_page_count, 
		version_store_reserved_page_count, 
		user_object_reserved_page_count, 
		internal_object_reserved_page_count, 
		mixed_extent_page_count
	FROM tempdb.sys.dm_db_file_space_usage;

	SET @errorloc = 'dm_os_memory_nodes';
	INSERT INTO [ServerEye].[dm_os_memory_nodes](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[memory_node_id],
		[virtual_address_space_reserved_kb],
		[virtual_address_space_committed_kb],
		[locked_page_allocations_kb],
		[pages_kb],
		[shared_memory_reserved_kb],
		[shared_memory_committed_kb],
		[cpu_affinity_mask],
		[online_scheduler_mask],
		[processor_group],
		[foreign_committed_kb]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[memory_node_id],
		[virtual_address_space_reserved_kb],
		[virtual_address_space_committed_kb],
		[locked_page_allocations_kb],
		[pages_kb],
		[shared_memory_reserved_kb],
		[shared_memory_committed_kb],
		[cpu_affinity_mask],
		[online_scheduler_mask],
		[processor_group],
		[foreign_committed_kb]
	FROM sys.dm_os_memory_nodes n;

	SET @errorloc = 'dm_os_nodes';
	INSERT INTO [ServerEye].[dm_os_nodes](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[node_id],
		[node_state_desc],
		[memory_node_id],
		[cpu_affinity_mask],
		[online_scheduler_count],
		[idle_scheduler_count],
		[active_worker_count],
		[avg_load_balance],
		[resource_monitor_state],
		[online_scheduler_mask],
		[processor_group]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		n.node_id,
		n.node_state_desc,
		n.memory_node_id,
		n.cpu_affinity_mask,
		n.online_scheduler_count,
		n.idle_scheduler_count,
		n.active_worker_count,
		n.avg_load_balance,
		n.resource_monitor_state,
		n.online_scheduler_mask,
		n.processor_group
	FROM sys.dm_os_nodes n;

	SET @errorloc = 'dm_os_nodes';
	INSERT INTO [ServerEye].[dm_os_memory_broker_clerks](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[clerk_name],
		[total_kb],
		[simulated_kb],
		[simulation_benefit],
		[internal_benefit],
		[external_benefit],
		[value_of_memory],
		[periodic_freed_kb],
		[internal_freed_kb]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[clerk_name],
		[total_kb],
		[simulated_kb],
		[simulation_benefit],
		[internal_benefit],
		[external_benefit],
		[value_of_memory],
		[periodic_freed_kb],
		[internal_freed_kb]
	FROM sys.dm_os_memory_broker_clerks m;
	
	SET @errorloc = 'dm_os_schedulers';
	INSERT INTO [ServerEye].[dm_os_schedulers](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[parent_node_id],
		[scheduler_id],
		[cpu_id],
		[status],
		[is_online],
		[is_idle],
		[preemptive_switches_count],
		[context_switches_count],
		[idle_switches_count],
		[current_tasks_count],
		[runnable_tasks_count],
		[current_workers_count],
		[active_workers_count],
		[work_queue_count],
		[pending_disk_io_count],
		[load_factor],
		[yield_count],
		[last_timer_activity],

		[sum_is_preemptive],
		[sum_is_sick],
		[sum_is_in_cc_exception],
		[sum_is_fatal_exception],
		[sum_is_inside_catch],
		[sum_is_in_polling_io_completion_routine],
		[sum_context_switch_count],
		[sum_pending_io_count],
		[sum_pending_io_byte_count],
		[sum_tasks_processed_count],
		[NumWorkers]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[parent_node_id],
		[scheduler_id],
		[cpu_id],
		[status],
		[is_online],
		[is_idle],
		[preemptive_switches_count],
		[context_switches_count],
		[idle_switches_count],
		[current_tasks_count],
		[runnable_tasks_count],
		[current_workers_count],
		[active_workers_count],
		[work_queue_count],
		[pending_disk_io_count],
		[load_factor],
		[yield_count],
		[last_timer_activity],

		[sum_is_preemptive] = ISNULL(w.sum_is_preemptive,0),
		[sum_is_sick] = ISNULL(w.sum_is_sick,0),
		[sum_is_in_cc_exception] = ISNULL(w.sum_is_in_cc_exception,0),
		[sum_is_fatal_exception] = ISNULL(w.sum_is_fatal_exception,0),
		[sum_is_inside_catch] = ISNULL(w.sum_is_inside_catch,0),
		[sum_is_in_polling_io_completion_routine] = ISNULL(w.sum_is_in_polling_io_completion_routine,0),
		[sum_context_switch_count] = ISNULL(w.sum_context_switch_count,0),
		[sum_pending_io_count] = ISNULL(w.sum_pending_io_count,0),
		[sum_pending_io_byte_count] = ISNULL(w.sum_pending_io_byte_count,0),
		[sum_tasks_processed_count] = ISNULL(w.sum_tasks_processed_count,0),
		[NumWorkers] = ISNULL(w.NumWorkers,0)
	FROM sys.dm_os_schedulers s
		LEFT OUTER JOIN (
		SELECT 
			w.scheduler_address,
			[sum_is_preemptive] = SUM(CASE WHEN w.is_preemptive = 1 THEN 1 ELSE 0 END),
			[sum_is_sick] = SUM(CASE WHEN w.is_sick = 1 THEN 1 ELSE 0 END),
			[sum_is_in_cc_exception] = SUM(CASE WHEN w.is_in_cc_exception = 1 THEN 1 ELSE 0 END),
			[sum_is_fatal_exception] = SUM(CASE WHEN w.is_fatal_exception = 1 THEN 1 ELSE 0 END),
			[sum_is_inside_catch] = SUM(CASE WHEN w.is_inside_catch = 1 THEN 1 ELSE 0 END),
			[sum_is_in_polling_io_completion_routine] = SUM(CASE WHEN w.is_in_polling_io_completion_routine = 1 THEN 1 ELSE 0 END),
			[sum_context_switch_count] = SUM(w.context_switch_count),
			[sum_pending_io_count] = SUM(w.pending_io_count),
			[sum_pending_io_byte_count] = SUM(w.pending_io_byte_count),
			[sum_tasks_processed_count] = SUM(w.tasks_processed_count),
			NumWorkers = COUNT(*)
		FROM sys.dm_os_workers w
		GROUP BY w.scheduler_address
		) w
			ON w.scheduler_address = s.scheduler_address;


	SET @errorloc = 'Hi-Freq Perfmon';
	INSERT INTO [ServerEye].[FactPerformanceCounter](
		[UTCCaptureTime],
		[DimPerformanceCounterID],
		[cntr_value]
	)
	SELECT 
		@UTCCaptureTime,
		dpc.DimPerformanceCounterID,
		pc.cntr_value
	FROM ServerEye.DimPerformanceCounter dpc
		INNER hash JOIN
		sys.dm_os_performance_counters pc
			ON dpc.object_name = pc.object_name
			AND dpc.counter_name = pc.counter_name
			AND dpc.instance_name = pc.instance_name
	WHERE dpc.CounterFrequency = 1		--Hi-freq code
	OPTION(FORCE ORDER);

END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @err__ErrorSeverity = ERROR_SEVERITY();
	SET @err__ErrorState = ERROR_STATE();
	SET @err__ErrorText = N'Unexpected exception occurred at location "' + ISNULL(@errorloc,N'<null>') + '". Error #: ' + 
		CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
		CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

	RAISERROR(@err__ErrorText, @err__ErrorSeverity, @err__ErrorState);
	RETURN -1;
END CATCH


	RETURN 0;
END
GO