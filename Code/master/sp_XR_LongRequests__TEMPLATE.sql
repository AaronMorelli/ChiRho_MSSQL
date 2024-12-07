SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_MASTERPROC_SCHEMA@@.sp_XR_LongRequests
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

	FILE NAME: sp_XR_LongRequests__TEMPLATE.sql

	PROCEDURE NAME: sp_XR_LongRequests

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Returns a listing of requests (unique session_id/request_id/request_start_time) whose duration
	(as observed at a given point in time by AutoWho collections) is > than a certain threshold. This can be
	used to find long-running requests in a longer time window, or to compare a given batch process between
	a "good" run and a "bad" run.

To Execute
------------------------
exec sp_XR_LongRequests @start='2016-05-17 04:00', @end='2016-05-17 06:00', @savespace=N'N'

*/
(
	@start			DATETIME=NULL,			--the start of the time window. If NULL, defaults to 4 hours ago.
	@end			DATETIME=NULL,			-- the end of the time window. If NULL, defaults to 1 second ago.
	@source			NVARCHAR(20)=N'trace',		--'trace' = standard @@CHIRHO_SCHEMA@@.AutoWho_Executor background trace; 
												-- 'pastsv' reviews data from past sp_XR_SessionViewer calls done in "current" mode
												-- 'pastqp' reviews data from past sp_XR_QueryProgress calls done in "current" or "time series" mode.
												-- This param is ignored if this invocation is "current" mode (i.e. start/end are null)
	@units			NVARCHAR(20)=N'mb',		-- mb, native, or pages
	@mindur			INT=120,				-- in seconds. Only batch requests with at least one entry in SAR that is >= this val will be included
	@dbs			NVARCHAR(512)=N'',		--list of DB names to include
	@xdbs			NVARCHAR(512)=N'',		--list of DB names to exclude
	@spids			NVARCHAR(128)=N'',		--comma-separated list of session_ids to include
	@xspids			NVARCHAR(128)=N'',		--comma-separated list of session_ids to exclude
	@attr			NCHAR(1)=N'n',			--Whether to include the session/connection attributes for the request's first entry in sar (in the time range)
	@plan			NVARCHAR(20)=N'none',		--none / statement		whether to include the query plan for each statement
	@help			NVARCHAR(10)=N'n'		-- "params", "columns", or "all" (anything else <> "N" maps to "all")
)
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET ANSI_PADDING ON;

	DECLARE @scratch__int				INT,
			@lv__StartUTC				DATETIME,
			@lv__EndUTC					DATETIME,
			@helpexec					NVARCHAR(4000),
			@err__msg					NVARCHAR(MAX),
			@DynSQL						NVARCHAR(MAX),
			@helpstr					NVARCHAR(MAX),
			@lv__CollectionInitiatorID	TINYINT,
			@lv__qplan					NCHAR(1)
			;

	--We always print out the exec syntax (whether help was requested or not) so that the user can switch over to the Messages
	-- tab and see what their options are.
	SET @helpexec = N'
