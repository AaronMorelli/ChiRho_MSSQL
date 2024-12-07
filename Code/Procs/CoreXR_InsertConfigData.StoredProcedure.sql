SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.CoreXR_InsertConfigData
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

	FILE NAME: CoreXR_InsertConfigData.StoredProcedure.sql

	PROCEDURE NAME: CoreXR_InsertConfigData

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs at install time and inserts configuration data.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.CoreXR_InsertConfigData

--use to reset the data:
truncate table @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents;
truncate table @@CHIRHO_SCHEMA@@.CoreXR_Version;
truncate table @@CHIRHO_SCHEMA@@.CoreXR_CollectionInitiators;
*/
AS
BEGIN
	SET NOCOUNT ON;

	--To prevent this proc from damaging the installation after it has already been run, check for existing data.
	IF EXISTS (SELECT * FROM @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents)
		OR EXISTS (SELECT * FROM @@CHIRHO_SCHEMA@@.CoreXR_Version)
		OR EXISTS (SELECT * FROM @@CHIRHO_SCHEMA@@.CoreXR_CollectionInitiators)
	BEGIN
		RAISERROR('The configuration tables are not empty. You must clear these tables first before this procedure will insert config data', 16,1);
		RETURN -2;
	END
	
	INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	(EventGroup, trace_event_id, event_name, category_name, isEnabled)
	SELECT 'default',
		te.trace_event_id, 
		event_name = te.name, 
		category_name = tc.name,
		isEnabled = N'N'
	FROM sys.trace_events te
		INNER JOIN sys.trace_categories tc
			ON te.category_id = tc.category_id
	WHERE 1=1
	--omit some things to keep it simpler
	AND tc.name NOT IN (N'Broker',N'Deprecation',N'Full text',N'Query Notifications',N'Server')
	;

	--Set default "on" events for each category
	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'CLR'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Cursors'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Database'
	AND event_name IN (
		N'Data File Auto Grow',
		N'Log File Auto Grow'
	)
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Errors and Warnings'
	AND event_name IN (
		N'Background Job Error',		--don't know if a spid-filtered trace would catch these (i.e. system spid generated?)
		N'Database Suspect Data Page',
		N'ErrorLog',
		N'EventLog',
		N'Exception',
		N'Execution Warnings',
		N'User Error Message'
	);

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Locks'
	AND event_name IN (
		--Deadlocks occur on system SPIDs, and user should use the built-in XE trace or their own tracing for those
		N'Lock:Cancel',
		N'Lock:Escalation',
		N'Lock:Timeout',
		N'Lock:Timeout (timeout > 0)'
	);

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Objects'
	AND event_name IN (
		--Deadlocks occur on system SPIDs, and user should use the built-in XE trace or their own tracing for those
		N'Object:Altered',
		N'Object:Created',
		N'Object:Deleted'
	);

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'OLEDB'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Performance'
	AND event_name IN (
		N'Auto Stats',
		N'Showplan XML Statistics Profile'
	);

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Progress Report'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Scans'
	;

	--We just turn on 1 security audit event. If someone really wants to use this for security stuff, they need
	-- to think through which events they want
	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Security Audit'
	AND event_name = N'Audit Change Database Owner'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Sessions'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Stored Procedures'
	AND event_name IN (
		N'RPC:Completed',
		N'SP:Completed',
		N'SP:StmtCompleted'
	);

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'Transactions'
	AND event_name = N'TransactionLog'
	;

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'TSQL'
	AND event_name IN (
		N'SQL:BatchCompleted',
		N'SQL:StmtCompleted'
	);

	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
	SET isEnabled = N'Y'
	WHERE category_name = N'User configurable'
	;

	--Now insert non-Default trace events

	--SeeOuterBatch (usually to see param values)
	-- You can't filter by object ID for RPC, so often you filter by LIKE on the text field
	INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
		(EventGroup, trace_event_id, event_name, category_name, isEnabled)
	SELECT N'seeouterbatch',
		te.trace_event_id, 
		event_name = te.name, 
		category_name = tc.name,
		isEnabled = CASE WHEN te.name IN (N'RPC:Completed', N'SQL:BatchCompleted',N'Exec Prepared SQL')
						THEN N'Y'
						ELSE N'N'
					END
	FROM sys.trace_events te
		INNER JOIN sys.trace_categories tc
			ON te.category_id = tc.category_id
	WHERE 1=1
	AND (
		(tc.name = N'Stored Procedures'
		AND te.name IN (
			N'RPC Output Parameter',
			N'RPC:Completed',
			N'RPC:Starting'
			)
		)

		OR 
		
		(tc.name = N'TSQL'
		AND te.name IN (
			N'Exec Prepared SQL',
			N'Prepare SQL',
			N'SQL:BatchCompleted',
			N'SQL:BatchStarting',
			N'Unprepare SQL'
			)
		)
	)
	;


	--PerfCommon (events the author has used most often to tune slow statements & objects)
	INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
		(EventGroup, trace_event_id, event_name, category_name, isEnabled)
	SELECT N'perfcommon',
		te.trace_event_id, 
		event_name = te.name, 
		category_name = tc.name,
		isEnabled = CASE 
						WHEN tc.name = N'TSQL'
							AND te.name = N'SQL:StmtCompleted' THEN N'Y'
						WHEN tc.name = N'Performance' THEN N'Y'
						WHEN tc.name = N'Transactions' THEN N'Y'
						WHEN tc.name = N'Stored Procedures'
							AND te.name IN (N'SP:Completed', N'SP:StmtCompleted', N'SP:Recompile')
							THEN N'Y'
						WHEN tc.name = N'Errors and Warnings' THEN N'Y'
						ELSE N'N'
					END
	FROM sys.trace_events te
		INNER JOIN sys.trace_categories tc
			ON te.category_id = tc.category_id
	WHERE 1=1
	AND (
		(tc.name = N'Stored Procedures'
		AND te.name IN (
			N'RPC:Completed',
			N'SP:CacheHit',
			N'SP:CacheInsert',
			N'SP:CacheMiss',
			N'SP:CacheRemove',
			N'SP:Completed',
			N'SP:Recompile',
			N'SP:StmtCompleted'
			)
		)

		OR
		(tc.name = N'TSQL'
		AND te.name IN (
			N'Exec Prepared SQL',
			N'Prepare SQL',
			N'SQL:BatchCompleted',
			N'SQL:StmtCompleted',
			N'SQL:StmtRecompile',
			N'Unprepare SQL'
			)
		)

		OR
		(tc.name = N'Performance'
		AND te.name IN (
			N'Auto Stats',
			N'Degree of Parallelism',
			N'Showplan XML Statistics Profile'
			)
		)

		OR (tc.name = N'Transactions' AND te.name = N'TransactionLog')

		OR 
		(tc.name = N'Errors and Warnings'
		AND te.name IN (
			N'Bitmap Warning',
			N'CPU threshold exceeded',
			N'Exchange Spill Event',
			N'Hash Warning',
			N'Missing Column Statistics',
			N'Missing Join Predicate',
			N'Sort Warnings'
			)
		)
	)
	ORDER BY category_name, event_name
	;


	--PerfDetailed (more info for those tough tuning efforts)
	INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_ProfilerTraceEvents
		(EventGroup, trace_event_id, event_name, category_name, isEnabled)
	SELECT N'perfdetailed',
		te.trace_event_id, 
		event_name = te.name, 
		category_name = tc.name,
		isEnabled = CASE 
						WHEN tc.name = N'Cursors' THEN N'Y'
						WHEN tc.name = N'Database' THEN N'Y'
						WHEN tc.name = N'Errors and Warnings' THEN N'Y'
						WHEN tc.name = N'Locks' THEN N'Y'
						WHEN tc.name = N'Performance' AND te.name <> N'Performance statistics' THEN N'Y'
							--that event can be kinda annoying, so leave off by default
						WHEN tc.name = N'Stored Procedures' THEN N'Y'
						WHEN tc.name = N'Transactions' THEN N'Y'
						WHEN tc.name = N'TSQL' THEN N'Y'
						ELSE N'N'
					END
	FROM sys.trace_events te
		INNER JOIN sys.trace_categories tc
			ON te.category_id = tc.category_id
	WHERE 1=1
	AND (
		(tc.name = N'Cursors'
		)		

		OR
		(tc.name = N'Database'
		AND te.name IN (
			N'Data File Auto Grow',
			N'Log File Auto Grow'
			)
		)

		OR
		(tc.name = N'Errors and Warnings'
		AND te.name IN (
			N'Background Job Error',
			N'Bitmap Warning',
			N'Blocked process report',
			N'CPU threshold exceeded',
			N'Exchange Spill Event',
			N'Hash Warning',
			N'Missing Column Statistics',
			N'Missing Join Predicate',
			N'Sort Warnings'
			)
		)

		OR 
		(tc.name = N'Locks' AND te.name IN (
			N'Lock:Cancel',
			N'Lock:Escalation',
			N'Lock:Timeout',
			N'Lock:Timeout (timeout > 0)'
			)
		)

		OR
		(tc.name = N'Performance'
		AND te.name IN (
			N'Auto Stats',
			N'Degree of Parallelism',
			N'Performance statistics',
			N'Plan Guide Successful',
			N'Plan Guide Unsuccessful',
			N'Showplan XML Statistics Profile'
			)
		)

		OR
		(tc.name = N'Stored Procedures'
		AND te.name IN (
			N'RPC Output Parameter',
			N'RPC:Completed',
			N'RPC:Starting',
			N'SP:CacheHit',
			N'SP:CacheInsert',
			N'SP:CacheMiss',
			N'SP:CacheRemove',
			N'SP:Completed',
			N'SP:Recompile',
			N'SP:Starting',
			N'SP:StmtCompleted',
			N'SP:StmtStarting'
			)
		)

		OR (tc.name = N'Transactions' AND te.name = N'TransactionLog')

		OR
		(tc.name = N'TSQL'
		AND te.name IN (
			N'Exec Prepared SQL',
			N'Prepare SQL',
			N'SQL:BatchCompleted',
			N'SQL:BatchStarting',
			N'SQL:StmtCompleted',
			N'SQL:StmtRecompile',
			N'SQL:StmtStarting',
			N'Unprepare SQL'
			)
		)
	)
	ORDER BY category_name, event_name;

	INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_Version ([Version], EffectiveDate, EffectiveDateUTC)
		SELECT '2008R2.1', GETDATE(), GETUTCDATE();

	INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_CollectionInitiators 
	(CollectionInitiatorID, CollectionInitiator)
	SELECT 255, N'@@CHIRHO_SCHEMA@@.AutoWho_Executor' UNION ALL		--making the default trace the high key reduces page splits
	SELECT 254, N'ServerEye_Executor' UNION ALL		-- since the default/automated trace will generate collection data
	SELECT 1,   N'sp_XR_SessionViewer' UNION ALL	-- at a *much* higher rate than the sp_XR* procs
	SELECT 2,   N'sp_XR_QueryProgress';

	RETURN 0;
END

GO
