--Based on: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-session-space-usage-transact-sql

--One new field that is useful and should be included

SELECT
session_id	--smallint	Session ID.
    --session_id maps to session_id in sys.dm_exec_sessions.
,database_id	--smallint	Database ID.
    --In Azure SQL Database, the values are unique within a single database or an elastic pool, but not within a logical server.

--AARON: the definition of what takes up user allocations versus internal allocations is the same here as it is for dm_db_task_space_usage;
--see the doc page for either of these (or my notes in the dm_db_task_space_usage.sql file)
,user_objects_alloc_page_count	--bigint	
    --Number of pages reserved or allocated for user objects by this session.
,user_objects_dealloc_page_count	--bigint	
    --Number of pages deallocated and no longer reserved for user objects by this session.
,internal_objects_alloc_page_count	--bigint	
    --Number of pages reserved or allocated for internal objects by this session.
,internal_objects_dealloc_page_count	--bigint	
    --Number of pages deallocated and no longer reserved for internal objects by this session.

--AARON: this column is new, and is probably worth it!
--But the question: do I include it in the SUM (to calculate TempDB usage)? Or just have it in the clicable-XML?
,user_objects_deferred_dealloc_page_count	--bigint	--Number of pages which have been marked for deferred deallocation.
    --Note: Introduced in service packs for SQL Server 2012 (11.x) and SQL Server 2014 (12.x).

,pdw_node_id	--int	
    --Applies to: Azure Synapse Analytics, Analytics Platform System (PDW)
    --The identifier for the node that this distribution is on.
FROM sys.dm_db_session_space_usage;