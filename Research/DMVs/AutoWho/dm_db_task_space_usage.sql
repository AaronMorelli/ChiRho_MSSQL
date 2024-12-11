/* 
--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-task-space-usage-transact-sql

"IAM pages are not included in any of the page counts reported by this view."

"Page counters are initialized to zero (0) at the start of a request. These values are aggregated at the session level when the request is completed. 
For more information, see sys.dm_db_session_space_usage (Transact-SQL)."

"Work table caching, temporary table caching, and deferred drop operations affect the number of pages allocated and deallocated in a specified task."
*/


--AARON: does not look like any changes are needed for this table or the logic surrounding it?

SELECT
    session_id	--smallint	Session ID.
    ,request_id	--int	Request ID within the session.
        -- A request is also called a batch and may contain one or more queries. 
        -- A session may have multiple requests active at the same time. 
        --Each query in the request may start multiple threads (tasks), if a parallel execution plan is used.
    ,exec_context_id	--int	
        --Execution context ID of the task. For more information, see sys.dm_os_tasks (Transact-SQL).
    ,database_id	--smallint	
        --Database ID.
        --In Azure SQL Database, the values are unique within a single database or an elastic pool, but not within a logical server.


    /*
        "The following objects are included in the user object page counters:
            User-defined tables and indexes     <-- AARON: what does this mean in this context???
            System tables and indexes           <-- AARON: ditto, what does this mean in this context???
            Global temporary tables and indexes
            Local temporary tables and indexes
            Table variables
            Tables returned in the table-valued functions
        "
     */
    ,user_objects_alloc_page_count	    --bigint	
        --Number of pages reserved or allocated for user objects by this task.
    ,user_objects_dealloc_page_count	--bigint	
        --Number of pages deallocated and no longer reserved for user objects by this task.


    /*
        "Internal objects are only in tempdb. The following objects are included in the internal object page counters:
            - Work tables for cursor or spool operations and temporary large object (LOB) storage
            - Work files for operations such as a hash join
            - Sort runs
        "
     */
    ,internal_objects_alloc_page_count	--bigint	
        --Number of pages reserved or allocated for internal objects by this task.
    ,internal_objects_dealloc_page_count	--bigint	
        --Number of pages deallocated and no longer reserved for internal objects by this task.


    ,pdw_node_id	--int	
        --Applies to: Azure Synapse Analytics, Analytics Platform System (PDW)
        --The identifier for the node that this distribution is on.
FROM sys.dm_db_task_space_usage;