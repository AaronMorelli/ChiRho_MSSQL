--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-sessions-transact-sql
--NOTE: "In SQL Server 2022 (16.x) and later versions, requires VIEW SERVER PERFORMANCE STATE permission on the server."

--WARNING: the page above says that the cardinality relationship between dm_exec_sessions and dm_exec_connections is "one-to-zero or one-to-many"
--So multiple connections can use the same session? Is that a problem for me? I don't think so, at first glance.

--NOTE: "In [Azure] SQL Database, requires VIEW DATABASE STATE to see all connections to the current database. 
--VIEW DATABASE STATE can't be granted in the master database."

--GOOD TO KNOW, BUT I DO NOT THINK IT CAUSES ME SIGNIFICANT PROBLEMS: "When the [common criteria compliance enabled] server configuration option 
--is enabled, logon statistics are displayed in the following columns.  last_successful_logon, last_unsuccessful_logon, unsuccessful_logons
--If this option isn't enabled, these columns return null values. 
--https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/common-criteria-compliance-enabled-server-configuration-option?view=sql-server-ver16

--NOTE: The admin connections on Azure SQL Database see one row per authenticated session. The sa sessions that appear in the resultset, 
--don't have any effect on the user quota for sessions. The non-admin connections only see information related to their database user sessions.


