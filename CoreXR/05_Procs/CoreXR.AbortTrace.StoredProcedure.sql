SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CoreXR].[AbortTrace] 
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

	FILE NAME: CoreXR.AbortTrace.StoredProcedure.sql

	PROCEDURE NAME: CoreXR.AbortTrace

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Provides an interface for humans or programs to stop an AutoWho or ServerEye trace. 

	@Utility is either AutoWho or ServerEye at this time. "Profiler" traces do not abort

	@TraceID is the ID # of the trace, or if NULL, the MAX(ID) from the trace table for the Utility value, which
		is likely to be the current trace.

	@PreventAllDay: if "N", aborts the currently-running trace but does not prevent the trace from being started
		up again (e.g. 15 min later by the "Every 15 Minute" Master job). If "Y", places a row into
		a signal table (e.g. AutoWho.SignalTable or ServerEye.SignalTable) that indicates that the trace
		should not be started up for the rest of the calendar day. 

	OUTSTANDING ISSUES: 
		@PreventAllDay works for the rest of the day, and thus prevents a trace with day boundaries (the default) 
		from starting up. When the next day arrives at midnight, that signal row becomes irrelevant. However,
		the AutoWho and ServerEye traces can be configured to span a day (e.g. 4pm to 3:59am), and in that case,
		the signal that is entered won't stop such a trace from starting back up at 12:00am. 

To Execute
------------------------
EXEC CoreXR.AbortTrace @Utility=N'AutoWho', @TraceID=NULL, @PreventAllDay=N'N'
*/
(
	@Utility		NVARCHAR(20),
	@TraceID		INT=NULL, 
	@AbortCode		NCHAR(1),
	@PreventAllDay	NCHAR(1) = N'N'
)
AS
BEGIN
	DECLARE @RowExists INT,
		@StopTime DATETIME;

	IF @Utility IS NULL
	BEGIN
		RAISERROR('Parameter @Utility cannot be NULL',16,1);
		RETURN -1;
	END

	IF @AbortCode IS NULL
	BEGIN
		RAISERROR('Parameter @AbortCode cannot be NULL',16,1);
		RETURN -1;
	END

	IF @TraceID IS NULL
	BEGIN
		--Just go get the most recent one
		SELECT 
			@RowExists = ss.TraceID,
			@StopTime = ss.StopTime 
		FROM (
			SELECT TOP 1 t.TraceID, t.StopTime
			FROM CoreXR.[Traces] t WITH (NOLOCK)
			WHERE Utility = @Utility
			ORDER BY t.TraceID DESC
		) ss
	END
	ELSE
	BEGIN
		SELECT @RowExists = t.TraceID,
			@StopTime = t.StopTime
		FROM CoreXR.[Traces] t WITH (NOLOCK)
		WHERE Utility = @Utility
		AND t.TraceID = @TraceID;
	END

	IF @RowExists IS NULL
	BEGIN
		RAISERROR('Parameter value for @TraceID not found or no traces exist in the trace table for the @Utility specified',16,1);
		RETURN -1;
	END

	IF @StopTime IS NOT NULL
	BEGIN
		RAISERROR('Parameter value for @TraceID refers to a trace that has already been stopped.',16,1);
		RETURN -1;
	END

	--If we get this far, we have a trace that has not been stopped. Let's stop it
	UPDATE CoreXR.Traces
	SET StopTime = GETDATE(),
		StopTimeUTC = GETUTCDATE(),
		AbortCode = @AbortCode
	WHERE TraceID = @RowExists
	
	IF @Utility = N'AutoWho'
	BEGIN 
		IF UPPER(ISNULL(@PreventAllDay,N'Z')) NOT IN (N'N',N'Y')
		BEGIN
			RAISERROR('Parameter @PreventAllDay must be either "N" or "Y"', 16, 1);
			RETURN -1;
		END

		DELETE FROM AutoWho.SignalTable
		WHERE SignalName = N'AbortTrace' ;

		IF UPPER(@PreventAllDay) = N'N'
		BEGIN
			INSERT INTO AutoWho.SignalTable 
			(SignalName, SignalValue, InsertTime, InsertTimeUTC)
			VALUES (N'AbortTrace', N'OneTime', GETDATE(), GETUTCDATE());	-- N'OneTime' --> the Wrapper proc, when it sees this row for the same day,
																-- will abort the loop early and then delete this row so that
																-- the next time it starts it will continue to run
		END
		ELSE
		BEGIN
			INSERT INTO AutoWho.SignalTable 
				(SignalName, SignalValue, InsertTime, InsertTimeUTC)
			VALUES (N'AbortTrace', N'AllDay', GETDATE(), GETUTCDATE());		-- N'AllDay' --> the Wrapper proc, when it sees this row for the same day,
																-- will abort the loop early, but wil NOT delete this row. Thus, 
																-- that row will prevent this wrapper proc from running the rest of the day
		END
	END

	IF @Utility = N'ServerEye'
	BEGIN 
		IF UPPER(ISNULL(@PreventAllDay,N'Z')) NOT IN (N'N',N'Y')
		BEGIN
			RAISERROR('Parameter @PreventAllDay must be either "N" or "Y"', 16, 1);
			RETURN -1;
		END

		DELETE FROM ServerEye.SignalTable
		WHERE SignalName = N'AbortTrace' ;

		IF UPPER(@PreventAllDay) = N'N'
		BEGIN
			INSERT INTO ServerEye.SignalTable 
			(SignalName, SignalValue, InsertTime, InsertTimeUTC)
			VALUES (N'AbortTrace', N'OneTime', GETDATE(), GETUTCDATE());	-- N'OneTime' --> the Wrapper proc, when it sees this row for the same day,
																-- will abort the loop early and then delete this row so that
																-- the next time it starts it will continue to run
		END
		ELSE
		BEGIN
			INSERT INTO ServerEye.SignalTable 
				(SignalName, SignalValue, InsertTime, InsertTimeUTC)
			VALUES (N'AbortTrace', N'AllDay', GETDATE(), GETUTCDATE());		-- N'AllDay' --> the Wrapper proc, when it sees this row for the same day,
																-- will abort the loop early, but wil NOT delete this row. Thus, 
																-- that row will prevent this wrapper proc from running the rest of the day
		END
	END

	--as other utilities are added, their "Abort Trace" logic goes here

	RETURN 0;
END


GO
