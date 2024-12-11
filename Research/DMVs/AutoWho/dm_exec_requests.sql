--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql
--NOTE: "In SQL Server 2022 (16.x) and later versions, requires VIEW SERVER PERFORMANCE STATE permission on the server."

--NOTE: "When executing parallel requests in row mode, SQL Server assigns a worker thread to coordinate the worker threads responsible for 
--completing tasks assigned to them. In this DMV, only the coordinator thread is visible for the request. The columns reads, writes, 
--logical_reads, and row_count are not updated for the coordinator thread. The columns wait_type, wait_time, last_wait_type, wait_resource, 
--and granted_query_memory are only updated for the coordinator thread. For more information, see the Thread and Task Architecture Guide."

--IS THIS TRUE???: "VIEW SERVER STATE can't be granted in Azure SQL Database so sys.dm_exec_requests is always limited to the current connection."

--DOES THIS AFFECT ME???: "In availability group scenarios, if the secondary replica is set to read-intent only, the connection to the secondary 
--must specify its application intent in connection string parameters by adding applicationintent=readonly. 
--Otherwise, the access check for sys.dm_exec_requests doesn't pass for databases in the availability group, even if VIEW SERVER STATE permission 
--is present."

SELECT
/*** Section 1: columns that I have already implemented ***/
    session_id	    --smallint	ID of the session to which this request is related. Not nullable.
    ,request_id	    --int	    ID of the request. Unique in the context of the session. Not nullable.
    ,start_time	    --datetime	Timestamp when the request arrived. Not nullable.
    ,status	        --nvarchar(30)	Status of the request. Not nullable. Can be one of the following values:
                        --background
                        --rollback
                        --running
                        --runnable
                        --sleeping
                        --suspended

    ,command	    --nvarchar(32)  Not nullable.	Identifies the current type of command that is being processed. Common command types include the following values:
                        --SELECT
                        --INSERT
                        --UPDATE
                        --DELETE
                        --BACKUP LOG
                        --BACKUP DATABASE
                        --DBCC
                        --FOR

                    --Internal system processes set the command based on the type of task they perform. Tasks can include the following values:
                        --LOCK MONITOR
                        --CHECKPOINTLAZY
                        --WRITER

    ,sql_handle	    --varbinary(64)  Nullable. 	Is a token that uniquely identifies the batch or stored procedure that the query is part of
    ,statement_start_offset	    --int	Nullable.  Indicates, in bytes, beginning with 0, the starting position of the currently executing statement for the currently executing batch or persisted object. 
    ,statement_end_offset	    --int	Nullable.  Indicates, in bytes, starting with 0, the ending position of the currently executing statement for the currently executing batch or persisted object.
    ,plan_handle	--varbinary(64)   Nullable.	Is a token that uniquely identifies a query execution plan for a batch that is currently executing. 
    ,database_id	--smallint	      Not nullable.  ID of the database the request is executing against.  AARON: seems better to say that this is the "DB context" that the session is currently running under.
                                --In Azure SQL Database, the values are unique within a single database or an elastic pool, but not within a logical server.
                                --AARON: what does this mean???

    ,user_id	    --int	Not nullable.  ID of the user who submitted the request. 
    ,connection_id	--uniqueidentifier	Nullable.  ID of the connection on which the request arrived. 
    ,blocking_session_id	--smallint	
                                --ID of the session that is blocking the request. If this column is NULL or 0, the request isn't blocked, 
                                --or the session information of the blocking session isn't available (or can't be identified). 
                                --For more information, see "Understand and resolve SQL Server blocking problems."

                                --   -2 = The blocking resource is owned by an orphaned distributed transaction.
                                --   -3 = The blocking resource is owned by a deferred recovery transaction.
                                --   -4 = session_id of the blocking latch owner couldn't be determined at this time because of internal latch state transitions.
                                --   -5 = session_id of the blocking latch owner couldn't be determined because it isn't tracked for this latch type (for example, for an SH latch).

                                --AARON: "-5" is new (I also do not remember -4 being around, so that is probably also new. Looks like MSFT is trying to identify blockers based on latches, not just locks)
                                --   By itself, blocking_session_id -5 does not indicate a performance problem. 
                                --   -5 is an indication that the session is waiting on an asynchronous action to complete. 
                                --   Before -5 was introduced, the same session would have shown blocking_session_id 0, even though it was still in a wait state.
                                --   Depending on workload, observing blocking_session_id = -5 may be a common occurrence.

    ,wait_type	        --nvarchar(60)  Nullable.	If the request is currently blocked, this column returns the type of wait. 

    ,wait_time	        --int	Not nullable.      If the request is currently blocked, this column returns the duration in milliseconds, of the current wait. 
    ,last_wait_type	    --nvarchar(60)	Not Nullable.   If this request has previously been blocked, this column returns the type of the last wait.
    ,wait_resource	    --nvarchar(256)	Not nullable.   If the request is currently blocked, this column returns the resource for which the request is currently waiting. 
    ,open_transaction_count	  -- int	Not nullable.   Number of transactions that are open for this request. 
    ,open_resultset_count	--int	Not nullable.       Number of result sets that are open for this request. 
    ,transaction_id	        --bigint	Not nullable.   ID of the transaction in which this request executes. 
    ,context_info	        --varbinary(128)	Nullable.  CONTEXT_INFO value of the session. 
    ,percent_complete	--real	Not nullable.  Percentage of work completed for the following commands:
                                --ALTER INDEX REORGANIZE
                                --AUTO_SHRINK option with ALTER DATABASE
                                --BACKUP DATABASE
                                --DBCC CHECKDB
                                --DBCC CHECKFILEGROUP
                                --DBCC CHECKTABLE
                                --DBCC INDEXDEFRAG
                                --DBCC SHRINKDATABASE
                                --DBCC SHRINKFILE
                                --RECOVERY
                                --RESTORE DATABASE
                                --ROLLBACK
                                --TDE ENCRYPTION

    ,estimated_completion_time	    --bigint	Not nullable.  Internal only. 
    ,cpu_time	        --int	Not nullable.   CPU time in milliseconds that is used by the request. 
    ,total_elapsed_time	--int	Not nullable.   Total time elapsed in milliseconds since the request arrived. 
    ,scheduler_id	    --int   Nullable.	    ID of the scheduler that is scheduling this request.
    ,task_address	    --varbinary(8)  Nullable.  Memory address allocated to the task that is associated with this request.
    ,reads	            --bigint	Not nullable.  Number of reads performed by this request. 
    ,writes	            --bigint	Not nullable.  Number of writes performed by this request. 
    ,logical_reads	    --bigint	Not nullable.  Number of logical reads that have been performed by the request.
    ,text_size	        --int	    Not nullable.  TEXTSIZE setting for this request.
    ,language	        --nvarchar(128)	 Nullable.  Language setting for the request.
    ,date_format	    --nvarchar(3)	Nullable.  DATEFORMAT setting for the request.
    ,date_first	        --smallint	Not nullable.  DATEFIRST setting for the request. 
    ,quoted_identifier	--bit  Not nullable.        1 = QUOTED_IDENTIFIER is ON for the request. Otherwise, it's 0.
    ,arithabort	        --bit  Not nullable.        1 = ARITHABORT setting is ON for the request. Otherwise, it's 0.
    ,ansi_null_dflt_on	--bit  Not nullable.        1 = ANSI_NULL_DFLT_ON setting is ON for the request. Otherwise, it's 0.
    ,ansi_defaults	    --bit  Not nullable.    	1 = ANSI_DEFAULTS setting is ON for the request. Otherwise, it's 0.
    ,ansi_warnings	    --bit  Not nullable.     	1 = ANSI_WARNINGS setting is ON for the request. Otherwise, it's 0.
    ,ansi_padding	    --bit  Not nullable.    	1 = ANSI_PADDING setting is ON for the request. Otherwise, it's 0.
    ,ansi_nulls	        --bit  Not nullable.    	1 = ANSI_NULLS setting is ON for the request. Otherwise, it's 0.
    ,concat_null_yields_null	--bit  Not nullable.  1 = CONCAT_NULL_YIELDS_NULL setting is ON for the request. Otherwise, it's 0.
    ,transaction_isolation_level	--smallint	Not nullable.   Isolation level with which the transaction for this request is created.
                                        --0 = Unspecified
                                        --1 = ReadUncommitted
                                        --2 = ReadCommitted
                                        --3 = Repeatable
                                        --4 = Serializable
                                        --5 = Snapshot
    ,lock_timeout	    --int  Not nullable.	Lock time-out period in milliseconds for this request.
    ,deadlock_priority	--int  Not nullable. 	DEADLOCK_PRIORITY setting for the request.
    ,row_count	        --bigint Not nullable.	Number of rows that have been returned to the client by this request.
    ,prev_error	        --int	 Not nullable.  Last error that occurred during the execution of the request.
    ,nest_level	        --int	 Not nullable.  Current nesting level of code that is executing on the request.
    ,granted_query_memory	--int	Not nullable.  Number of pages allocated to the execution of a query on the request.

    ,executing_managed_code	--bit   Not nullable. Indicates whether a specific request is currently executing common language runtime objects, 
                            --         such as routines, types, and triggers. it's set for the full time a common language runtime object is on the stack, 
                            --         even while running Transact-SQL from within common language runtime.

    ,group_id	        --int  Not nullable.	ID of the workload group to which this query belongs
    ,query_hash	        --binary(8)	        Binary hash value calculated on the query and used to identify queries with similar logic. 
                        --                  You can use the query hash to determine the aggregate resource usage for queries that differ only by literal values.
    ,query_plan_hash	--binary(8)	        Binary hash value calculated on the query execution plan and used to identify similar query execution plans. 
                        --                  You can use query plan hash to find the cumulative cost of queries with similar execution plans.

