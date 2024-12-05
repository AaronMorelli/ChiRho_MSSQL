SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [CoreXR].[SessionsAndRequests] AS
/*   
   Copyright 2016 Aaron Morelli

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

	FILE NAME: CoreXR.SessionsAndRequests.View.sql

	VIEW NAME: CoreXR.SessionsAndRequests

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com
					https://github.com/AaronMorelli/ChiRho

	PURPOSE: Joins data from underlying SAR table + its Dims. Useful during debugging or ad-hoc analysis

	OUTSTANDING ISSUES: None at this time.

*/
SELECT SPIDCaptureTime, 
	session_id, 
	request_id, 
	TimeIdentifier, 
	calc__duration_ms,
	dc.command,
	dwt.wait_type, 
	calc__status_info,
	rqst__wait_time,
	sess__open_transaction_count,
	rqst__open_transaction_count, 
	calc__blocking_session_id, 
	rqst__blocking_session_id,
	calc__is_blocker,
	calc__threshold_ignore,
	calc__tmr_wait,
	tempdb__CalculatedNumberOfTasks, 
	calc__node_info,
	mgrant__granted_memory_kb, 
	sess__last_request_end_time,
	rqst__start_time,
	FKSQLStmtStoreID, 
	FKSQLBatchStoreID, 
	FKInputBufferStoreID, 
	FKQueryPlanBatchStoreID, 
	FKQueryPlanStmtStoreID,
	dln.login_name,
	dln.original_login_name,
	dsa.client_interface_name,
	dsa.client_version,
	dsa.deadlock_priority,
	dsa.endpoint_id as sess__endpoint_id,
	dsa.group_id,
	dsa.host_name,
	dsa.program_name,
	dsa.transaction_isolation_level,
	dca.auth_scheme,
	dca.encrypt_option,
	dca.endpoint_id,
	dca.net_packet_size,
	dca.net_transport,
	dca.node_affinity,
	dca.protocol_type,
	dca.protocol_version,
	sess__login_time, sess__host_process_id, sess__status_code, sess__cpu_time, 
	sess__memory_usage, sess__total_scheduled_time, sess__total_elapsed_time, sess__last_request_start_time, 
	sess__reads, sess__writes, 
	sess__logical_reads, sess__is_user_process, sess__lock_timeout, sess__row_count,  sess__database_id, 
	sess__FKDimLoginName, sess__FKDimSessionAttribute, 
	conn__connect_time, conn__FKDimNetAddress, conn__FKDimConnectionAttribute, 
	rqst__status_code,  rqst__wait_resource, 
	rqst__open_resultset_count, rqst__percent_complete, rqst__cpu_time, rqst__total_elapsed_time, rqst__scheduler_id, rqst__reads, 
	rqst__writes, rqst__logical_reads, rqst__transaction_isolation_level, rqst__lock_timeout, rqst__deadlock_priority, rqst__row_count, 
	rqst__granted_query_memory, rqst__executing_managed_code, rqst__group_id, rqst__FKDimCommand, rqst__FKDimWaitType, 
	tempdb__sess_user_objects_alloc_page_count, tempdb__sess_user_objects_dealloc_page_count, tempdb__sess_internal_objects_alloc_page_count, 
	tempdb__sess_internal_objects_dealloc_page_count, tempdb__task_user_objects_alloc_page_count, tempdb__task_user_objects_dealloc_page_count, 
	tempdb__task_internal_objects_alloc_page_count, tempdb__task_internal_objects_dealloc_page_count, 
	mgrant__request_time, mgrant__grant_time, mgrant__requested_memory_kb, mgrant__required_memory_kb, 
	mgrant__used_memory_kb, mgrant__max_used_memory_kb, mgrant__dop, calc__record_priority,  
	calc__block_relevant, calc__return_to_user,  calc__sysspid_isinteresting
FROM AutoWho.SessionsAndRequests sar
	LEFT OUTER JOIN AutoWho.DimCommand dc
		ON sar.rqst__FKDimCommand = dc.DimCommandID
	LEFT OUTER JOIN AutoWho.DimConnectionAttribute dca
		ON sar.conn__FKDimConnectionAttribute = dca.DimConnectionAttributeID
	LEFT OUTER JOIN AutoWho.DimLoginName dln
		ON sar.sess__FKDimLoginName = dln.DimLoginNameID
	LEFT OUTER JOIN AutoWho.DimNetAddress dna
		ON sar.conn__FKDimNetAddress = dna.DimNetAddressID
	LEFT OUTER JOIN AutoWho.DimSessionAttribute dsa
		ON sar.sess__FKDimSessionAttribute = dsa.DimSessionAttributeID
	LEFT OUTER JOIN AutoWho.DimWaitType dwt
		ON sar.rqst__FKDimWaitType = dwt.DimWaitTypeID
GO