exec sp_XR_LongRequests @start=''<start datetime>'', @end=''<end datetime>'', @mindur=120, 
	@source=N''trace'',		-- t/trace, sv/pastsv, qp/pastqp
	@units=N''mb'',			-- m/mb, n/native, p/pages
	@dbs=N'''', @xdbs=N'''', @spids=N'''', @xspids=N'''', 
	@attr=N''n'', @plan=N''none'',			--n/none, s/statement
	@help = N''n''							--n, p/params, c/columns, a/all
	';

	--handle case-sensitivity and nulls for string parameters
	SELECT 
		@help = LOWER(ISNULL(@help,N'all')),		--unlike the other parms, an invalid help still gets help info rather than raiserror
		@source = LOWER(ISNULL(@source,N'z')),
		@units = LOWER(ISNULL(@units,N'z')),
		@attr = LOWER(ISNULL(@attr,N'z')),
		@plan = LOWER(ISNULL(@plan,N'z'))
		;

	IF @help <> N'n'
	BEGIN
		GOTO helpbasic
	END

	IF @start IS NULL
	BEGIN
		SET @start = DATEADD(HOUR, -4, GETDATE());
		RAISERROR('Parameter @start set to 4 hours ago because a NULL value was supplied.', 10, 1) WITH NOWAIT;
	END

	SET @helpexec = REPLACE(@helpexec,'<start datetime>', REPLACE(CONVERT(NVARCHAR(20), @start, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @start, 108) + '.' + 
													RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @start)),3)
					);

	IF @end IS NULL
	BEGIN
		SET @end = DATEADD(SECOND,-1, GETDATE());
		RAISERROR('Parameter @end set to 1 second ago because a NULL value was supplied.',10,1) WITH NOWAIT;
	END

	SET @helpexec = REPLACE(@helpexec,'<end datetime>', REPLACE(CONVERT(NVARCHAR(20), @end, 102),'.','-') + ' ' + CONVERT(NVARCHAR(20), @end, 108) + '.' + 
														RIGHT(CONVERT(NVARCHAR(20),N'000') + CONVERT(NVARCHAR(20),DATEPART(MILLISECOND, @end)),3)
						);

	SET @lv__StartUTC = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @start);
	SET @lv__EndUTC = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @end);

	--We use UTC for this check b/c of the DST "fall-back" scenario. We don't want to prevent a user from calling this proc for a timerange 
	--that already occurred (e.g. 1:30am-1:45am) at the second occurrence of 1:15am that day.
	IF @lv__StartUTC > GETUTCDATE() OR @lv__EndUTC > GETUTCDATE()
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Neither of the parameters @start or @end can be in the future.',16,1);
		RETURN -1;
	END
	
	IF @end <= @start
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @end cannot be <= to parameter @start', 16, 1);
		RETURN -1;
	END

	IF @source LIKE N't%'
	BEGIN
		SET @source = N'trace';
		SET @lv__CollectionInitiatorID = 255;	--use the standard historical data collected by @@CHIRHO_SCHEMA@@.AutoWho_Executor
	END
	ELSE IF @source LIKE N'%sv'
	BEGIN
		SET @source = N'pastsv';
		SET @lv__CollectionInitiatorID = 1;		--use the data collected by past calls to sp_XR_SessionViewer
	END
	ELSE IF @source LIKE N'%qp'
	BEGIN
		SET @source = N'pastqp';
		SET @lv__CollectionInitiatorID = 2;		--use the data collected by past calls to sp_XR_QueryProgress
	END
	ELSE
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @source must be either "trace" (historical data from standard AutoWho trace, default), "pastsv" (data from past sp_XR_SessionViewer executions), or "pastqp" (data from past sp_XR_QueryProgress executions).',16,1);
		RETURN -1;
	END

	IF @units LIKE N'm%'
	BEGIN
		SET @units = N'mb';
	END
	ELSE IF @units LIKE N'n%'
	BEGIN
		SET @units = N'native';
	END
	ELSE IF @units LIKE N'p%'
	BEGIN
		SET @units = N'pages';
	END
	ELSE
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @units must be either "mb" (megabytes, default), "native" (DMV native units), or "pages" (8kb pages).',16,1);
		RETURN -1;
	END

	IF ISNULL(@mindur, -1) < 0
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @mindur must be an integer >= 0.', 16, 1);
		RETURN -1;
	END

	IF @attr NOT IN (N'n', N'y')
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @attr must be either "n" (default) or "y".', 16, 1);
		RETURN -1;
	END

	IF @plan LIKE N'n%'
	BEGIN
		SET @plan = N'none';
		SET @lv__qplan = N'n';
	END
	ELSE IF @plan LIKE N's%'
	BEGIN
		SET @plan = N'statement';
		SET @lv__qplan = N'y';
	END
	ELSE
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @plan must be either "none" or "statement".',16,1);
		RETURN -1;
	END

	--We don't validate the 4 CSV filtering variables, outside of checking for NULL. We leave that to the sub-procs
	IF @dbs IS NULL
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @dbs cannot be NULL; it should either be an empty string or a comma-delimited string of database names.',16,1);
		RETURN -1;
	END

	IF @xdbs IS NULL
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @xdbs cannot be NULL; it should either be an empty string or a comma-delimited string of database names.',16,1);
		RETURN -1;
	END

	IF @spids IS NULL
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @spids cannot be NULL; it should either be an empty string or a comma-delimited string of session IDs.',16,1);
		RETURN -1;
	END

	IF @xspids IS NULL
	BEGIN
		RAISERROR(@helpexec,10,1);
		RAISERROR('Parameter @xspids cannot be NULL; it should either be an empty string or a comma-delimited string of session IDs.',16,1);
		RETURN -1;
	END

	EXEC @@CHIRHO_DB@@.@@CHIRHO_SCHEMA@@.AutoWho_ViewLongRequests @init = @lv__CollectionInitiatorID,
			@start = @start, 
			@end = @end, 
			@mindur = @mindur,
			@spids = @spids, 
			@xspids = @xspids,
			@dbs = @dbs, 
			@xdbs = @xdbs,
			@attr = @attr,
			@plan = @lv__qplan,
			@units=@units
	;

	--we always print out at least the EXEC command
	GOTO helpbasic



