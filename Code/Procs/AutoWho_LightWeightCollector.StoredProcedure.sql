SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_LightWeightCollector
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

	FILE NAME: AutoWho_LightweightCollector.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_LightweightCollector

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: When the normal collector procedure runs > 30 seconds, "something is wrong". This procedure is lighter-weight
		in the sense that it only pulls from 3 DMVs (the most important ones in a slammed system) and uses loop joins
		and MAXDOP 1 to avoid anything like a memory grant. The main purpose is to grab *something* to find out what
		was happening at this time.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_LightWeightCollector
*/
AS
BEGIN
	DECLARE @SPIDCaptureTime DATETIME,
		@UTCCaptureTime DATETIME,
		@lv__ErrorLoc NVARCHAR(40), 
		@lv__ErrorMessage NVARCHAR(4000),
		@lv__ErrorState INT,
		@lv__ErrorSeverity INT;

	SET @SPIDCaptureTime = GETDATE();
	SET @UTCCaptureTime = GETUTCDATE();

	BEGIN TRY

		--Note that in the below queries we use LOOP joins so we don't have to wait for memory grants.
		--Yes, this means that the DMV contents are even further from representing any "specific point in time"
		-- than they normally are, but at least the below queries should run, barring CPU being completely pegged.
		SET @lv__ErrorLoc = N'sess';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_LightweightSessions
		(
			SPIDCaptureTime, UTCCaptureTime, sess__session_id, sess__login_time, sess__host_name, sess__program_name, 
			sess__host_process_id, sess__client_version, sess__client_interface_name, sess__security_id, 
			sess__login_name, sess__nt_domain, sess__nt_user_name, sess__status, sess__context_info, 
			sess__cpu_time, sess__memory_usage, sess__total_scheduled_time, sess__total_elapsed_time, 
			sess__endpoint_id, sess__last_request_start_time, sess__last_request_end_time, sess__reads, 
			sess__writes, sess__logical_reads, sess__is_user_process, sess__text_size, sess__language, 
			sess__date_format, sess__date_first, sess__quoted_identifier, sess__arithabort, sess__ansi_null_dflt_on, 
			sess__ansi_defaults, sess__ansi_warnings, sess__ansi_padding, sess__ansi_nulls, sess__concat_null_yields_null, 
			sess__transaction_isolation_level, sess__lock_timeout, sess__deadlock_priority, sess__row_count, sess__prev_error, 
			sess__original_security_id, sess__original_login_name, sess__last_successful_logon, sess__last_unsuccessful_logon, 
			sess__unsuccessful_logons, sess__group_id, sess__database_id, sess__authenticating_database_id, sess__open_transaction_count, 
			conn__most_recent_session_id, conn__connect_time, conn__net_transport, conn__protocol_type, conn__protocol_version, 
			conn__endpoint_id, conn__encrypt_option, conn__auth_scheme, conn__node_affinity, conn__num_reads, conn__num_writes, 
			conn__last_read, conn__last_write, conn__net_packet_size, conn__client_net_address, conn__client_tcp_port, 
			conn__local_net_address, conn__local_tcp_port, conn__connection_id, conn__parent_connection_id, conn__most_recent_sql_handle, 
			rqst__request_id, rqst__start_time, rqst__status, rqst__command, rqst__sql_handle, rqst__statement_start_offset, 
			rqst__statement_end_offset, rqst__plan_handle, rqst__database_id, rqst__user_id, rqst__connection_id, rqst__blocking_session_id, 
			rqst__wait_type, rqst__wait_time, rqst__last_wait_type, rqst__wait_resource, rqst__open_transaction_count, 
			rqst__open_resultset_count, rqst__transaction_id, rqst__context_info, rqst__percent_complete, rqst__estimated_completion_time, 
			rqst__cpu_time, rqst__total_elapsed_time, rqst__scheduler_id, rqst__task_address, rqst__reads, rqst__writes, rqst__logical_reads, 
			rqst__text_size, rqst__language, rqst__date_format, rqst__date_first, rqst__quoted_identifier, rqst__arithabort, 
			rqst__ansi_null_dflt_on, rqst__ansi_defaults, rqst__ansi_warnings, rqst__ansi_padding, rqst__ansi_nulls, 
			rqst__concat_null_yields_null, rqst__transaction_isolation_level, rqst__lock_timeout, rqst__deadlock_priority, rqst__row_count, 
			rqst__prev_error, rqst__nest_level, rqst__granted_query_memory, rqst__executing_managed_code, rqst__group_id, rqst__query_hash, 
			rqst__query_plan_hash, rqst__statement_sql_handle, rqst__statement_context_id, sess__internal_objects_alloc_page_count, 
			sess__internal_objects_dealloc_page_count, sess__user_objects_alloc_page_count, sess__user_objects_dealloc_page_count, 
			mgrant__scheduler_id, mgrant__dop, mgrant__request_time, mgrant__grant_time, mgrant__requested_memory_kb, mgrant__granted_memory_kb, 
			mgrant__required_memory_kb, mgrant__used_memory_kb, mgrant__max_used_memory_kb, mgrant__query_cost, mgrant__timeout_sec, 
			mgrant__resource_semaphore_id, mgrant__queue_id, mgrant__wait_order, mgrant__is_next_candidate, mgrant__wait_time_ms, 
			mgrant__plan_handle, mgrant__sql_handle, mgrant__group_id, mgrant__pool_id, mgrant__is_small, mgrant__ideal_memory_kb
		)
		SELECT 
			[SPIDCaptureTime] = @SPIDCaptureTime
			,[UTCCaptureTime] = @UTCCaptureTime
			,sess__session_id = s.session_id
			,sess__login_time = s.login_time
			,sess__host_name = s.host_name
			,sess__program_name = s.program_name
			,sess__host_process_id = s.host_process_id	
			,sess__client_version = s.client_version	
			,sess__client_interface_name = s.client_interface_name	
			,sess__security_id = s.security_id	
			,sess__login_name = s.login_name	
			,sess__nt_domain = s.nt_domain	
			,sess__nt_user_name = s.nt_user_name	
			,sess__status = s.status	
			,sess__context_info = s.context_info	
			,sess__cpu_time = s.cpu_time	
			,sess__memory_usage = s.memory_usage	
			,sess__total_scheduled_time = s.total_scheduled_time	
			,sess__total_elapsed_time = s.total_elapsed_time	
			,sess__endpoint_id = s.endpoint_id	
			,sess__last_request_start_time = s.last_request_start_time	
			,sess__last_request_end_time = s.last_request_end_time	
			,sess__reads = s.reads	
			,sess__writes = s.writes	
			,sess__logical_reads = s.logical_reads	
			,sess__is_user_process = s.is_user_process	
			,sess__text_size = s.text_size	
			,sess__language = s.language	
			,sess__date_format = s.date_format	
			,sess__date_first = s.date_first	
			,sess__quoted_identifier = s.quoted_identifier	
			,sess__arithabort = s.arithabort	
			,sess__ansi_null_dflt_on = s.ansi_null_dflt_on	
			,sess__ansi_defaults = s.ansi_defaults	
			,sess__ansi_warnings = s.ansi_warnings	
			,sess__ansi_padding = s.ansi_padding	
			,sess__ansi_nulls = s.ansi_nulls	
			,sess__concat_null_yields_null = s.concat_null_yields_null	
			,sess__transaction_isolation_level = s.transaction_isolation_level	
			,sess__lock_timeout = s.lock_timeout	
			,sess__deadlock_priority = s.deadlock_priority	
			,sess__row_count = s.row_count	
			,sess__prev_error = s.prev_error	
			,sess__original_security_id = s.original_security_id	
			,sess__original_login_name = s.original_login_name	
			,sess__last_successful_logon = s.last_successful_logon	
			,sess__last_unsuccessful_logon = s.last_unsuccessful_logon	
			,sess__unsuccessful_logons = s.unsuccessful_logons	
			,sess__group_id = s.group_id
			,p.dbid		--when I make version-sensitive builds, use this for 2012+: ,sess__database_id = s.database_id	
			,null --when I make version-sensitive builds, use this for 2012+: ,sess__authenticating_database_id = s.authenticating_database_id	
			,p.open_tran --when I make version-sensitive builds, use this for 2012+: ,sess__open_transaction_count = s.open_transaction_count
			,conn__most_recent_session_id = c.most_recent_session_id	
			,conn__connect_time = c.connect_time	
			,conn__net_transport = c.net_transport	
			,conn__protocol_type = c.protocol_type	
			,conn__protocol_version = c.protocol_version	
			,conn__endpoint_id = c.endpoint_id	
			,conn__encrypt_option = c.encrypt_option	
			,conn__auth_scheme = c.auth_scheme	
			,conn__node_affinity = c.node_affinity	
			,conn__num_reads = c.num_reads	
			,conn__num_writes = c.num_writes	
			,conn__last_read = c.last_read	
			,conn__last_write = c.last_write	
			,conn__net_packet_size = c.net_packet_size	
			,conn__client_net_address = c.client_net_address	
			,conn__client_tcp_port = c.client_tcp_port	
			,conn__local_net_address = c.local_net_address	
			,conn__local_tcp_port = c.local_tcp_port	
			,conn__connection_id = c.connection_id	
			,conn__parent_connection_id = c.parent_connection_id	
			,conn__most_recent_sql_handle = c.most_recent_sql_handle
			,rqst__request_id = r.request_id	
			,rqst__start_time = r.start_time	
			,rqst__status = r.status	
			,rqst__command = r.command	
			,rqst__sql_handle = r.sql_handle	
			,rqst__statement_start_offset = r.statement_start_offset	
			,rqst__statement_end_offset = r.statement_end_offset	
			,rqst__plan_handle = r.plan_handle	
			,rqst__database_id = r.database_id	
			,rqst__user_id = r.user_id	
			,rqst__connection_id = r.connection_id	
			,rqst__blocking_session_id = r.blocking_session_id	
			,rqst__wait_type = r.wait_type	
			,rqst__wait_time = r.wait_time	
			,rqst__last_wait_type = r.last_wait_type	
			,rqst__wait_resource = r.wait_resource	
			--TODO: ditto... this col is not in 2008. Do I need it?
			,null --,rqst__open_transaction_count = r.open_transaction_count	
			,rqst__open_resultset_count = r.open_resultset_count	
			,rqst__transaction_id = r.transaction_id	
			,rqst__context_info = r.context_info	
			,rqst__percent_complete = r.percent_complete	
			,rqst__estimated_completion_time = r.estimated_completion_time	
			,rqst__cpu_time = r.cpu_time	
			,rqst__total_elapsed_time = r.total_elapsed_time	
			,rqst__scheduler_id = r.scheduler_id	
			,rqst__task_address = r.task_address	
			,rqst__reads = r.reads	
			,rqst__writes = r.writes	
			,rqst__logical_reads = r.logical_reads	
			,rqst__text_size = r.text_size	
			,rqst__language = r.language	
			,rqst__date_format = r.date_format	
			,rqst__date_first = r.date_first	
			,rqst__quoted_identifier = r.quoted_identifier	
			,rqst__arithabort = r.arithabort	
			,rqst__ansi_null_dflt_on = r.ansi_null_dflt_on	
			,rqst__ansi_defaults = r.ansi_defaults	
			,rqst__ansi_warnings = r.ansi_warnings	
			,rqst__ansi_padding = r.ansi_padding	
			,rqst__ansi_nulls = r.ansi_nulls	
			,rqst__concat_null_yields_null = r.concat_null_yields_null	
			,rqst__transaction_isolation_level = r.transaction_isolation_level	
			,rqst__lock_timeout = r.lock_timeout	
			,rqst__deadlock_priority = r.deadlock_priority	
			,rqst__row_count = r.row_count	
			,rqst__prev_error = r.prev_error	
			,rqst__nest_level = r.nest_level	
			,rqst__granted_query_memory = r.granted_query_memory	
			,rqst__executing_managed_code = r.executing_managed_code	
			,rqst__group_id = r.group_id	
			,rqst__query_hash = r.query_hash	
			,rqst__query_plan_hash = r.query_plan_hash	
			,null		--not in SQL 2008 (do I need it at all?),rqst__statement_sql_handle = r.statement_sql_handle	
			,null		--not in SQL 2008 (do I need it at all?),rqst__statement_context_id = r.statement_context_id
			,sess__internal_objects_alloc_page_count = spc.internal_objects_alloc_page_count
			,sess__internal_objects_dealloc_page_count = spc.internal_objects_dealloc_page_count
			,sess__user_objects_alloc_page_count = spc.user_objects_alloc_page_count
			,sess__user_objects_dealloc_page_count = spc.user_objects_dealloc_page_count
			,mgrant__scheduler_id = m.scheduler_id
			,mgrant__dop = m.dop
			,mgrant__request_time = m.request_time
			,mgrant__grant_time = m.grant_time
			,mgrant__requested_memory_kb = m.requested_memory_kb
			,mgrant__granted_memory_kb = m.granted_memory_kb
			,mgrant__required_memory_kb = m.required_memory_kb
			,mgrant__used_memory_kb = m.used_memory_kb
			,mgrant__max_used_memory_kb = m.max_used_memory_kb
			,mgrant__query_cost = m.query_cost
			,mgrant__timeout_sec = m.timeout_sec
			,mgrant__resource_semaphore_id = m.resource_semaphore_id
			,mgrant__queue_id = m.queue_id
			,mgrant__wait_order = m.wait_order
			,mgrant__is_next_candidate = m.is_next_candidate
			,mgrant__wait_time_ms = m.wait_time_ms
			,mgrant__plan_handle = m.plan_handle
			,mgrant__sql_handle = m.sql_handle
			,mgrant__group_id = m.group_id
			,mgrant__pool_id = m.pool_id
			,mgrant__is_small = m.is_small
			,mgrant__ideal_memory_kb = m.ideal_memory_kb
		FROM sys.dm_exec_sessions s
			LEFT OUTER loop JOIN master.dbo.sysprocesses p
				ON s.session_id = p.spid
			LEFT OUTER loop JOIN sys.dm_exec_connections c
				ON s.session_id = c.session_id
			LEFT OUTER loop JOIN sys.dm_exec_requests r
				ON s.session_id = r.session_id
			LEFT OUTER loop JOIN sys.dm_exec_query_memory_grants m
				ON s.session_id = m.session_id
				AND r.request_id = m.request_id
			LEFT OUTER loop JOIN sys.dm_db_session_space_usage spc
				ON s.session_id = spc.session_id
				AND spc.database_id = 2
		OPTION(FORCE ORDER, MAXDOP 1)
		;

		SET @lv__ErrorLoc = N'tasks';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_LightweightTasks
		(
			SPIDCaptureTime, UTCCaptureTime, task__task_address, task__task_state, task__context_switches_count, 
			task__pending_io_count, task__pending_io_byte_count, task__pending_io_byte_average, 
			task__scheduler_id, task__session_id, task__exec_context_id, task__request_id, 
			task__worker_address, task__host_address, task__parent_task_address, taskusage__is_remote_task, 
			taskusage__user_objects_alloc_page_count, taskusage__user_objects_dealloc_page_count, 
			taskusage__internal_objects_alloc_page_count, taskusage__internal_objects_dealloc_page_count, 
			wait_duration_ms, wait_type, resource_address, blocking_task_address, blocking_session_id, 
			blocking_exec_context_id, resource_description
		)
		SELECT
			[SPIDCaptureTime] = @SPIDCaptureTime
			,[UTCCaptureTime] = @UTCCaptureTime
			,task__task_address = t.task_address	
			,task__task_state = t.task_state	
			,task__context_switches_count = t.context_switches_count
			,task__pending_io_count	= t.pending_io_count
			,task__pending_io_byte_count = t.pending_io_byte_count
			,task__pending_io_byte_average = t.pending_io_byte_average
			,task__scheduler_id	= t.scheduler_id
			,task__session_id = t.session_id
			,task__exec_context_id = t.exec_context_id
			,task__request_id = t.request_id
			,task__worker_address = t.worker_address
			,task__host_address	= t.host_address
			,task__parent_task_address = t.parent_task_address
			,null  --not in SQL 2008: ,taskusage__is_remote_task = tu.is_remote_task	
			,taskusage__user_objects_alloc_page_count = tu.user_objects_alloc_page_count	
			,taskusage__user_objects_dealloc_page_count = tu.user_objects_dealloc_page_count	
			,taskusage__internal_objects_alloc_page_count = tu.internal_objects_alloc_page_count	
			,taskusage__internal_objects_dealloc_page_count = tu.internal_objects_dealloc_page_count
			,wt.wait_duration_ms	
			,wt.wait_type	
			,wt.resource_address	
			,wt.blocking_task_address	
			,wt.blocking_session_id	
			,wt.blocking_exec_context_id	
			,wt.resource_description
		FROM sys.dm_os_tasks t
			LEFT OUTER LOOP JOIN sys.dm_db_task_space_usage tu
				ON t.session_id = tu.session_id
				AND t.request_id = tu.request_id
				AND t.exec_context_id = tu.exec_context_id
				AND tu.database_id = 2
			LEFT OUTER LOOP JOIN sys.dm_os_waiting_tasks wt
				ON t.task_address = wt.waiting_task_address
		OPTION(FORCE ORDER, MAXDOP 1)
		;

		SET @lv__ErrorLoc = N'trans';
		INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_LightweightTrans
		(
			SPIDCaptureTime, UTCCaptureTime, dtat__transaction_id, dtat__transaction_name, dtat__transaction_begin_time, dtat__transaction_type, 
			dtat__transaction_uow, dtat__transaction_state, dtat__transaction_status, dtat__transaction_status2, dtat__dtc_state, 
			dtat__dtc_status, dtat__dtc_isolation_level, dtat__filestream_transaction_id, dtst__session_id, dtst__transaction_descriptor, 
			dtst__enlist_count, dtst__is_user_transaction, dtst__is_local, dtst__is_enlisted, dtst__is_bound, dtst__open_transaction_count, 
			dtdt__database_id, dtdt__database_transaction_begin_time, dtdt__database_transaction_type, dtdt__database_transaction_state, 
			dtdt__database_transaction_status, dtdt__database_transaction_status2, dtdt__database_transaction_log_record_count, 
			dtdt__database_transaction_replicate_record_count, dtdt__database_transaction_log_bytes_used, 
			dtdt__database_transaction_log_bytes_reserved, dtdt__database_transaction_log_bytes_used_system, 
			dtdt__database_transaction_log_bytes_reserved_system, dtdt__database_transaction_begin_lsn, dtdt__database_transaction_last_lsn, 
			dtdt__database_transaction_most_recent_savepoint_lsn, dtdt__database_transaction_commit_lsn, dtdt__database_transaction_last_rollback_lsn, 
			dtdt__database_transaction_next_undo_lsn
		)
		SELECT 
			[SPIDCaptureTime] = @SPIDCaptureTime
			,[UTCCaptureTime] = @UTCCaptureTime
			,dtat__transaction_id = dtat.transaction_id	
			,dtat__transaction_name = dtat.name	
			,dtat__transaction_begin_time = dtat.transaction_begin_time	
			,dtat__transaction_type = dtat.transaction_type	
			,dtat__transaction_uow = dtat.transaction_uow	
			,dtat__transaction_state = dtat.transaction_state	
			,dtat__transaction_status = dtat.transaction_status	
			,dtat__transaction_status2 = dtat.transaction_status2	
			,dtat__dtc_state = dtat.dtc_state	
			,dtat__dtc_status = dtat.dtc_status	
			,dtat__dtc_isolation_level = dtat.dtc_isolation_level	
			,dtat__filestream_transaction_id = dtat.filestream_transaction_id
			,dtst__session_id = dtst.session_id
			,dtst__transaction_descriptor = dtst.transaction_descriptor
			,dtst__enlist_count = dtst.enlist_count
			,dtst__is_user_transaction = dtst.is_user_transaction
			,dtst__is_local = dtst.is_local
			,dtst__is_enlisted = dtst.is_enlisted
			,dtst__is_bound = dtst.is_bound
			,null  --not in SQL 2008: ,dtst__open_transaction_count = dtst.open_transaction_count
			,dtdt__database_id = dtdt.database_id	
			,dtdt__database_transaction_begin_time = dtdt.database_transaction_begin_time	
			,dtdt__database_transaction_type = dtdt.database_transaction_type	
			,dtdt__database_transaction_state = dtdt.database_transaction_state	
			,dtdt__database_transaction_status = dtdt.database_transaction_status	
			,dtdt__database_transaction_status2 = dtdt.database_transaction_status2	
			,dtdt__database_transaction_log_record_count = dtdt.database_transaction_log_record_count	
			,dtdt__database_transaction_replicate_record_count = dtdt.database_transaction_replicate_record_count	
			,dtdt__database_transaction_log_bytes_used = dtdt.database_transaction_log_bytes_used	
			,dtdt__database_transaction_log_bytes_reserved = dtdt.database_transaction_log_bytes_reserved	
			,dtdt__database_transaction_log_bytes_used_system = dtdt.database_transaction_log_bytes_used_system	
			,dtdt__database_transaction_log_bytes_reserved_system = dtdt.database_transaction_log_bytes_reserved_system	
			,dtdt__database_transaction_begin_lsn = dtdt.database_transaction_begin_lsn	
			,dtdt__database_transaction_last_lsn = dtdt.database_transaction_last_lsn	
			,dtdt__database_transaction_most_recent_savepoint_lsn = dtdt.database_transaction_most_recent_savepoint_lsn	
			,dtdt__database_transaction_commit_lsn = dtdt.database_transaction_commit_lsn	
			,dtdt__database_transaction_last_rollback_lsn = dtdt.database_transaction_last_rollback_lsn	
			,dtdt__database_transaction_next_undo_lsn = dtdt.database_transaction_next_undo_lsn
		FROM sys.dm_tran_active_transactions dtat
			LEFT OUTER LOOP JOIN sys.dm_tran_session_transactions dtst
				ON dtat.transaction_id = dtst.transaction_id
			LEFT OUTER LOOP JOIN sys.dm_tran_database_transactions dtdt
				ON dtat.transaction_id = dtdt.transaction_id
		OPTION(FORCE ORDER, MAXDOP 1);

		RETURN 0;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;

		SET @lv__ErrorSeverity = ERROR_SEVERITY();
		SET @lv__ErrorState = ERROR_STATE();

		SET @lv__ErrorMessage = N'Exception occurred at location ("' + ISNULL(@lv__ErrorLoc,N'<null>') + '"). Error #: ' + ISNULL(CONVERT(NVARCHAR(20),ERROR_NUMBER()), N'<null>') +
			N'; Severity: ' + ISNULL(CONVERT(NVARCHAR(20),@lv__ErrorSeverity), N'<null>') + 
			N'; State: ' + ISNULL(CONVERT(NVARCHAR(20),@lv__ErrorState),N'<null>') + 
			N'; Message: ' + ISNULL(ERROR_MESSAGE(),N'<null>');

		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@lv__ErrorMessage;

		RAISERROR(@lv__ErrorMessage, @lv__ErrorSeverity, @lv__ErrorState);
		RETURN -999;
	END CATCH
END
GO
