SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[CollectorMedFreq]
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

	FILE NAME: ServerEye.CollectorMedFreq.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.CollectorMedFreq

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs on a schedule (or initiated by a user via a viewer proc) and calls various sub-procs to gather miscellaneous 
		server-level DMV data. Collects data that we want captured somewhat frequently (by default every 5 minutes)

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

	DECLARE @DynSQL NVARCHAR(4000),
			@CurDBID INT,
			@CurDBName NVARCHAR(128),
			@ChiRhoDBName NVARCHAR(128);

	DECLARE @errorloc		NVARCHAR(100),
		@err__ErrorSeverity INT, 
		@err__ErrorState	INT, 
		@err__ErrorText		NVARCHAR(4000),
		@lv__nullstring		NVARCHAR(8),
		@lv__nullint		INT,
		@lv__nullsmallint	SMALLINT;

	SET @lv__nullstring = N'<nul5>';		--used the # 5 just to make it that much more unlikely that our "special value" would collide with a DMV value
	SET @lv__nullint = -929;				--ditto, used a strange/random number rather than -999, so there is even less of a chance of 
	SET @lv__nullsmallint = -929;			-- overlapping with some special system value

BEGIN TRY
	SET @ChiRhoDBName = DB_NAME();

	--DB and file stats.
	--First, update the DBID to Name mapping just to make sure these stats are tied to the correct database id/name pair
	SET @errorloc = N'CoreXR.UpdateDBMapping';
	EXEC CoreXR.UpdateDBMapping;

	SET @errorloc = N'LogSpace';
	IF OBJECT_ID('tempdb..#DBLogUsageStats') IS NOT NULL DROP TABLE #DBLogUsageStats;
	CREATE TABLE #DBLogUsageStats (
		[Database Name] NVARCHAR(128) NULL,
		[Log Size (MB)] DECIMAL(21,8) NULL,
		[Log Space Used Pct] DECIMAL(11,8) NULL,
		[Status] INT NULL
	);

	INSERT INTO #DBLogUsageStats
		EXEC ('DBCC SQLPERF(LOGSPACE)');

	SET @errorloc = N'Obtain DB stats';
	INSERT INTO [ServerEye].[DatabaseStats] (
		[UTCCaptureTime],
		[LocalCaptureTime],
		[database_id],
		[user_access_desc],
		[state_desc],
		[LogSizeMB],
		[LogPctUsed]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		d.database_id,
		d.user_access_desc,
		d.state_desc,
		[LogSizeMB] = t.[Log Size (MB)],
		[LogPctUsed] = t.[Log Space Used Pct]
	FROM sys.databases d
		LEFT OUTER JOIN #DBLogUsageStats t
			ON d.name = t.[Database Name];

	SET @errorloc = N'Loop DBFileStats';
	DECLARE iterateDBsCollectStats CURSOR FOR 
	SELECT dstat.database_id
	FROM ServerEye.DatabaseStats dstat
	WHERE dstat.UTCCaptureTime = @UTCCaptureTime
	AND dstat.user_access_desc = 'MULTI_USER'
	AND dstat.state_desc = 'ONLINE'
	ORDER BY dstat.database_id ASC;

	OPEN iterateDBsCollectStats;
	FETCH iterateDBsCollectStats INTO @CurDBID;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @CurDBName = DB_NAME(@CurDBID);

		SET @DynSQL = N'USE ' + QUOTENAME(@CurDBName) + N';
		INSERT INTO ' + QUOTENAME(@ChiRhoDBName) + '.[ServerEye].[DBFileStats](
			[UTCCaptureTime],
			[LocalCaptureTime],
			[database_id],
			[file_id],
			[name],
			[type_desc],
			[state_desc],
			[is_media_read_only],
			[is_read_only],
			[mf_size_pages],
			[df_size_pages],
			[pages_used],
			[DataSpaceName],
			[DataSpaceType],
			[DataSpaceIsDefault],
			[FGIsReadOnly]
		)
		SELECT 
			@UTCCaptureTime,
			@LocalCaptureTime,
			mf.database_id,
			mf.file_id,
			mf.name,
			mf.type_desc,
			mf.state_desc,
			mf.is_media_read_only,
			mf.is_read_only,
			[mf_size_pages] = mf.size,
			[df_size_pages] = df.size,
			[pages_used] = FILEPROPERTY(df.name, ''SpaceUsed''),
			[DataSpaceName] = dsp.name,
			[DataSpaceType] = dsp.type_desc,
			[DataSpaceIsDefault] = dsp.is_default,
			[FGIsReadOnly] = fg.is_read_only
		FROM sys.master_files mf
			left outer join sys.database_files df
				on mf.file_id = df.file_id
			left outer join sys.data_spaces dsp
				on mf.data_space_id = dsp.data_space_id
			left outer join sys.filegroups fg
				on dsp.data_space_id = fg.data_space_id
		WHERE mf.database_id = ' + CONVERT(NVARCHAR(20),@CurDBID) + '
		';

		EXEC sp_executesql @DynSQL, N'@UTCCaptureTime DATETIME, @LocalCaptureTime DATETIME', @UTCCaptureTime, @LocalCaptureTime;

		FETCH iterateDBsCollectStats INTO @CurDBID;
	END

	CLOSE iterateDBsCollectStats;
	DEALLOCATE iterateDBsCollectStats;


	--Get volume info as well
	SET @errorloc = N'Volume Stats';
	INSERT INTO [ServerEye].[dm_os_volume_stats](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimDBVolumeID],
		[total_bytes],
		[available_bytes]
	)
	SELECT
		@UTCCaptureTime,
		@LocalCaptureTime,
		dbv.DimDBVolumeID,
		ss.total_bytes,
		ss.available_bytes
	FROM (
		SELECT 
			volume_id,
			volume_mount_point,
			logical_volume_name,
			file_system_type,
			supports_compression,
			supports_alternate_streams,
			supports_sparse_files,
			is_read_only,
			is_compressed,
			total_bytes,
			available_bytes,
			rn = ROW_NUMBER() OVER (PARTITION BY volume_id, volume_mount_point, logical_volume_name, file_system_type,
										supports_compression, supports_alternate_streams, supports_sparse_files,
										is_read_only, is_compressed
									ORDER BY available_bytes ASC)
			--I've seen dups come back, apparently b/c available bytes was in the middle of changing,
			--hence the reason for not using DISTINCT logic here.
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
				[is_compressed] = ISNULL(vs.is_compressed,255),

				vs.total_bytes,
				vs.available_bytes
			FROM sys.master_files mf
				cross apply sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
		) ss_base
	) ss
		INNER JOIN ServerEye.DimDBVolume dbv
			ON ss.volume_id = dbv.volume_id
			AND ss.volume_mount_point = dbv.volume_mount_point
			AND ss.logical_volume_name = dbv.logical_volume_name
			AND ss.file_system_type = dbv.file_system_type
			AND ss.supports_compression = dbv.supports_compression
			AND ss.supports_alternate_streams = dbv.supports_alternate_streams
			AND ss.supports_sparse_files = dbv.supports_sparse_files
			AND ss.is_read_only = dbv.is_read_only
			AND ss.is_compressed = dbv.is_compressed
	WHERE ss.rn = 1;



	--We want to grab a profile of the connection/session/request attributes for user connections to this instance.
	IF OBJECT_ID('tempdb..#ConnProfileTemp1') IS NOT NULL DROP TABLE #ConnProfileTemp1;
	CREATE TABLE #ConnProfileTemp1(
		--attributes from sys.dm_exec_connections
		[net_transport]			[nvarchar](40) NOT NULL,
		[protocol_type]			[nvarchar](40) NOT NULL,
		[protocol_version]		[int] NOT NULL,
		[endpoint_id]			[int] NOT NULL,
		[encrypt_option]		[nvarchar](40) NOT NULL,
		[auth_scheme]			[nvarchar](40) NOT NULL,
		[node_affinity]			[smallint] NOT NULL,
		[net_packet_size]		[int] NOT NULL,
		[client_net_address]	[varchar](48) NOT NULL,
		[local_net_address]		[varchar](48) NOT NULL,
		[local_tcp_port]		[int] NOT NULL,

		--metrics from sys.dm_exec_connections
		[connect_time]			[datetime] NOT NULL,
		[num_reads]				[int] NULL,
		[num_writes]			[int] NULL,
		[last_read]				[datetime] NULL,
		[last_write]			[datetime] NULL,

		--attributes from sys.dm_exec_sessions
		[host_name]				[nvarchar](128) NOT NULL,
		[program_name]			[nvarchar](128) NOT NULL,
		[client_version]		[int] NOT NULL,
		[client_interface_name] [nvarchar](32) NOT NULL,
		[security_id]			[varbinary](85) NOT NULL,
		[login_name]			[nvarchar](128) NOT NULL,
		[nt_domain]				[nvarchar](128) NOT NULL,
		[nt_user_name]			[nvarchar](128) NOT NULL,
		[original_security_id]	[varbinary](85) NOT NULL,
		[original_login_name]	[nvarchar](128) NOT NULL,
		[group_id]				[int] NOT NULL,
		[session_database_id]	[smallint] NOT NULL,

		--metrics from dm_exec_sessions
		[login_time]			[datetime] NOT NULL,
		[last_request_start_time] [datetime] NOT NULL,
		[last_request_end_time] [datetime] NULL,
		[cpu_time]				[int] NULL,
		[reads]					[bigint] NULL,
		[writes]				[bigint] NULL,
		[logical_reads]			[bigint] NULL,

		--attributes from sys.dm_exec_requests
		[request_database_id]	[smallint] NOT NULL,
		[request_user_id]		[int] NOT NULL,

		--metrics from dm_exec_requests
		[start_time]			[datetime] NULL
	);

	SET @errorloc = N'#ConnProfileTemp1';
	INSERT INTO #ConnProfileTemp1 (
		--attributes from sys.dm_exec_connections
		[net_transport],
		[protocol_type],
		[protocol_version],
		[endpoint_id],
		[encrypt_option],
		[auth_scheme],
		[node_affinity],
		[net_packet_size],
		[client_net_address],
		[local_net_address],
		[local_tcp_port],

		--metrics from sys.dm_exec_connections
		[connect_time],
		[num_reads],
		[num_writes],
		[last_read],
		[last_write],

		--attributes from sys.dm_exec_sessions
		[host_name],
		[program_name],
		[client_version],
		[client_interface_name],
		[security_id],
		[login_name],
		[nt_domain],
		[nt_user_name],
		[original_security_id],
		[original_login_name],
		[group_id],
		[session_database_id],

		--metrics from dm_exec_sessions
		[login_time],
		[last_request_start_time],
		[last_request_end_time],
		[cpu_time],
		[reads],
		[writes],
		[logical_reads],

		--attributes from sys.dm_exec_requests
		[request_database_id],
		[request_user_id],

		--metrics from dm_exec_requests
		[start_time]
	)
	--All of the fields without null-wrappers were NOT NULL on a table definition that I SELECT INTO'd the below query
	SELECT
		[net_transport] = c.net_transport,	--not nullable
		[protocol_type] = ISNULL(c.protocol_type,@lv__nullstring),
		[protocol_version] = ISNULL(c.protocol_version,@lv__nullint),
		[endpoint_id] = ISNULL(c.endpoint_id,@lv__nullint),
		[encrypt_option] = c.encrypt_option,	--ditto
		[auth_scheme] = c.auth_scheme,		--
		[node_affinity] = c.node_affinity,	--
		[net_packet_size] = ISNULL(c.net_packet_size,@lv__nullint),
		[client_net_address] = ISNULL(c.client_net_address,@lv__nullstring),
		[local_net_address] = ISNULL(c.local_net_address,@lv__nullstring),
		[local_tcp_port] = ISNULL(c.local_tcp_port,@lv__nullint),

		[connect_time] = c.connect_time,
		[num_reads] = c.num_reads,
		[num_writes] = c.num_writes,
		[last_read] = c.last_read,
		[last_write] = c.last_write,
		
		[host_name] = ISNULL(s.host_name,@lv__nullstring),
		[program_name] = ISNULL(s.program_name,@lv__nullstring),
		[client_version] = ISNULL(s.client_version,@lv__nullint),
		[client_interface_name] = ISNULL(s.client_interface_name,@lv__nullstring),
		[security_id] =s.security_id,		--not nullable
		[login_name] = s.login_name,		--
		[nt_domain] = ISNULL(s.nt_domain,@lv__nullstring),
		[nt_user_name] = ISNULL(s.nt_user_name,@lv__nullstring),
		[original_security_id] = s.original_security_id,	--
		[original_login_name] = s.original_login_name,	--
		[group_id] = s.group_id,				--
		[session_database_id] = s.database_id,	--

		[login_time] = s.login_time,
		[last_request_start_time] = s.last_request_start_time,
		[last_request_end_time] = s.last_request_end_time,
		[cpu_time] = s.cpu_time,
		[reads] = s.reads,
		[writes] = s.writes,
		[logical_reads] = s.logical_reads,

		[request_database_id] = ISNULL(r.database_id, @lv__nullsmallint),
		[request_user_id] = ISNULL(r.user_id,@lv__nullint),

		[start_time] = r.start_time
	FROM sys.dm_exec_connections c
		INNER JOIN sys.dm_exec_sessions s
			ON c.session_id = s.session_id	--also join on c.most_recent_session_id
		LEFT OUTER JOIN sys.dm_exec_requests r
			ON c.session_id = r.session_id;

	SET @errorloc = N'DimUserProfileConn';
	INSERT INTO [ServerEye].[DimUserProfileConn](
		[net_transport],
		[protocol_type],
		[protocol_version],
		[endpoint_id],
		[encrypt_option],
		[auth_scheme],
		[node_affinity],
		[net_packet_size],
		[client_net_address],
		[local_net_address],
		[local_tcp_port],
		[TimeAdded],
		[TimeAddedUTC]
	)
	SELECT 
		[net_transport],
		[protocol_type],
		[protocol_version],
		[endpoint_id],
		[encrypt_option],
		[auth_scheme],
		[node_affinity],
		[net_packet_size],
		[client_net_address],
		[local_net_address],
		[local_tcp_port],
		GETDATE(),
		GETUTCDATE()
	FROM (
		SELECT DISTINCT 
			[net_transport],
			[protocol_type],
			[protocol_version],
			[endpoint_id],
			[encrypt_option],
			[auth_scheme],
			[node_affinity],
			[net_packet_size],
			[client_net_address],
			[local_net_address],
			[local_tcp_port]
		FROM #ConnProfileTemp1 t
	) ss
	WHERE NOT EXISTS (
		SELECT *
		FROM [ServerEye].[DimUserProfileConn] d
		WHERE ss.net_transport = d.net_transport
		AND ss.protocol_type = d.protocol_type
		AND ss.protocol_version = d.protocol_version
		AND ss.endpoint_id = d.endpoint_id
		AND ss.encrypt_option = d.encrypt_option
		AND ss.auth_scheme = d.auth_scheme
		AND ss.node_affinity = d.node_affinity
		AND ss.net_packet_size = d.net_packet_size
		AND ss.client_net_address = d.client_net_address
		AND ss.local_net_address = d.local_net_address
		AND ss.local_tcp_port = d.local_tcp_port
	);

	SET @errorloc = N'DimUserProfileProgram';
	INSERT INTO [ServerEye].[DimUserProfileProgram](
		[host_name],
		[program_name],
		[client_version],
		[client_interface_name],
		[TimeAdded],
		[TimeAddedUTC]
	)
	SELECT 
		[host_name],
		[program_name],
		[client_version],
		[client_interface_name],
		GETDATE(),
		GETUTCDATE()
	FROM (
		SELECT DISTINCT
			[host_name],
			[program_name],
			[client_version],
			[client_interface_name]
		FROM #ConnProfileTemp1 t
	) ss
	WHERE NOT EXISTS (
		SELECT * 
		FROM [ServerEye].[DimUserProfileProgram] d
		WHERE ss.host_name = d.host_name
		AND ss.program_name = d.program_name
		AND ss.client_version = d.client_version
		AND ss.client_interface_name = d.client_interface_name
	);

	SET @errorloc = N'DimUserProfileLogin';
	INSERT INTO [ServerEye].[DimUserProfileLogin](
		[security_id],--			[varbinary](85) NOT NULL,
		[login_name],
		[nt_domain],
		[nt_user_name],
		[original_security_id], --	[varbinary](85) NOT NULL,
		[original_login_name],
		[group_id],
		[session_database_id],
		[request_database_id],
		[request_user_id],
		[TimeAdded],
		[TimeAddedUTC]
	)
	SELECT 
		[security_id],
		[login_name],
		[nt_domain],
		[nt_user_name],
		[original_security_id],
		[original_login_name],
		[group_id],
		[session_database_id],
		[request_database_id],
		[request_user_id],
		GETDATE(),
		GETUTCDATE()
	FROM (
		SELECT DISTINCT
			[security_id],
			[login_name],
			[nt_domain],
			[nt_user_name],
			[original_security_id],
			[original_login_name],
			[group_id],
			[session_database_id],
			[request_database_id],
			[request_user_id]
		FROM #ConnProfileTemp1 t
	) ss
	WHERE NOT EXISTS (
		SELECT *
		FROM [ServerEye].[DimUserProfileLogin] d
		WHERE ss.security_id = d.security_id
		AND ss.login_name = d.login_name
		AND ss.nt_domain = d.nt_domain
		AND ss.nt_user_name = d.nt_user_name
		AND ss.original_security_id = d.original_security_id
		AND ss.original_login_name = d.original_login_name
		AND ss.group_id = d.group_id
		AND ss.session_database_id = d.session_database_id
		AND ss.request_database_id = d.request_database_id
		AND ss.request_user_id = d.request_user_id
	);

	
	SET @errorloc = N'Fact ConnectionProfile';
	INSERT INTO [ServerEye].[ConnectionProfile](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimUserProfileConnID],
		[DimUserProfileProgramID],
		[DimUserProfileLoginID],
		[NumRows],
		[conn__connect_time_min],
		[conn__connect_time_max],
		[conn__num_reads_sum],
		[conn__num_reads_max],
		[conn__num_writes_sum],
		[conn__num_writes_max],
		[conn__last_read_min],
		[conn__last_read_max],
		[conn__last_write_min],
		[conn__last_write_max],
		[sess__login_time_min],
		[sess__login_time_max],
		[sess__last_request_start_time_min],
		[sess__last_request_start_time_max],
		[sess__last_request_end_time_min],
		[sess__last_request_end_time_max],
		[sess__cpu_time_sum],
		[sess__cpu_time_max],
		[sess__reads_sum],
		[sess__reads_max],
		[sess__writes_sum],
		[sess__writes_max],
		[sess__logical_reads_sum],
		[sess__logical_reads_max],
		[rqst__start_time_min],
		[rqst__start_time_max]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		dupc.DimUserProfileConnID,
		dupp.DimUserProfileProgramID,
		dupl.DimUserProfileLoginID,

		[NumRows] = COUNT(*),
		[conn__connect_time_min] = MIN(ss.connect_time),
		[conn__connect_time_max] = MAX(ss.connect_time),
		[conn__num_reads_sum] = SUM(ss.num_reads),
		[conn__num_reads_max] = MAX(ss.num_reads),
		[conn__num_writes_sum] = SUM(ss.num_writes),
		[conn__num_writes_max] = MAX(ss.num_writes),
		[conn__last_read_min] = MIN(ss.last_read),
		[conn__last_read_max] = MAX(ss.last_read),
		[conn__last_write_min] = MIN(ss.last_write),
		[conn__last_write_max] = MAX(ss.last_write),
		[sess__login_time_min] = MIN(ss.login_time),
		[sess__login_time_max] = MAX(ss.login_time),
		[sess__last_request_start_time_min] = MIN(ss.last_request_start_time),
		[sess__last_request_start_time_max] = MAX(ss.last_request_start_time),
		[sess__last_request_end_time_min] = MIN(ss.last_request_end_time),
		[sess__last_request_end_time_max] = MAX(ss.last_request_end_time),
		[sess__cpu_time_sum] = SUM(ss.cpu_time),
		[sess__cpu_time_max] = MAX(ss.cpu_time),
		[sess__reads_sum] = SUM(ss.reads),
		[sess__reads_max] = MAX(ss.reads),
		[sess__writes_sum] = SUM(ss.writes),
		[sess__writes_max] = MAX(ss.writes),
		[sess__logical_reads_sum] = SUM(ss.logical_reads),
		[sess__logical_reads_max] = MAX(ss.logical_reads),
		[rqst__start_time_min] = MIN(ss.start_time),
		[rqst__start_time_max] = MAX(ss.start_time)
	FROM 
		ServerEye.DimUserProfileConn dupc
			INNER hash JOIN 
	
			ServerEye.DimUserProfileProgram dupp
				INNER hash JOIN

				ServerEye.DimUserProfileLogin dupl
					INNER hash JOIN

					(
					SELECT 
						t.net_transport,
						t.protocol_type,
						t.protocol_version,
						t.endpoint_id,
						t.encrypt_option,
						t.auth_scheme,
						t.node_affinity,
						t.net_packet_size,
						t.client_net_address,
						t.local_net_address,
						t.local_tcp_port,

						t.connect_time,
						t.num_reads,
						t.num_writes,
						t.last_read,
						t.last_write,

						t.host_name,
						t.program_name,
						t.client_version,
						t.client_interface_name,
						t.security_id,
						t.login_name,
						t.nt_domain,
						t.nt_user_name,
						t.original_security_id,
						t.original_login_name,
						t.group_id,
						t.session_database_id,

						t.login_time,
						t.last_request_start_time,
						t.last_request_end_time,
						t.cpu_time,
						t.reads,
						t.writes,
						t.logical_reads,

						t.request_database_id,
						t.request_user_id,

						t.start_time
					FROM #ConnProfileTemp1 t
				) ss

				ON ss.security_id = dupl.security_id
				AND ss.login_name = dupl.login_name
				AND ss.nt_domain = dupl.nt_domain
				AND ss.nt_user_name = dupl.nt_user_name
				AND ss.original_security_id = dupl.original_security_id
				AND ss.original_login_name = dupl.original_login_name
				AND ss.group_id = dupl.group_id
				AND ss.session_database_id = dupl.session_database_id
				AND ss.request_database_id = dupl.request_database_id
				AND ss.request_user_id = dupl.request_user_id

			ON ss.host_name = dupp.host_name
			AND ss.program_name = dupp.program_name
			AND ss.client_version = dupp.client_version
			AND ss.client_interface_name = dupp.client_interface_name

		ON ss.net_transport = dupc.net_transport
		AND ss.protocol_type = dupc.protocol_type
		AND ss.protocol_version = dupc.protocol_version
		AND ss.endpoint_id = dupc.endpoint_id
		AND ss.encrypt_option = dupc.encrypt_option
		AND ss.auth_scheme = dupc.auth_scheme
		AND ss.node_affinity = dupc.node_affinity
		AND ss.net_packet_size = dupc.net_packet_size
		AND ss.client_net_address = dupc.client_net_address
		AND ss.local_net_address = dupc.local_net_address
		AND ss.local_tcp_port = dupc.local_tcp_port
	GROUP BY dupc.DimUserProfileConnID,
		dupp.DimUserProfileProgramID,
		dupl.DimUserProfileLoginID
	OPTION(FORCE ORDER);


	--dm_os_memory_clerks
	SET @errorloc = N'dm_os_memory_clerks';
	INSERT INTO [ServerEye].[dm_os_memory_clerks](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimMemoryTrackerID],
		[memory_node_id],
		[NumUniqueClerks],
		[sum_pages_kb],
		[sum_virtual_memory_reserved_kb],
		[sum_virtual_memory_committed_kb],
		[sum_awe_allocated_kb],
		[sum_shared_memory_reserved_kb],
		[sum_shared_memory_committed_kb]
	)
	SELECT 
		ss2.UTCCaptureTime,
		ss2.LocalCaptureTime,
		ss2.DimMemoryTrackerID,
		ss2.memory_node_id,
		ss2.NumRows,
		ss2.sum_pages_kb,
		ss2.sum_virtual_memory_reserved_kb,
		ss2.sum_virtual_memory_committed_kb,
		ss2.sum_awe_allocated_kb,
		ss2.sum_shared_memory_reserved_kb,
		ss2.sum_shared_memory_committed_kb
	FROM (
		SELECT 
			[UTCCaptureTime] = @UTCCaptureTime,
			[LocalCaptureTime] = @LocalCaptureTime,
			mem.DimMemoryTrackerID,
			ss.memory_node_id,
			NumRows = COUNT(*),
			sum_pages_kb = SUM(ss.pages_kb),
			sum_virtual_memory_reserved_kb = SUM(ss.virtual_memory_reserved_kb),
			sum_virtual_memory_committed_kb = SUM(ss.virtual_memory_committed_kb),
			sum_awe_allocated_kb = SUM(ss.awe_allocated_kb),
			sum_shared_memory_reserved_kb = SUM(ss.shared_memory_reserved_kb),
			sum_shared_memory_committed_kb = SUM(ss.shared_memory_committed_kb)
		FROM (
			SELECT 
				[type] = t.type,
				[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
							WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
								THEN 'ObjPerm - <dbname>'
							WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
								THEN 'ACRUserStore'
							WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
								THEN 'SecCtxtACRUserStore'
							ELSE t.name END,
				t.memory_node_id,
				t.pages_kb,
				t.virtual_memory_reserved_kb,
				t.virtual_memory_committed_kb,
				t.awe_allocated_kb,
				t.shared_memory_reserved_kb,
				t.shared_memory_committed_kb
			FROM sys.dm_os_memory_clerks t
		) ss
			INNER JOIN ServerEye.DimMemoryTracker mem
				ON mem.type = ss.type
				AND mem.name = ss.name
		WHERE mem.IsInClerks = 1
		GROUP BY mem.DimMemoryTrackerID,
			ss.memory_node_id
	) ss2
	WHERE ISNULL(ss2.sum_pages_kb,0) > 0
	OR ISNULL(ss2.sum_virtual_memory_reserved_kb,0) > 0
	OR ISNULL(ss2.sum_virtual_memory_committed_kb,0) > 0
	OR ISNULL(ss2.sum_awe_allocated_kb,0) > 0
	OR ISNULL(ss2.sum_shared_memory_reserved_kb,0) > 0
	OR ISNULL(ss2.sum_shared_memory_committed_kb,0) > 0;

	SET @errorloc = N'dm_os_memory_cache_clock_hands';
	INSERT INTO [ServerEye].[dm_os_memory_cache_clock_hands](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimMemoryTrackerID],
		[memory_node_id],
		[clock_hand],
		[NumUniqueRows],
		[sum_status_is_suspended],
		[sum_status_is_running],
		[sum_rounds_count],
		[sum_removed_all_rounds_count],
		[sum_updated_last_round_count],
		[sum_removed_last_round_count]
	)
	SELECT 
		ss2.UTCCaptureTime,
		ss2.LocalCaptureTime,
		ss2.DimMemoryTrackerID,
		ss2.memory_node_id,
		ss2.clock_hand,
		ss2.NumRows,
		ss2.sum_status_is_suspended,
		ss2.sum_status_is_running,
		ss2.sum_rounds_count,
		ss2.sum_removed_all_rounds_count,
		ss2.sum_updated_last_round_count,
		ss2.sum_removed_last_round_count
	FROM (
		SELECT 
			[UTCCaptureTime] = @UTCCaptureTime,
			[LocalCaptureTime] = @LocalCaptureTime,
			mem.DimMemoryTrackerID,
			ss.memory_node_id,
			ss.clock_hand,
			NumRows = COUNT(*),
			sum_status_is_suspended = SUM(ss.status_is_suspended),
			sum_status_is_running = SUM(ss.status_is_running),
			sum_rounds_count = SUM(ss.rounds_count),
			sum_removed_all_rounds_count = SUM(ss.removed_all_rounds_count),
			sum_updated_last_round_count = SUM(ss.updated_last_round_count),
			sum_removed_last_round_count = SUM(ss.removed_last_round_count)
		FROM (
			SELECT 
				[type] = t.type,
				[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
							WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
								THEN 'ObjPerm - <dbname>'
							WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
								THEN 'ACRUserStore'
							WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
								THEN 'SecCtxtACRUserStore'
							ELSE t.name END,
				cl.memory_node_id,
				t.clock_hand,
				[status_is_suspended] = CASE WHEN t.clock_status = 'SUSPENDED' THEN 1 ELSE 0 END,
				[status_is_running] = CASE WHEN t.clock_status = 'RUNNING' THEN 1 ELSE 0 END,
				t.rounds_count,
				t.removed_all_rounds_count,
				t.updated_last_round_count,
				t.removed_last_round_count
			FROM sys.dm_os_memory_cache_clock_hands t	--all of these appear to be in memclerks
				INNER JOIN sys.dm_os_memory_clerks cl
					ON t.cache_address = cl.memory_clerk_address
		) ss
			INNER JOIN ServerEye.DimMemoryTracker mem
				ON mem.type = ss.type
				AND mem.name = ss.name
		WHERE mem.IsInClockHands = 1
		GROUP BY mem.DimMemoryTrackerID,
			ss.memory_node_id,
			ss.clock_hand
	) ss2
	WHERE ISNULL(ss2.sum_rounds_count,0) > 0
	OR ISNULL(ss2.sum_removed_all_rounds_count,0) > 0
	OR ISNULL(ss2.sum_updated_last_round_count,0) > 0
	OR ISNULL(ss2.sum_removed_last_round_count,0) > 0;

	SET @errorloc = N'dm_os_memory_cache_counters';
	INSERT INTO [ServerEye].[dm_os_memory_cache_counters](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimMemoryTrackerID],
		[memory_node_id],
		[NumUniqueRows],
		[sum_pages_kb],
		[sum_pages_in_use_kb],
		[sum_entries_count],
		[sum_entries_in_use_count]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		mem.DimMemoryTrackerID,
		ss.memory_node_id,
		NumRows = COUNT(*),
		sum_pages_kb = SUM(ss.pages_kb),
		sum_pages_in_use_kb = SUM(ss.pages_in_use_kb),
		sum_entries_count = SUM(ss.entries_count),
		sum_entries_in_use_count = SUM(ss.entries_in_use_count)
	FROM (
		SELECT 
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END,
			cl.memory_node_id,
			t.pages_kb,
			t.pages_in_use_kb,
			t.entries_count,
			t.entries_in_use_count
		FROM sys.dm_os_memory_cache_counters t
			INNER JOIN sys.dm_os_memory_clerks cl
				ON t.cache_address = cl.memory_clerk_address
	) ss
		INNER JOIN ServerEye.DimMemoryTracker mem
			ON mem.type = ss.type
			AND mem.name = ss.name
	WHERE mem.IsInCacheCounters = 1
	GROUP BY mem.DimMemoryTrackerID,
		ss.memory_node_id;


	SET @errorloc = N'dm_os_memory_cache_hash_tables';
	INSERT INTO [ServerEye].[dm_os_memory_cache_hash_tables](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimMemoryTrackerID],
		[memory_node_id],
		[table_level],
		[NumUniqueRows],
		[sum_buckets_count],
		[sum_buckets_in_use_count],
		[min_buckets_min_length],
		[max_buckets_max_length],
		[avg_buckets_avg_length],
		[max_buckets_max_length_ever],
		[sum_hits_count],
		[sum_misses_count],
		[avg_buckets_avg_scan_hit_length],
		[avg_buckets_avg_scan_miss_length]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		mem.DimMemoryTrackerID,
		ss.memory_node_id,
		ss.table_level,
		[NumRows] = COUNT(*),
		[sum_buckets_count] = SUM(ss.buckets_count),
		[sum_buckets_in_use_count] = SUM(ss.buckets_in_use_count),
		[min_buckets_min_length] = MIN(ss.buckets_min_length),
		[max_buckets_max_length] = MAX(ss.buckets_max_length),
		[avg_buckets_avg_length] = CONVERT(DECIMAL(11,2),AVG(ss.buckets_avg_length*1.)),
		[max_buckets_max_length_ever] = MAX(ss.buckets_max_length_ever),
		[sum_hits_count] = SUM(ss.hits_count),
		[sum_misses_count] = SUM(ss.misses_count),
		[avg_buckets_avg_scan_hit_length] = CONVERT(DECIMAL(11,2),AVG(ss.buckets_avg_scan_hit_length*1.)),
		[avg_buckets_avg_scan_miss_length] = CONVERT(DECIMAL(11,2),AVG(ss.buckets_avg_scan_miss_length*1.))
	FROM (
		SELECT 
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END,
			cl.memory_node_id,
			t.table_level,
			t.buckets_count,
			t.buckets_in_use_count,
			t.buckets_min_length,
			t.buckets_max_length,
			t.buckets_avg_length,
			t.buckets_max_length_ever,
			t.hits_count,
			t.misses_count,
			t.buckets_avg_scan_hit_length,
			t.buckets_avg_scan_miss_length
		FROM sys.dm_os_memory_cache_hash_tables t	--all of these appear to be in mem clerks
			INNER JOIN sys.dm_os_memory_clerks cl
				ON t.cache_address = cl.memory_clerk_address
	) ss
		INNER JOIN ServerEye.DimMemoryTracker mem
			ON mem.type = ss.type
			AND mem.name = ss.name
	WHERE mem.IsInCacheHashTables = 1
	GROUP BY mem.DimMemoryTrackerID,
		ss.memory_node_id,
		ss.table_level;


	SET @errorloc = N'dm_os_memory_pools';
	INSERT INTO [ServerEye].[dm_os_memory_pools](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimMemoryTrackerID],
		[memory_node_id],
		[NumUniqueRows],
		[sum_max_free_entries_count],
		[sum_free_entries_count],
		[sum_removed_in_all_rounds_count]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		mem.DimMemoryTrackerID,
		ss.memory_node_id,
		[NumUniqueRows] = COUNT(*),
		[sum_max_free_entries_count] = SUM(ss.max_free_entries_count),
		[sum_free_entries_count] = SUM(ss.free_entries_count),
		[sum_removed_in_all_rounds_count] = SUM(ss.removed_in_all_rounds_count)
	FROM (
		SELECT 
			[type] = t.type,
			[name] = CASE WHEN t.type = 'USERSTORE_DBMETADATA' THEN '<dbname>' 
						WHEN t.type = 'USERSTORE_OBJPERM' AND t.name LIKE 'ObjPerm%'
							THEN 'ObjPerm - <dbname>'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'ACRUserStore%'
							THEN 'ACRUserStore'
						WHEN t.type = 'USERSTORE_TOKENPERM' AND t.name LIKE 'SecCtxtACRUserStore%'
							THEN 'SecCtxtACRUserStore'
						ELSE t.name END,
			cl.memory_node_id,
			t.max_free_entries_count,
			t.free_entries_count,
			t.removed_in_all_rounds_count
		FROM sys.dm_os_memory_pools t
			INNER JOIN sys.dm_os_memory_clerks cl
				ON t.memory_pool_address = cl.memory_clerk_address
	) ss
		INNER JOIN ServerEye.DimMemoryTracker mem
			ON mem.type = ss.type
			AND mem.name = ss.name
	WHERE mem.IsInPools = 1
	GROUP BY mem.DimMemoryTrackerID,
		ss.memory_node_id;

	SET @errorloc = N'dm_os_hosts';
	INSERT INTO [ServerEye].[dm_os_hosts](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[DimMemoryTrackerID],
		[memory_node_id],
		[enqueued_tasks_count],
		[active_tasks_count],
		[completed_ios_count],
		[completed_ios_in_bytes],
		[active_ios_count]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		mem.DimMemoryTrackerID,
		cl.memory_node_id,
		t.enqueued_tasks_count,
		t.active_tasks_count,
		t.completed_ios_count,
		t.completed_ios_in_bytes,
		t.active_ios_count
	FROM sys.dm_os_hosts t
		INNER JOIN sys.dm_os_memory_clerks cl
			ON t.default_memory_clerk_address = cl.memory_clerk_address
		INNER JOIN ServerEye.DimMemoryTracker mem
			ON mem.type = t.type
			AND mem.name = t.name
	WHERE mem.IsInHosts = 1;


	SET @errorloc = N'dm_os_memory_brokers';
	INSERT INTO [ServerEye].[dm_os_memory_brokers](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[pool_id],
		[memory_broker_type],
		[allocations_kb],
		[allocations_kb_per_sec],
		[predicted_allocations_kb],
		[target_allocations_kb],
		[future_allocations_kb],
		[overall_limit_kb],
		[last_notification]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[pool_id],
		[memory_broker_type],
		[allocations_kb],
		[allocations_kb_per_sec],
		[predicted_allocations_kb],
		[target_allocations_kb],
		[future_allocations_kb],
		[overall_limit_kb],
		[last_notification]
	FROM sys.dm_os_memory_brokers;


	SET @errorloc = N'dm_exec_query_resource_semaphores';
	INSERT INTO [ServerEye].[dm_exec_query_resource_semaphores](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[pool_id],
		[resource_semaphore_id],
		[target_memory_kb],
		[max_target_memory_kb],
		[total_memory_kb],
		[available_memory_kb],
		[granted_memory_kb],
		[used_memory_kb],
		[grantee_count],
		[waiter_count],
		[timeout_error_count],
		[forced_grant_count],

		[NumGrantRows],
		[sum_dop],
		[earliest_request_time],
		[longest_granted_delay_sec],
		[sum_requested_memory_kb],
		[max_requested_memory_kb],
		[sum_required_memory_kb],
		[max_required_memory_kb],
		[sum_max_used_memory_kb],
		[max_max_used_memory_kb],
		[sum_wait_time_ms],
		[max_wait_time_ms],
		[num_is_small]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		ISNULL(s.[pool_id],-1),				--technically a null-able field though I don't expect any
		ISNULL(s.[resource_semaphore_id],-1),	--ditto
		[target_memory_kb],
		[max_target_memory_kb],
		[total_memory_kb],
		[available_memory_kb],
		[granted_memory_kb],
		[used_memory_kb],
		[grantee_count],
		[waiter_count],
		[timeout_error_count],
		[forced_grant_count],

		[NumGrantRows] = mg.NumRows,
		[sum_dop] = mg.sum_dop,
		[earliest_request_time] = mg.earliest_request_time,
		[longest_granted_delay_sec] = mg.longest_granted_delay_sec,
		[sum_requested_memory_kb] = mg.sum_requested_memory_kb,
		[max_requested_memory_kb] = mg.max_requested_memory_kb,
		[sum_required_memory_kb] = mg.sum_required_memory_kb,
		[max_required_memory_kb] = mg.max_required_memory_kb,
		[sum_max_used_memory_kb] = mg.sum_max_used_memory_kb,
		[max_max_used_memory_kb] = mg.max_max_used_memory_kb,
		[sum_wait_time_ms] = mg.sum_wait_time_ms,
		[max_wait_time_ms] = mg.max_wait_time_ms,
		[num_is_small] = mg.num_is_small

	FROM dm_exec_query_resource_semaphores s
		LEFT OUTER JOIN (
			SELECT 
				m.pool_id,
				m.resource_semaphore_id,
				NumRows = COUNT(*),
				sum_dop = SUM(m.dop),
				earliest_request_time = MIN(m.request_time),
				longest_granted_delay_sec = MAX(DATEDIFF(SECOND, m.request_time, m.grant_time)),
				sum_requested_memory_kb = SUM(m.requested_memory_kb),
				max_requested_memory_kb = MAX(m.requested_memory_kb),
				sum_required_memory_kb = SUM(m.required_memory_kb),
				max_required_memory_kb = MAX(m.required_memory_kb),
				sum_max_used_memory_kb = SUM(m.max_used_memory_kb),
				max_max_used_memory_kb = MAX(m.max_used_memory_kb),
				sum_wait_time_ms = SUM(m.wait_time_ms),
				max_wait_time_ms = MAX(m.wait_time_ms),

				num_is_small = SUM(CONVERT(INT,m.is_small))
			FROM sys.dm_exec_query_memory_grants m
			GROUP BY m.pool_id, m.resource_semaphore_id
		) mg
			ON s.pool_id = mg.pool_id
			AND s.resource_semaphore_id = mg.resource_semaphore_id;



	SET @errorloc = N'dm_resource_governor_resource_pools';
	INSERT INTO [ServerEye].[dm_resource_governor_resource_pools](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[pool_id],
		[name],
		[statistics_start_time],
		[total_cpu_usage_ms],
		[cache_memory_kb],
		[compile_memory_kb],
		[used_memgrant_kb],
		[total_memgrant_count],
		[total_memgrant_timeout_count],
		[active_memgrant_count],
		[active_memgrant_kb],
		[memgrant_waiter_count],
		[max_memory_kb],
		[used_memory_kb],
		[target_memory_kb],
		[out_of_memory_count],
		[min_cpu_percent],
		[max_cpu_percent],
		[min_memory_percent],
		[max_memory_percent],
		[cap_cpu_percent],
		[min_iops_per_volume],
		[max_iops_per_volume],
		[read_io_queued_total],
		[read_io_issued_total],
		[read_io_completed_total],
		[read_io_throttled_total],
		[read_bytes_total],
		[read_io_stall_total_ms],
		[read_io_stall_queued_ms],
		[write_io_queued_total],
		[write_io_issued_total],
		[write_io_completed_total],
		[write_io_throttled_total],
		[write_bytes_total],
		[write_io_stall_total_ms],
		[write_io_stall_queued_ms],
		[io_issue_violations_total],
		[io_issue_delay_total_ms]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[pool_id],
		[name],
		[statistics_start_time],
		[total_cpu_usage_ms],
		[cache_memory_kb],
		[compile_memory_kb],
		[used_memgrant_kb],
		[total_memgrant_count],
		[total_memgrant_timeout_count],
		[active_memgrant_count],
		[active_memgrant_kb],
		[memgrant_waiter_count],
		[max_memory_kb],
		[used_memory_kb],
		[target_memory_kb],
		[out_of_memory_count],
		[min_cpu_percent],
		[max_cpu_percent],
		[min_memory_percent],
		[max_memory_percent],
		[cap_cpu_percent],
		[min_iops_per_volume],
		[max_iops_per_volume],
		[read_io_queued_total],
		[read_io_issued_total],
		[read_io_completed_total],
		[read_io_throttled_total],
		[read_bytes_total],
		[read_io_stall_total_ms],
		[read_io_stall_queued_ms],
		[write_io_queued_total],
		[write_io_issued_total],
		[write_io_completed_total],
		[write_io_throttled_total],
		[write_bytes_total],
		[write_io_stall_total_ms],
		[write_io_stall_queued_ms],
		[io_issue_violations_total],
		[io_issue_delay_total_ms]
	FROM sys.dm_resource_governor_resource_pools p;


	SET @errorloc = N'dm_resource_governor_resource_pool_volumes';
	INSERT INTO [ServerEye].[dm_resource_governor_resource_pool_volumes](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[pool_id],
		[volume_name],
		[read_io_queued_total],
		[read_io_issued_total],
		[read_io_completed_total],
		[read_io_throttled_total],
		[read_bytes_total],
		[read_io_stall_total_ms],
		[read_io_stall_queued_ms],
		[write_io_queued_total],
		[write_io_issued_total],
		[write_io_completed_total],
		[write_io_throttled_total],
		[write_bytes_total],
		[write_io_stall_total_ms],
		[write_io_stall_queued_ms],
		[io_issue_violations_total],
		[io_issue_delay_total_ms]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[pool_id],
		[volume_name],
		[read_io_queued_total],
		[read_io_issued_total],
		[read_io_completed_total],
		[read_io_throttled_total],
		[read_bytes_total],
		[read_io_stall_total_ms],
		[read_io_stall_queued_ms],
		[write_io_queued_total],
		[write_io_issued_total],
		[write_io_completed_total],
		[write_io_throttled_total],
		[write_bytes_total],
		[write_io_stall_total_ms],
		[write_io_stall_queued_ms],
		[io_issue_violations_total],
		[io_issue_delay_total_ms]
	FROM sys.dm_resource_governor_resource_pool_volumes;

	SET @errorloc = N'dm_resource_governor_workload_groups';
	INSERT INTO [ServerEye].[dm_resource_governor_workload_groups](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[group_id],
		[name],
		[pool_id],
		[statistics_start_time],
		[total_request_count],
		[total_queued_request_count],
		[active_request_count],
		[queued_request_count],
		[total_cpu_limit_violation_count],
		[total_cpu_usage_ms],
		[max_request_cpu_time_ms],
		[blocked_task_count],
		[total_lock_wait_count],
		[total_lock_wait_time_ms],
		[total_query_optimization_count],
		[total_suboptimal_plan_generation_count],
		[total_reduced_memgrant_count],
		[max_request_grant_memory_kb],
		[active_parallel_thread_count],
		[importance],
		[request_max_memory_grant_percent],
		[request_max_cpu_time_sec],
		[request_memory_grant_timeout_sec],
		[group_max_requests],
		[max_dop],
		[effective_max_dop]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[group_id],
		[name],
		[pool_id],
		[statistics_start_time],
		[total_request_count],
		[total_queued_request_count],
		[active_request_count],
		[queued_request_count],
		[total_cpu_limit_violation_count],
		[total_cpu_usage_ms],
		[max_request_cpu_time_ms],
		[blocked_task_count],
		[total_lock_wait_count],
		[total_lock_wait_time_ms],
		[total_query_optimization_count],
		[total_suboptimal_plan_generation_count],
		[total_reduced_memgrant_count],
		[max_request_grant_memory_kb],
		[active_parallel_thread_count],
		[importance],
		[request_max_memory_grant_percent],
		[request_max_cpu_time_sec],
		[request_memory_grant_timeout_sec],
		[group_max_requests],
		[max_dop],
		[effective_max_dop]
	FROM dm_resource_governor_workload_groups;

	SET @errorloc = N'sys.traces';
	INSERT INTO [ServerEye].[systraces](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[id],
		[status],
		[path],
		[max_size],
		[stop_time],
		[max_files],
		[is_rowset],
		[is_rollover],
		[is_shutdown],
		[is_default],
		[buffer_count],
		[buffer_size],
		[file_position],
		[reader_spid],
		[start_time],
		[last_event_time],
		[event_count],
		[dropped_event_count]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[id],
		[status],
		[path],
		[max_size],
		[stop_time],
		[max_files],
		[is_rowset],
		[is_rollover],
		[is_shutdown],
		[is_default],
		[buffer_count],
		[buffer_size],
		[file_position],
		[reader_spid],
		[start_time],
		[last_event_time],
		[event_count],
		[dropped_event_count]
	FROM sys.traces;

	SET @errorloc = N'sys.traces';
	INSERT INTO [ServerEye].[dm_xe_sessions](
		[UTCCaptureTime],
		[LocalCaptureTime],
		[address],
		[name],
		[pending_buffers],
		[total_regular_buffers],
		[regular_buffer_size],
		[total_large_buffers],
		[large_buffer_size],
		[total_buffer_size],
		[buffer_policy_flags],
		[buffer_policy_desc],
		[flags],
		[flag_desc],
		[dropped_event_count],
		[dropped_buffer_count],
		[blocked_event_fire_time],
		[create_time],
		[largest_event_dropped_size],
		[session_source]
	)
	SELECT 
		@UTCCaptureTime,
		@LocalCaptureTime,
		[address],
		[name],
		[pending_buffers],
		[total_regular_buffers],
		[regular_buffer_size],
		[total_large_buffers],
		[large_buffer_size],
		[total_buffer_size],
		[buffer_policy_flags],
		[buffer_policy_desc],
		[flags],
		[flag_desc],
		[dropped_event_count],
		[dropped_buffer_count],
		[blocked_event_fire_time],
		[create_time],
		[largest_event_dropped_size],
		[session_source]
	FROM sys.dm_xe_sessions s;


	SET @errorloc = 'Med-Freq Perfmon';
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
	WHERE dpc.CounterFrequency = 2		--Med-freq code
	OPTION(FORCE ORDER);

	RETURN 0;
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