--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-memory-grants-transact-sql


--AARON: there are some useful new columns in this DMV. (Down near the bottom, but also review all cols against what I am pulling now)
SELECT
    session_id	    --smallint	
        --ID (SPID) of the session where this query is running.
    ,request_id	    --int	
        --ID of the request. Unique in the context of the session.
    ,scheduler_id	--int	
        --ID of the scheduler that is scheduling this query.
    ,dop	--smallint	
        --Degree of parallelism of this query.
    ,request_time	--datetime	
        --Date and time when this query requested the memory grant.
    ,grant_time	        --datetime	
        --Date and time when memory was granted for this query. NULL if memory is not granted yet.
    ,requested_memory_kb	--bigint	
        --Total requested amount of memory in kilobytes.
    ,granted_memory_kb	    --bigint	
        --Total amount of memory actually granted in kilobytes. Can be NULL if the memory is not granted yet. For a typical situation, this value should be the same as requested_memory_kb. For index creation, the server may allow additional on-demand memory beyond initially granted memory.
    ,required_memory_kb	    --bigint	
        --Minimum memory required to run this query in kilobytes. requested_memory_kb is the same or larger than this amount.
    ,used_memory_kb	    --bigint	
        --Physical memory used at this moment in kilobytes.
    ,max_used_memory_kb	    --bigint	
        --Maximum physical memory used up to this moment in kilobytes.
    ,query_cost	    --float	
        --Estimated query cost.
    ,timeout_sec	--int	
        --Time-out in seconds before this query gives up the memory grant request.
    ,resource_semaphore_id	--smallint	
        --Non-unique ID of the resource semaphore on which this query is waiting.
        --Note: This ID is unique in versions of SQL Server that are earlier than SQL Server 2008 (10.0.x). 
        --This change can affect troubleshooting query execution. For more information, see the "Remarks" section later in this article.
    ,queue_id	--smallint	
        --ID of waiting queue where this query waits for memory grants. NULL if the memory is already granted.
    ,wait_order	--int	
        --Sequential order of waiting queries within the specified queue_id. This value can change for a given query if other queries get memory grants or time out. NULL if memory is already granted.
    ,is_next_candidate	--bit	
        --Candidate for next memory grant.
            --1 = Yes
            --0 = No
            --NULL = Memory is already granted.
    ,wait_time_ms	--bigint	
        --Wait time in milliseconds. NULL if the memory is already granted.
    ,plan_handle	--varbinary(64)	
        --Identifier for this query plan. Use sys.dm_exec_query_plan to extract the actual XML plan.
    ,sql_handle	--varbinary(64)	
        --Identifier for Transact-SQL text for this query. Use sys.dm_exec_sql_text to get the actual Transact-SQL text.
    ,group_id	--int	
        --ID for the workload group where this query is running.
    ,pool_id	--int	
        --ID of the resource pool that this workload group belongs to.
    ,is_small	--tinyint	
        --When set to 1, indicates that this grant uses the small resource semaphore. When set to 0, indicates that a regular semaphore is used.
    ,ideal_memory_kb	--bigint	
        --Size, in kilobytes (KB), of the memory grant to fit everything into physical memory. This is based on the cardinality estimate.


    ,pdw_node_id	--int	The identifier for the node that this distribution is on.
        --Applies to: Azure Synapse Analytics, Analytics Platform System (PDW)
    ,reserved_worker_count	--bigint	Number of reserved worker threads.
        --Applies to: SQL Server (Starting with SQL Server 2016 (13.x)) and Azure SQL Database
    ,used_worker_count	--bigint	Number of worker threads used at this moment.
        --Applies to: SQL Server (Starting with SQL Server 2016 (13.x)) and Azure SQL Database
    ,max_used_worker_count	--bigint	Maximum number of worker threads used up to this moment.
        --Applies to: SQL Server (Starting with SQL Server 2016 (13.x)) and Azure SQL Database
    ,reserved_node_bitmap	--bigint	Bitmap of NUMA nodes where worker threads are reserved.
        --Applies to: SQL Server (Starting with SQL Server 2016 (13.x)) and Azure SQL Database
FROM sys.dm_exec_query_memory_grants;
