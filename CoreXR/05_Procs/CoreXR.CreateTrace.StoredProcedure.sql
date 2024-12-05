SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CoreXR].[CreateTrace] 
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

	FILE NAME: CoreXR.CreateTrace.StoredProcedure.sql

	PROCEDURE NAME: CoreXR.CreateTrace

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Creates an entry in the CoreXR.Traces table for the @Utility specified. At this time the
		Traces table is little more than a log table to show when various traces have started or stopped. 

		@Utility is either "AutoWho" or "ServerEye" at this point in time

		@Type is currently always 'Background" for values passed in via the AutoWho or ServerEye Executor).
		The intention with this parameter is to separate background traces (i.e. started by the jobs) with
		traces started by some sort of user-facing procedure. In the future, users may be given an interface
		to start/stop instances of a ServerEye trace that collects some or all of the various system DMVs
		and has a given start/stop time. When the trace is complete, the user would be able to navigate that
		data. The value here would be that the user could set specific start & stop times for the trace
		instead of relying on the intervals present with the standard Background ServerEye trace.

		@IntendedStopTime shows when AutoWho or ServerEye *planned* for the trace to stop. It may have stopped
		a few seconds off from that time, or may be many hours off if a human aborted the trace or something
		went wrong.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC CoreXR.CreateTrace @Utility=N'', @Type=N'', @IntendedStopTime='2016-04-24 23:59'
*/
(
	@Utility			NVARCHAR(20),
	@Type				NVARCHAR(20),
	@IntendedStopTime	DATETIME=NULL,	--If both are specified, UTC takes precedence
	@IntendedStopTimeUTC	DATETIME=NULL, 
	@Payload_int		INT=NULL,
	@Payload_bigint		BIGINT=NULL,
	@Payload_decimal	DECIMAL(28,9)=NULL,
	@Payload_datetime	DATETIME=NULL,
	@Payload_datetimeUTC	DATETIME=NULL,
	@Payload_nvarchar	NVARCHAR(MAX)=NULL
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @LastIdentity INT,
		@Reraise NVARCHAR(4000);

	IF @Utility IS NULL
	BEGIN
		RAISERROR('Parameter @Utility cannot be null',16,1);
		RETURN -1;
	END

	IF @Type IS NULL
	BEGIN
		RAISERROR('Parameter @Type cannot be null',16,1);
		RETURN -1;
	END

	
	IF @IntendedStopTime IS NULL AND @IntendedStopTimeUTC IS NULL
	BEGIN
		RAISERROR('Either @IntendedStopTime or @IntendedStopTimeUTC must be non-NULL.',16,1);
		RETURN -1;
	END
	ELSE
	BEGIN
		--At least 1 of these is non-null.
		--UTC takes precedence, if specified
		IF @IntendedStopTimeUTC IS NOT NULL
		BEGIN
			SET @IntendedStopTime = DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), GETDATE()), @IntendedStopTimeUTC);
		END
		ELSE
		BEGIN
			SET @IntendedStopTimeUTC = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @IntendedStopTime);
		END
	END

	--We do the same thing with the datetime payloads, though both can be null
	IF @Payload_datetimeUTC IS NOT NULL
	BEGIN
		SET @Payload_datetime = DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), GETDATE()), @Payload_datetimeUTC);
	END
	ELSE --UTC payload is NULL
		IF @Payload_datetime IS NOT NULL
	BEGIN
		SET @Payload_datetimeUTC = DATEADD(MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), @Payload_datetime);
	END

	BEGIN TRY
	
		INSERT INTO CoreXR.[Traces]
			([Utility], [Type],  --Take defaults for CreateTime, CreateTimeUTC
				IntendedStopTime, IntendedStopTimeUTC,
				StopTime, StopTimeUTC, AbortCode,
				Payload_int, Payload_bigint, Payload_decimal, Payload_datetime, Payload_datetimeUTC, Payload_nvarchar
			)
		SELECT @Utility,@Type, 
				@IntendedStopTime, @IntendedStopTimeUTC,
				NULL, NULL, NULL,
				@Payload_int, @Payload_bigint, @Payload_decimal, @Payload_datetime, @Payload_datetimeUTC, @Payload_nvarchar;

		SET @LastIdentity = SCOPE_IDENTITY();

		IF @LastIdentity > 0
		BEGIN
			RETURN @LastIdentity;
		END
		ELSE
		BEGIN
			IF @LastIdentity IS NULL
			BEGIN
				RAISERROR('The output of SCOPE_IDENTITY() is NULL', 16, 1);
				RETURN -1;
			END
			ELSE
			BEGIN
				RAISERROR('The output of SCOPE_IDENTITY() is <= 0', 16, 1);
				RETURN -2;
			END
		END
	END TRY
	BEGIN CATCH
		SET @Reraise = N'Unexpected error occurred while inserting an new trace record into the trace table: Error # ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; Severity: ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + '; State: ' + 
			CONVERT(NVARCHAR(20),ERROR_STATE()) + '; Message: '+ ERROR_MESSAGE();

		RAISERROR(@Reraise, 16, 1);
		RETURN -3;
	END CATCH

	RETURN 0;		--should never hit this
END

GO