helpbasic:

	IF @help <> N'n'
	BEGIN
		IF @help LIKE N'p%'
		BEGIN
			SET @help = N'params';
		END

		ELSE IF @help LIKE N'c%'
		BEGIN
			SET @help = N'columns';
		END
		ELSE 
		BEGIN
			--user may have typed gibberish... which is ok, give him/her all the help
			SET @Help = N'all';
		END
	END

	SET @helpstr = @helpexec;
	RAISERROR(@helpstr,10,1) WITH NOWAIT;
	
	IF @Help = N'n'
	BEGIN
		--because the user may want to use sp_XR_SessionViewer and/or sp_XR_QueryProgress next, if they haven't asked for help explicitly, we print out the syntax for 
		--the Session Viewer and Query Progress procedures
		SET @helpstr = N'
EXEC dbo.sp_XR_SessionViewer @start=''<start datetime>'',@end=''<end datetime>'', --@offset=99999,	--99999
	@source=N''trace'',		-- trace, pastSV, pastQP
	@camrate=0, @camstop=60,
	@activity=1,@dur=0, @dbs=N'''',@xdbs=N'''', @spids=N'''',@xspids=N'''', @blockonly=N''N'',
	@attr=N''N'',@resources=N''N'',@batch=N''N'',@plan=N''none'',	--none, statement, full
	@ibuf=N''N'',@bchain=0,@tran=N''N'',@waits=0,		--bchain 0-10, waits 0-3
	@savespace=N''N'',@directives=N'''', @help=N''N''		--"query(ies)"
	';

		RAISERROR(@helpstr,10,1);

--		SET @helpstr = '
--EXEC dbo.sp_XR_QueryProgress @start=''<start datetime>'',@end=''<end datetime>'', --@offset=99999,	--99999
--						@spid=<int>, @request=0, @nodeassociate=N''N'',
--						@help=N''N''		--"query(ies)"
--		';
		--TODO: once QP is ready, include it in the output here

		RETURN 0;
	END

	SET @helpstr = N'
ChiRho version 2008R2.1

Key Concepts and Terminology
-------------------------------------------------------------------------------------------------------------------------------------------
sp_XR_LongRequests displays data from AutoWho, a subcomponent of the ChiRho toolkit that snapshots (by default, every 15 seconds) the 
session-centric DMVs and stores the results in tables in the AutoWho schema. sp_XR_LongRequests searches a time window and identifies 
longer-running requests, aggregating data up to the individual statements executed by that request (at least as observed by AutoWho 
snapshotting). This gives the user the ability to review a long-running request/batch to identify the problem statements or compare 
between "good" and "bad runs. This proc also has cousins: 

	- sp_XR_SessionSummary: aggregates and displays one row per AutoWho snapshot (called a "capture"), giving the user a quick summary of what 
							was/wasn''t occurring in the session-centric DMVs at that point in time. A user can quickly review a window of time 
							looking for problems in blocking, resource utilization, long transactions, or long queries.

	- sp_XR_SessionViewer: shows a single AutoWho capture at a time, giving the user details on actively-running queries, blocking,
						   resource usage, session/connection attributes, and query plans for a particular point in time.

	- sp_XR_FrequentQueries: searches a time window and identifies frequently-run queries (and input buffers for idle spids), and aggregates
							 statistics for those high-frequency results. This gives the user the ability to identify commonly-observed
							 statements or pauses in transactions and compare between "good" and "bad" windows of time.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
On a typical install of ChiRho, the AutoWho code typically executes in the context of a background trace, polling every 15 seconds. However, 
the same AutoWho collection code can be run by sp_XR_SessionViewer whenever it is running in "current mode". Regardless of which method is 
used to collect AutoWho data, it is always stored in AutoWho tables. Thus, even a "current mode" run of sp_XR_SessionViewer stores data from 
the DMVs into AutoWho tables before displaying to the user. A tag in the AutoWho tables is used to differentiate which method of collection was 
used for each capture, essentially partitioning (logically) the data into different "sets". The @source parameter allows the user to target these 
different sets when using sp_XR_LongRequests, though only rarely will a value other than "trace" be useful for reviewing LongRequests.

sp_XR_LongRequests examines a time window (often measured in hours) and returns all requests that have been observed to run longer than @mindur 
seconds between the @start and @end times. This proc can be used to compare between a good and a bad execution of a longer batch process, or to 
identify changes in resource utilization between runs, or determine the wait types common to a given longer-running statement.

Each row in the result set can either be a header row, representing a request, or a detail row representing a statement. (The same statement can 
span rows in some cases, see notes under the @plan attribute). A request in SQL Server is the unique combination of dm_exec_requests.session_id, 
dm_exec_requests.request_id, and dm_exec_requests.start_time. A request (also known as a "batch" in some contexts) can involve one or more statements. 

More info on the result set structure is available in the "columns" help section.
	';
	RAISERROR(@helpstr,10,1);

	IF @Help NOT IN (N'params',N'all')
	BEGIN
		GOTO helpcolumns
	END

helpparams:
	SET @helpstr = N'
Parameters (all string parameters are case-insensitive)
-------------------------------------------------------------------------------------------------------------------------------------------
@start			Valid Values: NULL, any datetime value in the past

				Defines the start time of the time window/range used to pull & display request-related data from the ChiRho database. The 
				time cannot be in the future, and must be < @end. If NULL is passed, the time defaults to 4 hours before the current time 
				[ DATEADD(hour, -4, GETDATE()) ]. If a given request started executing before @start, only its data from @start onward 
				will be included.
	
@end			Valid Values: NULL, any datetime in the past

				Defines the end time of the time window/range used. The time cannot be in the future, and must be > @start. If NULL is 
				passed, the time defaults to 1 second before the current time [ DATEADD(second, -1, GETDATE()) ]. If a given request 
				continued executing after @end, only its data until @end will be included.

@source			Valid Values: "trace" (default), "sv" or "pastsv", "qp" or "pastqp"

				Specifies which subset of data in AutoWho tables to review. AutoWho data is collected through one of three ways: 
				the standard background trace ("trace") which usually executes every 15 seconds all day long; through the 
				sp_XR_SessionViewer procedure ("pastsv") when run with null @start and @end parameters; through the sp_XR_QueryProgress 
				procedure ("pastqp") also when run with null @start/@end. Internally, this data is partitioned based on how the 
				collection in initiated, and this @source parameter allows the user to direct which collection type is reviewed. 
				Most of the time, the background trace data is desired and thus "trace" is appropriate.';
	RAISERROR(@helpstr,10,1);


	SET @helpstr = N'
@units			Valid Values: "m" or "mb" (default), "n" or "native", "p" or "pages"

				Controls the units the following groups of columns: Task TempDB, Session TempDB, Query Memory requested/granted/used,
				physical and logical reads, writes, and transaction log usage.

				Defaults to megabytes. If "pages", the units are in 8kb blocks (the standard SQL Server database page size). If "native", 
				the units are those that come from the DMVs. For logical and physical readers, writes, and TempDB usage, this is 8kb pages. For
				query memory this is kilobytes and for transaction log usage this is bytes.

@mindur			Valid Values: Zero or any positive integer, in seconds (defaults to 120)

				This procedure presents data on requests (a unique session_id, request_id, and dm_exec_requests.start_time). This 
				parameter sets the threshold at which a given request is considered to have executed for a "long" time. Thus, by 
				default, if AutoWho has observed a given request execution duration to be >= 120 seconds for AutoWho collections 
				occurring between @start and @end, that request is considered "long" and all data collected by AutoWho between @start 
				and @end will be taken into account by this procedure.

@dbs			Valid Values: comma-separated list of database names to be included. Defaults to empty string.

				Filters the output to include only requests whose context database ID (from dbo.sysprocesses) is equal to the DBIDs 
				that correspond to the DB names in this list. If a request has multiple context DBIDs, its first one (in the @start/@end 
				range) is the defining context DBID for the complete request.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
@xdbs			Valid Values: comma-separated list of database names to be excluded. Defaults to empty string.

				Filters the output to exclude requests whose initial context DBID (see above note in" @dbs" for how this is defined) 
				matches one of the DBs specified.

@spids			Valid Values: comma-separated list of session IDs to be included. Defaults to empty string.

				Filters the output to include only requests whose SPIDs are in this list. Note that there is a bit of a mismatch, in 
				that the output data is at the request level, but filtering is at the session level. It is currently considered unlikely 
				that a user would want to include requests from one session and exclude other requests from that same session.

@xspids			Valid values: comma-separated list of session IDs to be excluded. Defaults to empty string.

				Filters the output to remove requests whose SPIDs are in this list. See above note (in "@spids") about requests
				versus sessions.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
@attr			Valid values: Y or N (default)

				If Y, a new column named "Plan&Info" is added to the result set. (This column is also added to the output when the 
				@plan parameter is set to "statement".) For header-level rows, this column contains various attributes from the 
				dm_exec_sessions, dm_exec_connections, and dm_exec_requests views.

@plan			Valid values: "n" or "none", "s" or "statement"

				If Y, a new column named "Plan&Info" is added to the result set. (This column is also added to the output when the 
				@attr parameter is set to Y.) For detail-level rows, this column contains the query plan XML for the detail-level row''s 
				statement. 

				NOTE: Because the initial AutoWho capture(s) of a running request can omit the collection of the query plan (depending 
				on the values of the "QueryPlanThreshold" and "QueryPlanThresholdBlockRel" AutoWho options), adding in the plan information 
				can change the granularity of the output. For example, the first observation of a request, when its duration is 2.5 
				seconds, may omit capturing the query plan for that request, while the next observation 15 seconds later will capture it
				(under default config values). Because the output is grouped by both statement and plan identifiers, there will appear to 
				be 2 separate statements (output rows) with the same statement text. This situation does not occur when @plan="N" b/c the 
				plan IDs are set to an irrelevant constant.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
@help			Valid Values: N, params, columns, all, or even gibberish

				If @Help=N''N'', then no help is printed. If =''params'', this section of Help is printed. If =''columns'', the section 
				on result columns is prented. If @Help is passed anything else (even gibberish), it is set to ''all'', and all help 
				content is printed.
	';

	RAISERROR(@helpstr,10,1);

	IF @Help = N'params'
	BEGIN
		GOTO exitloc
	END
	ELSE
	BEGIN
		SET @helpstr = N'
		';
		RAISERROR(@helpstr,10,1);
	END


helpcolumns:

	SET @helpstr = N'
Columns
-------------------------------------------------------------------------------------------------------------------------------------------
SPID			The session ID of the request. Rows for a given request are grouped together, but the overall list of requests is 
				ordered by request start time, then by session id, then by request_id. To simplify the output and aid the user visually, 
				SPID values are only displayed for header-level (request-level) rows, and this column is blank for detail-level 
				(statement-level) rows.

FirstSeen		For header-level rows, the first time (after @start time) the request was seen by the AutoWho collection code. For 
				detail-level rows, the first time (after @start time) the statement was seen by AutoWho. If a request was already executing 
				before @start, any previous collections by AutoWho will not be reflected in this output.

LastSeen		For header-level rows, the last time (before @end time) the request was seen by the AutoWho collection code. For 
				detail-level rows, the last time (after @end time) the statement was seen by AutoWho. If a request was already executing 
				after @end, any later collections by AutoWho will not be reflected in this output.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
Extent(sec)		The time difference, in seconds, between FirstSeen and LastSeen. Note that this is NOT necessarily the duration of the 
				statement for several reasons:
					1) AutoWho polls on intervals (default=15 seconds for the background trace). A query is unlikely to end right after 
						an AutoWho collection and so its duration is almost always longer than seen by AutoWho.
					2) A request executing before @start or after @end will have a duration longer than Last minus First.
					3) The same statement text can be visited multiple times, e.g. inside of a loop or in a sub-proc that is called 
						multiple times.
				Thus, the word choice of "extent" is intentional: the proc merely notes the time gap between the first time the statement 
				was seen and the last. Future versions of this proc may offer the ability to display statement "run-lengths", highlighting 
				when a given statement was seen, then not seen for the same request, then seen again.';
	RAISERROR(@helpstr,10,1);

		SET @helpstr = N'
#Seen			The number of times a given statement was seen within @start and @end for the request. This can assist the user in 
				determining whether a high "Extent(sec)" value represents one instance of a given statement or many return visits to 
				the same statement. A large value in "Extent(sec)" but a lower value in #Seen indicates that the same statement was 
				re-visited a number of times. The collection interval of AutoWho can be of assistance. It is 15 seconds by default, 
				so an "Extent(sec)" of 300 and a "#Seen" value of 20 would indicate that AutoWho had seen this statement every time 
				over a 300 second time interval. (15 seconds multiplied by 4 times-per-minute multiplied by 5 minutes).

DB&Object		For header-level (request-level) rows, indicates the context database for the request. If a request''s context database 
				changes the first-observed context database is presented. For detail-level rows, represents the T-SQL object name (if any) 
				that the statement resides in. This field is blank for ad-hoc SQL.

Cmd				For header-level (request-level) rows, the input buffer of the request. For detail-level rows, the statement text.';
	RAISERROR(@helpstr,10,1);

		SET @helpstr = N'
Statuses		As a request (actually, a task) executes, it alternates between several states: running, runnable, and suspended. This
				field aggregates the various statuses seen for a given statement (no data is presented for header-level rows). The info
				can be used to determine what % of the time a given request is actually executing versus waiting for CPU (runnable) or
				waiting on other SPIDs or environmental factors (suspended).

				Note that suspended task states are divided between suspended-waiting-for-CXPACKET and all other suspended states. This
				enables the user to separate waiting on other sessions/environmental conditions from inter-thread waiting that is somewhat
				inevitable. 

NonCXWaits		The various wait types observed for a given statement are aggregated, along with the observed wait times. All non-CXPACKET
				waits are aggregated under this column. Note that because the underlying data is polling-based, the actual wait-times
				encountered by a given statement may vary. This column is blank for header-level (request-level) rows.

CXWaits			All CXPACKET waits and the sub-waits (e.g. PortOpen on Node 4) are aggregated under this column. This column allows the
				user to see which nodes the CXPACKET waits are occurring on, and to some extent to see whether those CXPACKET waits were
				consumer-side or producer-side.

Plan&Info		For header-level (request-level) rows, provides a clickable-XML value that contains various attributes from dm_exec_sessions,
				dm_exec_connections, and dm_exec_requests. For detail-level (statement-level) rows, provides the query plan in XML form.
				This column is only present when either @attr="Y" or @plan="statement".';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
<resource field groups>
				The following resources are presented in groups: # of tasks, query DOP, CPU, task usage of TempDB, session usage of TempDB,
					query memory requested, query memory granted, query memory used, transaction log usage, logical reads, physical
					reads, and writes.

				IMPORTANT: Some of the resources are used at the query level. (E.g. query memory requests/grants occur at each query).
				Other resources are used/tracked at the request level. (E.g. CPU, reads, writes, and tran log usage). All of these
				resources are shown at the query level because it can be helpful to see how much CPU increases during the execution of
				an individual statement inside of a request/batch, even though the CPU counter represents the total usage by the
				request/batch rather than the statement.

				In fact, as of this release, these resource fields are *only* populated at the statement level rather than the 
				request level. This may be re-evaluated in a future release.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
				Within each group are the following fields:
					"_First" --> The value of the resource on the first observation of this statement (within this request) by AutoWho. 
								For example, if "CPU_First"=2,235, the first time AutoWho observed that statement (within that batch), 
								the dm_exec_requests.cpu counter was 2235.

					"Last" --> The value of the resource on the last observation of this statement within the request.

					"FLDelta" --> Last minus First

					"Min" --> The minimum value for the resource observed by AutoWho for this statement (within this request). 

					"Max" --> You can figure this one out.

					"MMDelta" --> Max minus Min.

					"Avg" --> The average of all observations of the resource for this statement (within this request). 
								
				Not all resource groups have all of the above fields.
					- For Tasks and DOP, both deltas are omitted since the difference is easy to do manually

					- For the resources that are typically ever-increasing, at least for the same statement (CPU, transaction log, 
						logical/physical reads, and writes), average has been omitted as it does not provide clear value.

					- For the query memory groups, "FLDelta" has been omitted since the difference between first and last is not
						terribly meaningful.';
	RAISERROR(@helpstr,10,1);

	SET @helpstr = N'
				In many cases one or more of the resource fields will be blank. This is to eliminate redundant info that crowds the
				results. In these cases, the values of the hidden fields can be inferred. Here is the logic:

				If a resource value stays constant through all observations of a given statement (within its request), the value
				is displayed in the "_First" column and the rest are blank.

				For ever-increasing resources, if first=min and last=max, the "min", "max", and "MMDelta" fields are left blank.
				Normally, we expect the first observation to be the least and the last to be the highest.

				For volatile resources (tempdb, query memory, tasks), as long as the value changed even a bit in any of the observations,
				all columns are displayed.
			';
	RAISERROR(@helpstr,10,1);

exitloc:

	RETURN 0;
END

GO