/*** Section 2: columns that were implemented in newer versions, that are not yet in AutoWho.
    None of these are "critically-important", though most of them would be helpful to some extent.
    Right now I'm debating on my supportability "cutoff", whether to try to limit features to just what is present
    when I wrote this originally (in 2015-2017 and had to support SQL 2008 and 2008 R2 stuff)
***/
    ,statement_sql_handle	--varbinary(64)	    sql_handle of the individual query.  This column is NULL if Query Store is not enabled for the database.
        --Applies to: SQL Server 2014 (12.x) and later.

    ,statement_context_id	--bigint	  The optional foreign key to sys.query_context_settings. This column is NULL if Query Store is not enabled for the database.
        --Applies to: SQL Server 2014 (12.x) and later.

    ,dop	                --int	        The degree of parallelism of the query.
        --Applies to: SQL Server 2016 (13.x) and later.

    ,parallel_worker_count	--int	        The number of reserved parallel workers if this is a parallel query.
        --Applies to: SQL Server 2016 (13.x) and later.

    ,external_script_request_id	    --uniqueidentifier	The external script request ID associated with the current request.
        --Applies to: SQL Server 2016 (13.x) and later.


    is_resumable	--bit	        Indicates whether the request is a resumable index operation.
        --Applies to: SQL Server 2017 (14.x) and later.

    ,page_resource	--binary(8)	    An 8-byte hexadecimal representation of the page resource if the wait_resource column contains a page. For more information, see sys.fn_PageResCracker.
        --Applies to: SQL Server 2019 (15.x)

    ,page_server_reads	--bigint  Not nullable.  Number of page server reads performed by this request.
        --Applies to: Azure SQL Database Hyperscale

    ,dist_statement_id	--uniqueidentifier	 Not nullable.  Unique ID for the statement for the request submitted.
        --Applies to: SQL Server 2022 and later versions, Azure SQL Database, Azure SQL Managed Instance, Azure Synapse Analytics (serverless pools only), and Microsoft Fabric

FROM sys.dm_exec_requests r
;