SELECT
--TODO: I do not think I obtained all of the session fields, even for the ones that existed when I originally wrote this tool. Need to do a review and determine
--which fields are worth adding.
    session_id	--smallint	Not nullable.
        --Identifies the session associated with each active primary connection.
    ,login_time	--datetime	Not nullable.
        --Time when session was established. Sessions that have not completely logged in at the time this DMV is queried, are shown with a login time of 1900-01-01.
    ,host_name	--nvarchar(128)  Nullable	
        --Name of the client workstation that is specific to a session. The value is NULL for internal sessions.
        --Security note: The client application provides the workstation name and can provide inaccurate data. Do not rely on HOST_NAME as a security feature.
    ,program_name	        --nvarchar(128)  Nullable  	Name of client program that initiated the session. The value is NULL for internal sessions.
    ,host_process_id	    --int  Nullable 	Process ID of the client program that initiated the session. The value is NULL for internal sessions.
    ,client_version	        --int  Nullable 	TDS protocol version of the interface that is used by the client to connect to the server. The value is NULL for internal sessions.
    ,client_interface_name	--nvarchar(32)	Nullable.  Name of library/driver being used by the client to communicate with the server. The value is NULL for internal sessions.
    ,security_id	--varbinary(85)  Not nullable.	Windows security ID associated with the login.
    ,login_name	    --nvarchar(128)  Not nullable.  	
        --SQL Server login name under which the session is currently executing. 
        --For the original login name that created the session, see original_login_name. Can be a SQL Server authenticated login name or a Windows authenticated domain user name. 
    ,nt_domain	    --nvarchar(128)  Nullable.	
        -- Windows domain for the client if the session is using Windows Authentication or a trusted connection. This value is NULL for internal sessions and non-domain users.
    ,nt_user_name	--nvarchar(128)  Nullable.	
        -- Windows user name for the client if the session is using Windows Authentication or a trusted connection. This value is NULL for internal sessions and non-domain users.
    ,status	        --nvarchar(30)  Not nullable.  
        --	Status of the session. Possible values:
                --Running - Currently running one or more requests
                --Sleeping - Currently running no requests
                --Dormant - Session was reset because of connection pooling and is now in prelogin state.
                --Preconnect - Session is in the Resource Governor classifier.
    ,context_info	            --varbinary(128)  Nullable. 	CONTEXT_INFO value for the session. The context information is set by the user by using the SET CONTEXT_INFO statement
    ,cpu_time	                --int	Not nullable.      CPU time, in milliseconds, used by this session.
    ,memory_usage	            --int	Not nullable.      Number of 8-KB pages of memory used by this session.
    ,total_scheduled_time	    --int	Not nullable.      Total time, in milliseconds, for which the session (requests within) were scheduled for execution.
    ,total_elapsed_time	        --int	Not nullable.      Time, in milliseconds, since the session was established.
    ,endpoint_id	            --int	Not nullable.      ID of the endpoint associated with the session.
    ,last_request_start_time	--datetime	Not nullable.  Time at which the last request on the session began. This time includes the currently executing request.
    ,last_request_end_time	    --datetime	Nullable.      Time of the last completion of a request on the session.
    ,reads	                    --bigint	Not nullable.  Number of reads performed, by requests in this session, during this session.
    ,writes	                    --bigint	Not nullable.  Number of writes performed, by requests in this session, during this session.
    ,logical_reads	            --bigint	Not nullable.  Number of logical reads performed, by requests in this session, during this session.
    ,is_user_process	        --bit	Not nullable.      0 if the session is a system session. Otherwise, it's 1. 
    ,text_size              	--int	Not nullable.      TEXTSIZE setting for the session.
    ,language	                --nvarchar(128)	Nullable.  LANGUAGE setting for the session.
    ,date_format	            --nvarchar(3)  Nullable.   DATEFORMAT setting for the session.
    ,date_first	                --smallint	Not nullable.  DATEFIRST setting for the session.
    ,quoted_identifier	        --bit	Not nullable.   QUOTED_IDENTIFIER setting for the session.
    ,arithabort	                --bit	Not nullable.   ARITHABORT setting for the session.
    ,ansi_null_dflt_on	        --bit	Not nullable.   ANSI_NULL_DFLT_ON setting for the session.
    ,ansi_defaults	            --bit	Not nullable.   ANSI_DEFAULTS setting for the session.
    ,ansi_warnings	            --bit   Not nullable.	ANSI_WARNINGS setting for the session.
    ,ansi_padding	            --bit   Not nullable.	ANSI_PADDING setting for the session.
    ,ansi_nulls	                --bit   Not nullable 	ANSI_NULLS setting for the session.
    ,concat_null_yields_null	--bit	Not nullable.  CONCAT_NULL_YIELDS_NULL setting for the session.
    ,transaction_isolation_level	--smallint  Not nullable.
        --	Transaction isolation level of the session.
            -- 0 = Unspecified
            -- 1 = ReadUncommitted
            -- 2 = ReadCommitted
            -- 3 = RepeatableRead
            -- 4 = Serializable
            -- 5 = Snapshot

    ,lock_timeout	        --int   Not nullable.   LOCK_TIMEOUT setting for the session. The value is in milliseconds.
    ,deadlock_priority	    --int	Not nullable.  DEADLOCK_PRIORITY setting for the session.
    ,row_count	            --bigint  Not nullable. Number of rows returned on the session up to this point.
    ,prev_error	            --int  Not nullable.  	ID of the last error returned on the session.
    ,original_security_id	--varbinary(85)	 Not nullable.  Windows security ID that is associated with the original_login_name.
    ,original_login_name	--nvarchar(128)	Not nullable.
        --SQL Server login name that the client used to create this session. Can be a SQL Server authenticated login name, 
        --a Windows authenticated domain user name, or a contained database user. The session could have gone through many implicit or explicit 
        --context switches after the initial connection, for example, if EXECUTE AS is used.

    ,last_successful_logon	    --datetime	Time of the last successful logon for the original_login_name before the current session started.
    ,last_unsuccessful_logon	--datetime	Time of the last unsuccessful logon attempt for the original_login_name before the current session started.
    ,unsuccessful_logons	--bigint	Number of unsuccessful logon attempts for the original_login_name between the last_successful_logon and login_time.
    ,group_id	    --int	 Not nullable.  ID of the workload group to which this session belongs.

    ,database_id	--smallint	ID of the current database for each session.
        --In Azure SQL Database, the values are unique within a single database or an elastic pool, but not within a logical server.
        --AARON: what does this mean?

        --Applies to: SQL Server 2012 (11.x) and later versions.

    ,authenticating_database_id	    --int	ID of the database authenticating the principal. For logins, the value is 0. For contained database users, the value is the database ID of the contained database.
        --Applies to: SQL Server 2012 (11.x) and later versions.
    ,open_transaction_count	--int	Number of open transactions per session.
        --Applies to: SQL Server 2012 (11.x) and later versions.
        --"Because of differences in how they're recorded, open_transaction_count might not match sys.dm_tran_session_transactions.open_transaction_count."

    ,pdw_node_id	--int	The identifier for the node that this distribution is on.
        --Applies to: Azure Synapse Analytics, and Analytics Platform System (PDW).
    ,page_server_reads	--bigint	Not nullable.     Number of page server reads performed, by requests in this session, during this session. 
        --Applies to: Azure SQL Database Hyperscale.
FROM sys.dm_exec_sessions
;