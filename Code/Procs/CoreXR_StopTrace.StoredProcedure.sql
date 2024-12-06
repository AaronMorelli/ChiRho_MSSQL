SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.CoreXR_StopTrace
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

	FILE NAME: CoreXR_StopTrace.StoredProcedure.sql

	PROCEDURE NAME: CoreXR_StopTrace

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: This is the "more graceful" way to stop a CoreXR trace (than CoreXR_AbortTrace). @AbortCode
		can be used to show whether the trace was stopped with any sort of problem. 

		@Utility is either "AutoWho" "ServerEye", or "Profiler" at this time. 

		@TraceID cannot be NULL (unlike CoreXR_AbortTrace), since it is assumed that whatever started the trace
		will keep the handle (ID) to that trace until ready to stop that trace.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.CoreXR_StopTrace @Utility=N'AutoWho', @TraceID=5, @AbortCode=N'N'
*/
(
	@Utility		NVARCHAR(20),
	@TraceID		INT,
	@AbortCode		NCHAR(1) = N'N'
)
AS
BEGIN
	DECLARE @RowExists INT,
		@StopTime DATETIME;

	IF @Utility IS NULL
	BEGIN
		RAISERROR('Parameter @Utility cannot be null',16,1);
		RETURN -1;
	END

	IF @TraceID IS NULL
	BEGIN
		RAISERROR('Parameter @TraceID cannot be null',16,1);
		RETURN -1;
	END

	SELECT @RowExists = t.TraceID,
		@StopTime = t.StopTime
	FROM @@CHIRHO_SCHEMA@@.CoreXR_Traces t
	WHERE t.TraceID = @TraceID
	AND t.Utility = @Utility;

	IF @RowExists IS NULL
	BEGIN
		RAISERROR('Parameter value for @TraceID for this value of @Utility not found in the core XR trace table',16,1);
		RETURN -1;
	END

	IF @StopTime IS NOT NULL
	BEGIN
		RAISERROR('Parameter value for @TraceID refers to a trace that has already been stopped.',16,1);
		RETURN -1;
	END
	
	--If we get this far, there is a not-stopped trace.
	UPDATE @@CHIRHO_SCHEMA@@.CoreXR_Traces
	SET StopTime = GETDATE(),
		StopTimeUTC = GETUTCDATE(),
		AbortCode = ISNULL(@AbortCode,N'N')
	WHERE TraceID = @TraceID;

	RETURN 0;
END
GO