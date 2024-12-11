--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-tasks-transact-sql
-- Same 2022 note about VIEW SERVER PERFORMANCE STATE that applies to other views.

/* Azure SQL DB is complicated:
    "On SQL Database Basic, S0, and S1 service objectives, and for databases in elastic pools, the server admin account, 
    the Microsoft Entra admin account, or membership in the ##MS_ServerStateReader## server role is required. 
    On all other SQL Database service objectives, either the VIEW DATABASE STATE permission on the database, 
    or membership in the ##MS_ServerStateReader## server role is required."
 */

SELECT
    task_address	--varbinary(8)	
        --Memory address of the object.
    task_state	--nvarchar(60)	
        --State of the task. This can be one of the following:
            --PENDING: Waiting for a worker thread.
            --RUNNABLE: Runnable, but waiting to receive a quantum.
            --RUNNING: Currently running on the scheduler.
            --SUSPENDED: Has a worker, but is waiting for an event.
            --DONE: Completed.
            --SPINLOOP: Stuck in a spinlock.
    context_switches_count	--int	
        --Number of scheduler context switches that this task has completed.
    pending_io_count	--int	
        --Number of physical I/Os that are performed by this task.
    pending_io_byte_count	--bigint	
        --Total byte count of I/Os that are performed by this task.
    pending_io_byte_average	    --int	
        --Average byte count of I/Os that are performed by this task.
    scheduler_id	    --int	
        --ID of the parent scheduler (see sys.dm_os_schedulers).
    session_id	        --smallint	
        --ID of the session that is associated with the task.
    exec_context_id	    --int	
        --Execution context ID that is associated with the task.
    request_id	--int	
        --ID of the request of the task.

    worker_address	--varbinary(8)	
        --Memory address of the worker that is running the task (see sys.dm_os_workers)
        -- NULL = Task is either waiting for a worker to be able to run, or the task has just finished running.

    host_address	--varbinary(8)	
        --Memory address of the host (see sys.dm_os_hosts). This helps identify the host that was used to create this task.
        --0 = Hosting was not used to create the task. 

    ,parent_task_address	--varbinary(8)	
        --Memory address of the task that is the parent of the object.
    ,pdw_node_id	--int	
        --Applies to: Azure Synapse Analytics, Analytics Platform System (PDW)
        --The identifier for the node that this distribution is on.
FROM sys.dm_os_tasks t;