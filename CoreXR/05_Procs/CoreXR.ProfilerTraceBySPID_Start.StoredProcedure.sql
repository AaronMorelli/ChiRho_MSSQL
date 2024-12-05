SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CoreXR].[ProfilerTraceBySPID_Start]
/*   
	Copyright 2016 Aaron Morelli

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

	PROJECT NAME: ChiRho https://github.com/AaronMorelli/ChiRho

	PROJECT DESCRIPTION: A T-SQL toolkit for troubleshooting performance and stability problems on SQL Server instances

	FILE NAME: CoreXR.ProfilerTraceBySPID_Start.StoredProcedure.sql

	PROCEDURE NAME: CoreXR.ProfilerTraceBySPID_Start

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Called ad-hoc by users of ChiRho when wanting to trace a specific
		spid. Often useful when inserting the call to this proc (and the associated "End" call)
		into existing app T-SQL code at controlled locations to collect a trace that only
		watches specific statements.

		Note that error handling for this proc is carefully constructed not to raise any
		exceptions, and no transaction management is undertaken. This is to avoid any
		disruption at all to the calling code. The goal is for the calling code to 
		call this proc to start the trace, then call it later to close the trace, and
		otherwise not have to worry about any disruption to its logic.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
--minimal param usage:
DECLARE @lmsg NVARCHAR(MAX);
EXEC [CoreXR].[ProfilerTraceBySPID_Start] @TraceCategories=N'Performance,Stored Procedures', 
												@IncludePerfWarnings=N'Y',
												@SPID=NULL,			--defaults to current SPID
												@Duration=250000,	--250 ms will ignore lots of unimportant statements
												@ReturnMessage=@lmsg OUTPUT
												;
	--get more categories from SELECT DISTINCT category_name FROM CoreXR.ProfilerTraceEvents
	--or can pass "All" to @TraceCategories to choose everything in a given @EventGroup

Then to stop the trace, call:

*/
(
	@TraceFileDirectory		NVARCHAR(210)	= NULL,		--Default to placing this with the SQL black box trace file or the master db (in that order)
	@TraceCategories		NVARCHAR(256)	= N'',		-- a list of categories from CoreXR.ProfilerTraceEvents
	@IncludePerfWarnings	NCHAR(1)		= N'N',		-- Y/N -- if Y, will include the various perf warnings even if the "Errors and Warnings" category is not chosen
	@EventGroup				NVARCHAR(40)	= N'',		-- if NULL or "", defaults to "Default". Otherwise, looks in the CoreXR.ProfilerTraceEvents table to pull that set of events

	--Filters
	@SPID					INT				= NULL,		--Defaults to the current SPID. 0 means no filtering by SPID. Otherwise, must be positive
	@Duration				INT				= NULL,		--If NULL or 0, no filter. Must be positive
	@ObjectIDInclude		NVARCHAR(256)	= N'',		--comma-separated list of object IDs to include. IDs are more performant than object names.
	@ObjectIDExclude		NVARCHAR(256)	= N'',		--comma-separated list of object IDs to exclude.
	@ObjectNameInclude		NVARCHAR(1024)	= N'',		--comma-separated list of object names to include.
	@ObjectNameExclude		NVARCHAR(1024)	= N'',		--comma-separated list of object names to exclude.
	@MaxNestLevel			INT				= 0,		-- Limits events to a nesting level that is <= this #
	@ErrorNumInclude		NVARCHAR(256)	= N'',		--comma-separated list of error #'s to include.
	@ErrorNumExclude		NVARCHAR(256)	= N'',		--comma-separated list of error #'s to exclude.

	@SafetyStop				SMALLINT		= 60,		-- How long (in minutes) to let the trace stay open.
	@TID					INT				= NULL OUTPUT,		--The trace ID
	@ReturnMessage			NVARCHAR(MAX)	= NULL OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

--outer-most exception handling
BEGIN TRY
	DECLARE @ErrorCode INT,
		@TraceFileName NVARCHAR(256),
		@FullPathname NVARCHAR(512),
		@IntendedStopTime DATETIME;

	DECLARE @OIDInclusions TABLE (ObjectID INT);
	DECLARE @OIDExclusions TABLE (ObjectID INT);
	DECLARE @ObjectNameInclusions TABLE (ObjectName NVARCHAR(256));
	DECLARE @ObjectNameExclusions TABLE (ObjectName NVARCHAR(256));
	DECLARE @ErrorNumInclusions TABLE (ErrorNum INT);
	DECLARE @ErrorNumExclusions TABLE (ErrorNum INT);
	DECLARE @TraceCats TABLE (CategoryName NVARCHAR(256));
	DECLARE @IncludedTraceEvents TABLE (trace_event_id INT, event_name NVARCHAR(256));

	IF @SPID IS NULL
	BEGIN
		SET @SPID = @@SPID;
	END

	IF @SPID < 0
	BEGIN
		--We don't raiserror because we don't want to trigger any exceptions in the calling code. 
		--It is the responsibility of the calling code to check for errors
		SET @ReturnMessage = N'The @SPID parameter must be NULL, 0, or a positive integer.';
		SET @ErrorCode = -1;
		RETURN @ErrorCode;
	END

	IF @Duration IS NULL
	BEGIN
		SET @Duration = 0;
	END
	ELSE IF @Duration < 0
	BEGIN
		SET @ReturnMessage = N'The @Duration parameter must be NULL, 0, or a positive integer.';
		SET @ErrorCode = -2;
		RETURN @ErrorCode;
	END

	IF @MaxNestLevel IS NULL
	BEGIN
		SET @MaxNestLevel = 0;
	END
	ELSE IF @MaxNestLevel < 0
	BEGIN
		SET @ReturnMessage = N'The @MaxNestLevel parameter must be NULL, 0, or a positive integer.';
		SET @ErrorCode = -3;
		RETURN @ErrorCode;
	END

	IF @SafetyStop IS NULL
	BEGIN
		SET @SafetyStop = 60
	END
	ELSE IF @SafetyStop < 0
	BEGIN
		SET @ReturnMessage = N'The @SafetyStop parameter must be NULL, 0, or a positive small integer.';
		SET @ErrorCode = -4;
		RETURN @ErrorCode;
	END

	IF @TraceCategories IS NULL
	BEGIN
		SET @ReturnMessage = N'The @TraceCategories parameter cannot be NULL. Choose specific categories from the XR profiler events table, or use "All"';
		SET @ErrorCode = -4;
		RETURN @ErrorCode;
	END
	ELSE
	BEGIN
		SET @TraceCategories = LTRIM(RTRIM(@TraceCategories));
	END

	IF @IncludePerfWarnings IS NULL
	BEGIN
		SET @IncludePerfWarnings = N'';
	END
	ELSE
	BEGIN
		SET @IncludePerfWarnings = UPPER(LTRIM(RTRIM(@IncludePerfWarnings)));
	END

	IF @IncludePerfWarnings NOT IN (N'N', N'Y')
	BEGIN
		SET @ReturnMessage = N'The @IncludePerfWarnings parameter can only be Y or N';
		SET @ErrorCode = -5;
		RETURN @ErrorCode;
	END

	IF @EventGroup IS NULL
	BEGIN
		SET @EventGroup = N'default';
	END
	ELSE
	BEGIN
		SET @EventGroup = LTRIM(RTRIM(@EventGroup));

		IF @EventGroup = N''
		BEGIN
			SET @EventGroup = N'default';
		END
		ELSE
		BEGIN
			IF NOT EXISTS (SELECT * FROM CoreXR.ProfilerTraceEvents p
									WHERE p.EventGroup = @EventGroup COLLATE SQL_Latin1_General_CP1_CI_AS)
			BEGIN
				SET @ReturnMessage = N'@EventGroup must refer to a valid Event Group in the core XR trace events table.';
				SET @ErrorCode = -6;
				RETURN @ErrorCode;
			END
		END
	END

	IF @ObjectIDInclude <> N''
	BEGIN
		BEGIN TRY
			;WITH StringSplitter AS ( 
				SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
				FROM (SELECT LTRIM(RTRIM(ISNULL(@ObjectIDInclude,N''))) as col1) ss1 
			) 
			INSERT INTO @OIDInclusions (ObjectID)
			SELECT DISTINCT SS.oNums
			FROM (
				SELECT CONVERT(INT,LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)')))) AS oNums
				FROM StringSplitter 
				CROSS APPLY Names.nodes('/M') Split(a)
				) SS
			WHERE SS.oNums <> 0;
		END TRY
		BEGIN CATCH
			SET @ReturnMessage = N'The @ObjectIDInclude parameter should be a comma-separated list of numbers representing the only Object IDs that should be in the trace.';
			SET @ErrorCode = -7;
			RETURN @ErrorCode;
		END CATCH
	END

	BEGIN TRY
		;WITH StringSplitter AS ( 
			SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
			FROM (SELECT LTRIM(RTRIM(ISNULL(@ObjectIDExclude,N''))) as col1) ss1 
		) 
		INSERT INTO @OIDExclusions (ObjectID)
		SELECT DISTINCT SS.oNums
		FROM (
			SELECT CONVERT(INT,LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)')))) AS oNums
			FROM StringSplitter 
			CROSS APPLY Names.nodes('/M') Split(a)
			) SS
		WHERE SS.oNums <> 0;
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'The @ObjectIDExclude parameter should be a comma-separated list of numbers representing Object IDs that should NOT be in the trace.';
		SET @ErrorCode = -8;
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY 
		;WITH StringSplitter AS ( 
			SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
			FROM (SELECT LTRIM(RTRIM(ISNULL(@ObjectNameInclude,N''))) as col1) ss1 
		) 
		INSERT INTO @ObjectNameInclusions (ObjectName)
		SELECT DISTINCT SS.oNames
		FROM (SELECT LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)'))) AS oNames
			FROM StringSplitter 
			CROSS APPLY Names.nodes('/M') Split(a)
			) SS
		WHERE SS.oNames <> '';
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'The @ObjectNameInclude parameter should be a comma-separated list of Object names. These objects will be the only objects in the trace.';
		SET @ErrorCode = -9;
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY 
		;WITH StringSplitter AS ( 
			SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
			FROM (SELECT LTRIM(RTRIM(ISNULL(@ObjectNameExclude,N''))) as col1) ss1 
		) 
		INSERT INTO @ObjectNameExclusions (ObjectName)
		SELECT DISTINCT SS.oNames
		FROM (SELECT LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)'))) AS oNames
			FROM StringSplitter 
			CROSS APPLY Names.nodes('/M') Split(a)
			) SS
		WHERE SS.oNames <> '';
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'The @ObjectNameExclude parameter should be a comma-separated list of Object names. These objects will NOT be in the trace.';
		SET @ErrorCode = -10;
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY
		;WITH StringSplitter AS ( 
			SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
			FROM (SELECT LTRIM(RTRIM(ISNULL(@ErrorNumInclude,N''))) as col1) ss1 
		) 
		INSERT INTO @ErrorNumInclusions (ErrorNum)
		SELECT DISTINCT SS.oNums
		FROM (
			SELECT CONVERT(INT,LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)')))) AS oNums
			FROM StringSplitter 
			CROSS APPLY Names.nodes('/M') Split(a)
			) SS
		WHERE SS.oNums <> 0;
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'The @ErrorNumInclude parameter should be a comma-separated list of error numbers to filter by.';
		SET @ErrorCode = -11;
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY
		;WITH StringSplitter AS ( 
			SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
			FROM (SELECT LTRIM(RTRIM(ISNULL(@ErrorNumExclude,N''))) as col1) ss1 
		) 
		INSERT INTO @ErrorNumExclusions (ErrorNum)
		SELECT DISTINCT SS.oNums
		FROM (
			SELECT CONVERT(INT,LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)')))) AS oNums
			FROM StringSplitter 
			CROSS APPLY Names.nodes('/M') Split(a)
			) SS
		WHERE SS.oNums <> 0;
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'The @ErrorNumExclude parameter should be a comma-separated list of error numbers to filter by.';
		SET @ErrorCode = -12;
		RETURN @ErrorCode;
	END CATCH

	IF @TraceCategories <> N'All' COLLATE SQL_Latin1_General_CP1_CI_AS
	BEGIN
		BEGIN TRY 
			;WITH StringSplitter AS ( 
				SELECT CAST('<M>' + REPLACE( col1,  ',' , '</M><M>') + '</M>' AS XML) AS Names 
				FROM (SELECT LTRIM(RTRIM(ISNULL(@TraceCategories,N''))) as col1) ss1 
			) 
			INSERT INTO @TraceCats (CategoryName)
			SELECT DISTINCT SS.oNames
			FROM (SELECT LTRIM(RTRIM(Split.a.value('.', 'NVARCHAR(256)'))) AS oNames
				FROM StringSplitter 
				CROSS APPLY Names.nodes('/M') Split(a)
				) SS
			WHERE SS.oNames <> '';
		END TRY
		BEGIN CATCH
			SET @ReturnMessage = N'The @TraceCategories parameter should be a comma-separated list of category names that are supported by ChiRho.';
			SET @ErrorCode = -13;
			RETURN @ErrorCode;
		END CATCH
	END

	BEGIN TRY
		IF @TraceFileDirectory IS NULL
		BEGIN
			SET @TraceFileDirectory = (
				SELECT tracepath 
				FROM (
					SELECT TOP 1 tracepath 
					FROM (
						SELECT [path] as tracepath, 1 as ordcol
						FROM sys.traces t
						WHERE t.path IS NOT NULL
						--filter down to just the default trace
						AND SUBSTRING(
								REVERSE(
									LTRIM(RTRIM(t.path))
									),
									1, 
									CHARINDEX('\',REVERSE(LTRIM(RTRIM(t.path))) )
							) LIKE '%gol%'

						--fallback is the master DB location
						UNION ALL 

						SELECT mf.physical_name, 2 as ordcol
						FROM sys.master_files mf
						WHERE mf.database_id = 1
						AND mf.file_id = 1
					) ss
					ORDER BY ordcol ASC
				) ss2
			);

			IF @TraceFileDirectory IS NULL
			BEGIN
				SET @ReturnMessage = N'Could not find a valid directory to store the trace file.';
				SET @ErrorCode = -14;
				RETURN @ErrorCode;
			END

			--strip off the file name
			SET @TraceFileDirectory = LTRIM(RTRIM(SUBSTRING(REVERSE(LTRIM(RTRIM(@TraceFileDirectory))), 
				CHARINDEX('\',REVERSE(LTRIM(RTRIM(@TraceFileDirectory)))), LEN(@TraceFileDirectory) )));

			IF SUBSTRING(@TraceFileDirectory,1,1) <> '\'
			BEGIN
				SET @TraceFileDirectory = @TraceFileDirectory + '\';
			END

			SET @TraceFileDirectory = REVERSE(@TraceFileDirectory);
		END 
		ELSE	--the user gave us a directory; add a backslash if necessary
		BEGIN
			SET @TraceFileDirectory = LTRIM(RTRIM(@TraceFileDirectory))

			IF SUBSTRING(REVERSE(@TraceFileDirectory),1,1) <> '\'
			BEGIN
				SET @TraceFileDirectory = @TraceFileDirectory + '\';
			END
		END
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred while obtaining a valid directory for the trace file. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -15;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH


	SET @TraceFileName = 'XRSQLTraceBySPID_' + 
					CONVERT(NVARCHAR(20),@SPID) + '__' + 
					REPLACE(CONVERT(NVARCHAR(30), GETDATE(), 102),'.','_') + '__' + 
					REPLACE(CONVERT(NVARCHAR(30), GETDATE(), 108), ':', '_');
	
	SET @FullPathname = @TraceFileDirectory + @TraceFileName;

	--SELECT * FROM CoreXR.ProfilerTraceEvents
	IF @TraceCategories = N'All' COLLATE SQL_Latin1_General_CP1_CI_AS
	BEGIN
		INSERT INTO @IncludedTraceEvents (
			trace_event_id, event_name
		)
		SELECT trace_event_id, event_name
		FROM CoreXR.ProfilerTraceEvents p
		WHERE p.EventGroup = @EventGroup COLLATE SQL_Latin1_General_CP1_CI_AS
		AND isEnabled = N'Y'
		;
	END
	ELSE
	BEGIN
		IF EXISTS (SELECT * 
					FROM @TraceCats t 
					WHERE NOT EXISTS (
						SELECT * FROM CoreXR.ProfilerTraceEvents p
						WHERE p.category_name = t.CategoryName COLLATE SQL_Latin1_General_CP1_CI_AS
						)
					)
		BEGIN
			SET @ReturnMessage = N'Tracing categories chosen through the @TraceCategories parameter must be supported by ChiRho.';
			SET @ErrorCode = -16;
			RETURN @ErrorCode;
		END

		INSERT INTO @IncludedTraceEvents (
			trace_event_id, event_name
		)
		SELECT trace_event_id, event_name
		FROM CoreXR.ProfilerTraceEvents p
			INNER JOIN @TraceCats c
				ON p.category_name = c.CategoryName COLLATE SQL_Latin1_General_CP1_CI_AS
		WHERE p.EventGroup = @EventGroup COLLATE SQL_Latin1_General_CP1_CI_AS
		AND isEnabled = N'Y'
		;
	END

	--This parameter allows the user to avoid selecting the errors & warnings category
	-- and still get the performance-related warning event
	IF @IncludePerfWarnings = N'Y'
	BEGIN
		INSERT INTO @IncludedTraceEvents (
			trace_event_id, event_name
		)
		SELECT p.trace_event_id, p.event_name
		FROM CoreXR.ProfilerTraceEvents p
		WHERE EventGroup = N'default'			--this EG should always exist
		AND category_name = N'Errors and Warnings'
		AND event_name IN (
			N'Blocked process report', N'Background Job Error',		--auto-stats-async (but I think it occurs on a system spid, so this may be pointless)
			N'CPU threshold exceeded',N'Bitmap Warning', 
			N'Exchange Spill Event',N'Hash Warning',
			N'Missing Column Statistics',N'Missing Join Predicate',N'Sort Warnings'
			)
		AND NOT EXISTS (
			SELECT * 
			FROM @IncludedTraceEvents t
			WHERE t.trace_event_id = p.trace_event_id
		);
	END

	IF NOT EXISTS (SELECT * FROM @IncludedTraceEvents)
	BEGIN
		SET @ReturnMessage = N'No events defined for inclusion in this trace. Exiting...'
		SET @ErrorCode = -17;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END

	DECLARE @CoreXRTraceHandle INT;

	SET @IntendedStopTime = DATEADD(MINUTE, @SafetyStop, GETDATE());
	BEGIN TRY
		EXEC @CoreXRTraceHandle = CoreXR.CreateTrace @Utility='Profiler', @Type='Foreground', 
							@IntendedStopTime=@IntendedStopTime, 
							@Payload_int = @SPID,
							@Payload_nvarchar = @FullPathname;

		IF @CoreXRTraceHandle < 1
		BEGIN
			SET @ReturnMessage = N'Received invalid CoreXR trace handle: ' + ISNULL(CONVERT(NVARCHAR(20),@CoreXRTraceHandle),N'<null>');
			SET @ErrorCode = -17;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
		END
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred while registering this trace with ChiRho. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -18;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	DECLARE @ErrMsg NVARCHAR(MAX);
	DECLARE @rc INT;
	DECLARE @TraceID INT;
	DECLARE @maxfilesize BIGINT=500;
	DECLARE @on BIT=1;

	BEGIN TRY
		EXEC @rc = sp_trace_create @traceid=@TraceID OUTPUT, 
									@options=0, 
									@tracefile=@FullPathname, 
									@maxfilesize=@maxfilesize, 
									@stoptime=@IntendedStopTime;

		IF @TraceID IS NULL
		BEGIN
			SET @ReturnMessage = N'sp_trace_create returned a NULL @traceid return parameter.';
			SET @ErrorCode = -19;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
		END

		IF @TraceID <= 0
		BEGIN
			SET @ReturnMessage = N'sp_trace_create returned a <= 0 @traceid return parameter: ' + CONVERT(NVARCHAR(20),@TraceID);
			SET @ErrorCode = -20;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
		END

		IF ISNULL(@rc,99) > 0
		BEGIN
			SET @ReturnMessage = N'sp_trace_create returned a non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
			SET @ErrorCode = -21;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
		END
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred while creating the SQL trace. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -22;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	DECLARE @curTraceEventID INT,
			@curTraceColumnID INT,
			@curEventName NVARCHAR(128);
	DECLARE @curEventColumns TABLE (trace_event_id INT, trace_column_id INT);

	BEGIN TRY
		DECLARE iterateCurrentEvents CURSOR LOCAL FAST_FORWARD FOR
		SELECT t.trace_event_id, t.event_name
		FROM @IncludedTraceEvents t
		ORDER BY t.trace_event_id
		;

		OPEN iterateCurrentEvents;
		FETCH iterateCurrentEvents INTO @curTraceEventID, @curEventName;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			DELETE FROM @curEventColumns;

			INSERT INTO @curEventColumns 
			(trace_event_id, trace_column_id)
			SELECT teb.trace_event_id, teb.trace_column_id
			FROM sys.trace_event_bindings teb
			WHERE teb.trace_event_id = @curTraceEventID
			;

			DECLARE iterateEventColumns CURSOR LOCAL FAST_FORWARD FOR
			SELECT trace_column_id
			FROM @curEventColumns
			ORDER BY trace_column_id
			;

			OPEN iterateEventColumns;
			FETCH iterateEventColumns INTO @curTraceColumnID;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				EXEC @rc = sp_trace_setevent @TraceID, @curTraceEventID, @curTraceColumnID, @on;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE iterateCurrentEvents;
					DEALLOCATE iterateCurrentEvents;
					SET @ReturnMessage = N'sp_trace_setevent returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -23;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH iterateEventColumns INTO @curTraceColumnID;
			END

			CLOSE iterateEventColumns;
			DEALLOCATE iterateEventColumns;

			FETCH iterateCurrentEvents INTO @curTraceEventID, @curEventName;
		END

		CLOSE iterateCurrentEvents;
		DEALLOCATE iterateCurrentEvents;
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','iterateCurrentEvents')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','iterateCurrentEvents')) > -1
			BEGIN
				CLOSE iterateCurrentEvents
			END
			DEALLOCATE iterateCurrentEvents
		END

		SET @ReturnMessage = N'Unexpected exception occurred while enabling the trace events. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -24;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH


	-- Set the Filters.
	DECLARE @intfilter INT,
			@bigintfilter BIGINT;

	BEGIN TRY
		--First, for SPID
		IF @SPID > 0
		BEGIN
			SET @intfilter = @SPID;
			/* 
				12 is the column to filter, the first 0 means AND (1 would mean OR).
				The 3rd param is the comparison operator:
					0  = (Equal)
					1  <> (Not Equal)
					2  > (Greater Than)
					3  < (Less Than)
					4  >= (Greater Than Or Equal)
					5  <= (Less Than Or Equal)
					6  LIKE
					7  NOT LIKE
			*/
			EXEC @rc = sp_trace_setfilter @TraceID, 
								12,			--column to filter (12 = session_id)
								0,			-- 0 = AND, 1 = OR
								0,			-- what type of comparison
								@intfilter;

			IF ISNULL(@rc,99) <> 0
			BEGIN
				SET @ReturnMessage = N'sp_trace_setfilter (when filtering by SPID) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
				SET @ErrorCode = -25;
				INSERT INTO CoreXR.[Log]
					(LogDT, ErrorCode, LocationTag, LogMessage)
				SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
				RETURN @ErrorCode;
			END

			--if we want to filter out rows that don't tie to a particular SPID, we must filter OUT 
			-- NULL values as per this link: https://msdn.microsoft.com/en-us/library/ms174404.aspx
			/*
			 EXEC sp_trace_setfilter @TraceID, 
									12,		--column to filter (12 = session_id)
									0,		-- 0 = AND, 1 = OR
									1,		-- what type of comparison
									NULL;
			*/
		END
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred while filtering by SPID. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -26;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY
		--Then, for duration
		IF @Duration > 0
		BEGIN
			--13, bigint
			SET @bigintfilter = @Duration;
			EXEC @rc = sp_trace_setfilter @TraceID, 
								13,			--column to filter (13 = duration)
								0,			-- 0 = AND, 1 = OR
								4,			-- what type of comparison: 4 is >=
								@bigintfilter;

			IF ISNULL(@rc,99) <> 0
			BEGIN
				SET @ReturnMessage = N'sp_trace_setfilter (when filtering by duration) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
				SET @ErrorCode = -27;
				INSERT INTO CoreXR.[Log]
					(LogDT, ErrorCode, LocationTag, LogMessage)
				SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
				RETURN @ErrorCode;
			END
		END
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred while filtering by duration. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -28;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY
		--Then, for NestLevel
		IF @MaxNestLevel > 0
		BEGIN
			SET @intfilter = @MaxNestLevel;
			EXEC @rc = sp_trace_setfilter @TraceID, 
						29,			--column to filter (29 = nest_level)
						0,			-- 0 = AND, 1 = OR
						5,			-- what type of comparison: 5 is <=
						@intfilter;

			IF ISNULL(@rc,99) <> 0
			BEGIN
				SET @ReturnMessage = N'sp_trace_setfilter (when filtering by nest level) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
				SET @ErrorCode = -29;
				INSERT INTO CoreXR.[Log]
					(LogDT, ErrorCode, LocationTag, LogMessage)
				SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
				RETURN @ErrorCode;
			END
		END
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred while filtering by nest level. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
			SET @ErrorCode = -30;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
	END CATCH

	--Then, for object ID inclusion/exclusion
	BEGIN TRY
		IF EXISTS (SELECT * FROM @OIDInclusions)
		BEGIN
			DECLARE curs1 CURSOR LOCAL FAST_FORWARD FOR 
			SELECT ObjectID 
			FROM @OIDInclusions;

			OPEN curs1 
			FETCH curs1 INTO @intfilter;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				--add the object id to our inclusion list
				EXEC @rc = sp_trace_setfilter @TraceID, 22, 0, 0, @intfilter;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE curs1;
					DEALLOCATE curs1;
					SET @ReturnMessage = N'sp_trace_setfilter (when filtering by obj id inclusions) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -31;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH curs1 INTO @intfilter;
			END

			CLOSE curs1;
			DEALLOCATE curs1;
		END
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','curs1')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','curs1')) > -1
			BEGIN
				CLOSE curs1
			END
			DEALLOCATE curs1
		END

		SET @ReturnMessage = N'Unexpected exception occurred while filtering by object ID inclusion. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -32;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH


	BEGIN TRY
		IF EXISTS (SELECT * FROM @OIDExclusions)
		BEGIN
			DECLARE curs2 CURSOR LOCAL FAST_FORWARD FOR 
			SELECT ObjectID 
			FROM @OIDExclusions;

			OPEN curs2;
			FETCH curs2 INTO @intfilter;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				--add the object id to our exclusion list
				EXEC @rc = sp_trace_setfilter @TraceID, 22, 0, 1, @intfilter;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE curs2;
					DEALLOCATE curs2;
					SET @ReturnMessage = N'sp_trace_setfilter (when filtering by obj id exclusions) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -33;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH curs2 INTO @intfilter;
			END

			CLOSE curs2;
			DEALLOCATE curs2;
		END	--IF EXISTS (SELECT * FROM @OIDExclusions)
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','curs2')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','curs2')) > -1
			BEGIN
				CLOSE curs2
			END
			DEALLOCATE curs2
		END

		SET @ReturnMessage = N'Unexpected exception occurred while filtering by object ID exclusion. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -34;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	DECLARE @tmpNVC NVARCHAR(512);

	BEGIN TRY
		IF EXISTS (SELECT * FROM @ObjectNameInclusions)
		BEGIN
			DECLARE curs3 CURSOR LOCAL FAST_FORWARD FOR 
			SELECT N'%' + CONVERT(NVARCHAR(512),ObjectName) + N'%'
			FROM @ObjectNameInclusions;

			OPEN curs3;
			FETCH curs3 INTO @tmpNVC;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				--add the object name to our inclusion list
				EXEC @rc = sp_trace_setfilter @TraceID, 34, 0, 6, @tmpNVC;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE curs3;
					DEALLOCATE curs3;
					SET @ReturnMessage = N'sp_trace_setfilter (when filtering by obj name inclusions) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -35;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH curs3 INTO @tmpNVC;
			END

			CLOSE curs3;
			DEALLOCATE curs3;
		END
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','curs3')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','curs3')) > -1
			BEGIN
				CLOSE curs3
			END
			DEALLOCATE curs3
		END

		SET @ReturnMessage = N'Unexpected exception occurred while filtering by object name inclusion. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -36;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY
		IF EXISTS (SELECT * FROM @ObjectNameExclusions)
		BEGIN
			DECLARE curs4 CURSOR LOCAL FAST_FORWARD FOR 
			SELECT N'%' + CONVERT(NVARCHAR(512),ObjectName) + N'%'
			FROM @ObjectNameExclusions;

			OPEN curs4;
			FETCH curs4 INTO @tmpNVC;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				--add the object name to our exclusion list
				EXEC @rc = sp_trace_setfilter @TraceID, 34, 0, 7, @tmpNVC;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE curs4;
					DEALLOCATE curs4;
					SET @ReturnMessage = N'sp_trace_setfilter (when filtering by obj name exclusions) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -37;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH curs4 INTO @tmpNVC;
			END

			CLOSE curs4;
			DEALLOCATE curs4;
		END
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','curs4')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','curs4')) > -1
			BEGIN
				CLOSE curs4
			END
			DEALLOCATE curs4
		END

		SET @ReturnMessage = N'Unexpected exception occurred while filtering by object name exclusion. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -38;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	--Then, for error num inclusion/exclusion
	BEGIN TRY
		IF EXISTS (SELECT * FROM @ErrorNumInclusions)
		BEGIN
			DECLARE curs5 CURSOR LOCAL FAST_FORWARD FOR 
			SELECT ErrorNum
			FROM @ErrorNumInclusions;

			OPEN curs5
			FETCH curs5 INTO @intfilter;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				--add the error # to our inclusion list
				EXEC @rc = sp_trace_setfilter @TraceID, 31, 0, 0, @intfilter;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE curs5;
					DEALLOCATE curs5;
					SET @ReturnMessage = N'sp_trace_setfilter (when filtering by error # inclusion) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -39;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH curs5 INTO @intfilter;
			END

			CLOSE curs5;
			DEALLOCATE curs5;
		END	--IF EXISTS (SELECT * FROM @ErrorNumInclusions)
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','curs5')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','curs5')) > -1
			BEGIN
				CLOSE curs5
			END
			DEALLOCATE curs5
		END

		SET @ReturnMessage = N'Unexpected exception occurred while filtering by error # inclusion. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -40;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	BEGIN TRY
		IF EXISTS (SELECT * FROM @ErrorNumExclusions)
		BEGIN
			DECLARE curs6 CURSOR LOCAL FAST_FORWARD FOR
			SELECT ErrorNum
			FROM @ErrorNumExclusions;

			OPEN curs6;
			FETCH curs6 INTO @intfilter;

			WHILE @@FETCH_STATUS = 0
			BEGIN
				--add the object id to our exclusion list
				EXEC @rc = sp_trace_setfilter @TraceID, 31, 0, 1, @intfilter;

				IF ISNULL(@rc,99) <> 0
				BEGIN
					CLOSE curs5;
					DEALLOCATE curs5;
					SET @ReturnMessage = N'sp_trace_setfilter (when filtering by error # exclusion) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
					SET @ErrorCode = -41;
					INSERT INTO CoreXR.[Log]
						(LogDT, ErrorCode, LocationTag, LogMessage)
					SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
					RETURN @ErrorCode;
				END

				FETCH curs6 INTO @intfilter;
			END

			CLOSE curs6;
			DEALLOCATE curs6;
		END	--IF EXISTS (SELECT * FROM @ErrorNumExclusions)
	END TRY
	BEGIN CATCH
		IF (SELECT CURSOR_STATUS('local','curs6')) >= -1
		BEGIN
			IF (SELECT CURSOR_STATUS('local','curs6')) > -1
			BEGIN
				CLOSE curs6
			END
			DEALLOCATE curs6
		END

		SET @ReturnMessage = N'Unexpected exception occurred while filtering by error # exclusion. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();
		SET @ErrorCode = -42;
		INSERT INTO CoreXR.[Log]
			(LogDT, ErrorCode, LocationTag, LogMessage)
		SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
		RETURN @ErrorCode;
	END CATCH

	-- Set the trace status to start
	BEGIN TRY
		EXEC @rc = sp_trace_setstatus @TraceID, 1;

		IF ISNULL(@rc,99) <> 0
		BEGIN
			SET @ReturnMessage = N'sp_trace_setstatus (when starting the trace) returned non-zero return code: ' + ISNULL(CONVERT(NVARCHAR(20),@rc),N'<null>');
			SET @ErrorCode = -43;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
		END

		IF ISNULL(@TraceID,-99) < 0
		BEGIN
			SET @ReturnMessage = N'Trace handle returned from sp_trace_setstatus is invalid: ' + ISNULL(CONVERT(NVARCHAR(20),@TraceID),N'<null>');
			SET @ErrorCode = -44;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
		END

		SET @TID = @TraceID;

		UPDATE CoreXR.Traces
		SET Payload_bigint = @TraceID,
			Payload_datetime = GETDATE()		--trace create time; can correlate to sys.traces.start_time
		WHERE TraceID = @CoreXRTraceHandle;

		SET @ReturnMessage = N'Trace created successfully.';
		RETURN 0
	END TRY
	BEGIN CATCH
		SET @ReturnMessage = N'Unexpected exception occurred when starting the trace. Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
			CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
			ERROR_MESSAGE();

			SET @ErrorCode = -45;
			INSERT INTO CoreXR.[Log]
				(LogDT, ErrorCode, LocationTag, LogMessage)
			SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
			RETURN @ErrorCode;
	END CATCH
END TRY
BEGIN CATCH
	SET @ReturnMessage = N'Unhandled exception. Error # ' + 
		CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State ' + 
		CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Sev ' + 
		CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; Line ' + 
		CONVERT(NVARCHAR(20),ERROR_LINE()) + N'; Msg ' + 
		ERROR_MESSAGE();
	SET @ErrorCode = -999;
	INSERT INTO CoreXR.[Log]
		(LogDT, ErrorCode, LocationTag, LogMessage)
	SELECT SYSDATETIME(), @ErrorCode, OBJECT_NAME(@@PROCID), @ReturnMessage
	RETURN @ErrorCode;
END CATCH

END 
GO