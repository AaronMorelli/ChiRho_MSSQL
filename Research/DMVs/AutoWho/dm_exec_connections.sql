--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-connections-transact-sql

/* IMPORTANT ON RELATIONSHIP WITH dm_exec_sessions:

most-often: one-to-one
"Most commonly, for each row in sys.dm_exec_connections there is a single matching row in sys.dm_exec_sessions. 

sessions 1-to-zero connections:
"However, in some cases such as system internal sessions or Service Broker activation procedures, 
there may be a row in sys.dm_exec_sessions without a matching row in sys.dm_exec_connections."

sessions 1-to-many connections:
"When MARS is used, there may be multiple rows in sys.dm_exec_connections for a row in sys.dm_exec_sessions, 
one row for the parent connection, and one row for each MARS logical session. 
The latter rows can be identified by the value in the net_transport column being set to Session. 
For these connections, the value in the connection_id column of sys.dm_exec_connections 
matches the value in the connection_id column of sys.dm_exec_requests for MARS requests in progress.
*/

SELECT
    session_id	--int	    Is nullable.
        --Identifies the session associated with this connection. 
    ,most_recent_session_id	    --int	    Is nullable.
        --Represents the session ID for the most recent request associated with this connection. (SOAP connections can be reused by another session.) 
    ,connect_time	    --datetime	NOT nullable.
        --Timestamp when connection was established. 
    ,net_transport	    --nvarchar(40)	 NOT nullable.
        --When MARS is used, returns Session for each additional connection associated with a MARS logical session.
        --Note: Describes the physical transport protocol that is used by this connection. 

    ,protocol_type	--nvarchar(40)	Is nullable.
        --Specifies the protocol type of the payload. It currently distinguishes between TDS ("TSQL"), "SOAP", and "Database Mirroring". 
    ,protocol_version	--int	    Is nullable.
        --Version of the data access protocol associated with this connection. 
    ,endpoint_id	--int	    Is nullable.
        --An identifier that describes what type of connection it is. This endpoint_id can be used to query the sys.endpoints view. 
    ,encrypt_option	--nvarchar(40)	    NOT nullable.
        --Boolean value to describe whether encryption is enabled for this connection. 
        --For HADR mirroring endpoints, this column always returns FALSE. Use the sys.database_mirroring_endpoints DMV instead to check if connections to a HADR mirroring endpoint are encrypted.

    ,auth_scheme	--nvarchar(40)	    NOT nullable.
        --Specifies SQL Server/Windows Authentication scheme used with this connection. 

    ,node_affinity	--smallint	NOT nullable.
        --Identifies the memory node to which this connection has affinity. 
    ,num_reads	    --int	Is nullable.
        --Number of byte reads that have occurred over this connection. 
    ,num_writes	    --int	Is nullable.
        --Number of byte writes that have occurred over this connection. 
    ,last_read	    --datetime	Is nullable.
        --Timestamp when last read occurred over this connection. 
    ,last_write	    --datetime	Is nullable.
        --Timestamp when last write occurred over this connection. 
    ,net_packet_size	--int	Is nullable.
        --Network packet size used for information and data transfer. 
    ,client_net_address	--varchar(48)	Is nullable.
        --Host address of the client connecting to this server. 
    ,client_tcp_port	--int	Is nullable.
        --Port number on the client computer that is associated with this connection. 
        --In Azure SQL Database, this column always returns NULL.
    ,local_net_address	--varchar(48)	Is nullable.
        --Represents the IP address on the server that this connection targeted. Available only for connections using the TCP transport provider. 
        --In Azure SQL Database, this column always returns NULL.
    ,local_tcp_port	--int	Is nullable.
        --Represents the server TCP port that this connection targeted if it were a connection using the TCP transport. 
        --In Azure SQL Database, this column always returns NULL.
    ,connection_id	    --uniqueidentifier	NOT nullable.
        --Identifies each connection uniquely. 
    ,parent_connection_id	--uniqueidentifier	Is nullable.
        --Identifies the primary connection that the MARS session is using. 
    ,most_recent_sql_handle	    --varbinary(64)	Is nullable.
        --The SQL handle of the last request executed on this connection. 
        --The most_recent_sql_handle column is always in sync with the most_recent_session_id column. 

    ,pdw_node_id	--int	
        --Applies to: Azure Synapse Analytics, Analytics Platform System (PDW)
        --The identifier for the node that this distribution is on.
FROM sys.dm_exec_connections;
