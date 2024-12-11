--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-waiting-tasks-transact-sql
--For SQL 2022 and later, requires VIEW SERVER PERFORMANCE STATE

--the "resource_description" column is a goldmine, with very specific formatting.
--See the latest here: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-waiting-tasks-transact-sql?view=sql-server-ver16#resource_description-column
--TODO: confirm that my logic conforms to this.


/* For Azure SQL DB:
YIKES, THIS IS COMPLICATED:
    "On SQL Database Basic, S0, and S1 service objectives, and for databases in elastic pools, 
    the server admin account, the Microsoft Entra admin account, or membership in the ##MS_ServerStateReader## server role is required. 
    
    On all other SQL Database service objectives, either the VIEW DATABASE STATE permission on the database, or membership in the ##MS_ServerStateReader## server role is required.
 */


 --AARON: looks like the only new column is Synapse-specific, so the only TODOs for me are to confirm that I have the correct field lengths

SELECT
    waiting_task_address	--varbinary(8)	
        --Address of the waiting task.
    ,session_id	            --smallint	
        --ID of the session associated with the task.
    ,exec_context_id	    --int	
        --ID of the execution context associated with the task.
    ,wait_duration_ms	    --bigint	
        --Total wait time for this wait type, in milliseconds. This time is inclusive of signal_wait_time.
    ,wait_type	            --nvarchar(60)	        AARON: is my data type 60 char long? Or did MSFT lengthen this recently and I need to update?
        --Name of the wait type.
    ,resource_address	    --varbinary(8)	
        --Address of the resource for which the task is waiting.
    ,blocking_task_address	--varbinary(8)	
        --Task that is currently holding this resource
    ,blocking_session_id	    --smallint	
        --ID of the session that is blocking the request. If this column is NULL, the request is not blocked, or the session information of the blocking session is not available (or cannot be identified).
                --  -2 = The blocking resource is owned by an orphaned distributed transaction.
                --  -3 = The blocking resource is owned by a deferred recovery transaction.
                --  -4 = session_id of the blocking latch owner couldn't be determined due to internal latch state transitions.

                -- Why is there not a "-5" item here, like there is for dm_exec_requests ?

    ,blocking_exec_context_id	--int	
        --ID of the execution context of the blocking task.
    ,resource_description	--nvarchar(3072)	        AARON: do I need to update the length in my schema?
        --Description of the resource that is being consumed. For more information, see resource_description column.

    ,pdw_node_id	            --int	
        --Applies to: Azure Synapse Analytics, Analytics Platform System (PDW)
        --The identifier for the node that this distribution is on.
FROM sys.dm_os_waiting_tasks wt
;