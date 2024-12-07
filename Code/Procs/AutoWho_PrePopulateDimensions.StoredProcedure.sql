SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_PrePopulateDimensions
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

	FILE NAME: AutoWho_PrePopulateDimensions.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_PrePopulateDimensions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: The AutoWho_Collector proc will populate the various dimension tables in an ad-hoc sort of way... as it
		sees dimension members, (e.g. wait types) in the DMVs and there is not a match yet in the dimension table,
		it will add the wait to the dimension table before persisting the DMV-based data into the SAR/TAW tables.

		However, if we code pre-population logic into a proc and then call that proc when the AutoWho Executor
		proc is starting up, then we can probably save some time in the Collector logic to check and then add
		dimension values.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_PrePopulateDimensions

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

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimCommand 
		(command, TimeAdded)
	SELECT r.command, GETDATE()
	FROM 
		(SELECT DISTINCT command = ISNULL(r.command,@lv__nullstring)
		FROM sys.dm_exec_requests r) r
	WHERE NOT EXISTS (
		SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimCommand dc
		WHERE dc.command = r.command
	);

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute 
		(net_transport, protocol_type, protocol_version, endpoint_id,
		node_affinity, net_packet_size, encrypt_option, auth_scheme, TimeAdded)
	SELECT net_transport, protocol_type, protocol_version, endpoint_id,
		node_affinity, net_packet_size, encrypt_option, auth_scheme, GETDATE()
	FROM (
		SELECT DISTINCT 
			net_transport = ISNULL(c.net_transport,@lv__nullstring), 
			protocol_type = ISNULL(c.protocol_type,@lv__nullstring), 
			protocol_version = ISNULL(c.protocol_version,@lv__nullint), 
			endpoint_id = ISNULL(c.endpoint_id,@lv__nullint),
			node_affinity = ISNULL(c.node_affinity,@lv__nullsmallint), 
			net_packet_size = ISNULL(c.net_packet_size, @lv__nullsmallint), 
			encrypt_option = ISNULL(c.encrypt_option, @lv__nullstring),
			auth_scheme = ISNULL(c.auth_scheme, @lv__nullstring)
		FROM sys.dm_exec_connections c
	) c
	WHERE NOT EXISTS (
		SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute dca
		WHERE dca.net_transport = c.net_transport
		AND dca.protocol_type = c.protocol_type
		AND dca.protocol_version = c.protocol_version
		AND dca.endpoint_id = c.endpoint_id
		AND dca.node_affinity = c.node_affinity
		AND dca.net_packet_size = c.net_packet_size
		AND dca.encrypt_option = c.encrypt_option
		AND dca.auth_scheme = c.auth_scheme
	);

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName
		(login_name, original_login_name)
	SELECT s.login_name, s.original_login_name
	FROM (
		SELECT DISTINCT 
			login_name = ISNULL(s.login_name,@lv__nullstring), 
			original_login_name = ISNULL(s.original_login_name,@lv__nullstring)
		FROM sys.dm_exec_sessions s
	) s
	WHERE NOT EXISTS (
		SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName dln
		WHERE dln.login_name = s.login_name
		AND dln.original_login_name = s.original_login_name
	);

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress
		(client_net_address, local_net_address, local_tcp_port, TimeAdded)
	SELECT c.client_net_address, c.local_net_address, c.local_tcp_port, GETDATE()
	FROM (
		SELECT DISTINCT 
			client_net_address = ISNULL(c.client_net_address,@lv__nullstring), 
			local_net_address = ISNULL(c.local_net_address, @lv__nullstring),
			local_tcp_port = ISNULL(c.local_tcp_port,@lv__nullint)
		FROM sys.dm_exec_connections c
	) c
	WHERE NOT EXISTS (
		SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress dna
		WHERE dna.client_net_address = c.client_net_address
		--b/c of dynamic ports, moved to SAR table: AND dna.client_tcp_port = c.client_tcp_port
		AND dna.local_net_address = c.local_net_address
		AND dna.local_tcp_port = c.local_tcp_port
	);

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute
		(host_name, program_name, client_version, client_interface_name,
		endpoint_id, transaction_isolation_level, deadlock_priority, group_id,
		TimeAdded)
	SELECT s.host_name, s.program_name, s.client_version, s.client_interface_name,
		s.endpoint_id, s.transaction_isolation_level, s.deadlock_priority, s.group_id,
		GETDATE()
	FROM (
		SELECT DISTINCT 
			host_name = ISNULL(s.host_name, @lv__nullstring), 
			program_name = ISNULL(s.program_name, @lv__nullstring),
			client_version = ISNULL(s.client_version, @lv__nullint),
			client_interface_name = ISNULL(s.client_interface_name, @lv__nullstring),
			endpoint_id = ISNULL(s.endpoint_id, @lv__nullint),
			transaction_isolation_level = ISNULL(s.transaction_isolation_level, @lv__nullsmallint),
			[deadlock_priority] = ISNULL(s.deadlock_priority, @lv__nullsmallint),
			group_id = ISNULL(s.group_id, @lv__nullint)
		FROM sys.dm_exec_sessions s
	) s
	WHERE NOT EXISTS (
		SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute dsa
		WHERE dsa.host_name = s.host_name
		AND dsa.program_name = s.program_name
		AND dsa.client_version = s.client_version
		AND dsa.client_interface_name = s.client_interface_name
		AND dsa.endpoint_id = s.endpoint_id
		AND dsa.transaction_isolation_level = s.transaction_isolation_level
		AND dsa.deadlock_priority = s.deadlock_priority
		AND dsa.group_id = s.group_id
	);

	/* For now, lets not do this with wait types. There are an awful lot of wait types, 
	and the vast majority will never be seen is session-focused DMVs. So it just makes the Dim table larger, and thus
	performance slower

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType
		(wait_type, wait_type_short, TimeAdded)
	SELECT w.wait_type, w.wait_type_short, GETDATE()
	FROM (
		SELECT DISTINCT 
			w.wait_type,
			wait_type_short = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(
				w.wait_type,
				'SLEEP_TASK','SlpTsk'),
				'PAGEIOLATCH','PgIO'),
				'PAGELATCH','Pg'),
				'CXPACKET','CXP'),
				'THREADPOOL','ThrPool'),				--5
				'ASYNC_IO_COMPLETION', 'AsyncIOComp'),
				'ASYNC_NETWORK_IO', 'AsyncNetIO'),
				'BACKUPBUFFER','BkpBuf'),
				'BACKUPIO', 'BkpIO'),
				'BACKUPTHREAD', 'BkpThrd'),				--10
				'IO_COMPLETION', 'IOcomp'),
				'LOGBUFFER', 'LogBuf'),
				'RESOURCE_SEMAPHORE', 'RsrcSem'),
				'RESOURCE_SEMAPHORE_QUERY_COMPILE', 'RsrcSemQryComp'),
				'TRACEWRITE', 'TrcWri'),				--15
				'WRITE_COMPLETION', 'WriComp'),
				'WRITELOG', 'WriLog'),
				'PREEMPTIVE', 'PREm')									--18
		FROM sys.dm_os_wait_stats w
	) w
	WHERE NOT EXISTS (
		SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType dwt
		WHERE dwt.wait_type = w.wait_type
		AND dwt.wait_type_short = w.wait_type_short
	);
	*/

	RETURN 0;
END
GO