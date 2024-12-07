SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_PostProcessor
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

	FILE NAME: AutoWho_PostProcessor.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_PostProcessor

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: To reduce the duration of the AutoWho.Collector proc''s duration, a number of advanced features have
		been moved out to a separate procedure that does post-processing of the data collected. This includes:

			- resolving page IDs to object/index names if possible

			- resolving lock waits to their object/index names if possible

			- aggregating NUMA node information for tasks (useful to highlight NUMA node skew)

		The idea is that by moving these more expensive operations out to a separate batch process, we keep
		the Collector fast and also do the above work more efficiently.
	

	FUTURE ENHANCEMENTS: 

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_PostProcessor @optionset='BackgroundTrace', @init=255, 
	@singletimeUTC = NULL, @startUTC=NULL, @endUTC=NULL;	--either singletime or start/end must be provided and valid captures
*/
(
	@optionset		NVARCHAR(50),
	@init			TINYINT,		--which CollectionInitiatorID are we doing this for?
	@singletimeUTC	DATETIME=NULL,	--If provided, these times MUST be UTC times from the
	@startUTC		DATETIME=NULL,	-- @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes or AutoWho.UserCollectionTimes tables.
	@endUTC			DATETIME=NULL	-- Either singletime or start/end must be provided
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @lv__AppLockResource NVARCHAR(100),
			@lv__ProcRC			INT,
			@lv__ExecMode		TINYINT,		--1 singletime; 2 start/end
			@lv__startLocalTime	DATETIME,
			@lv__endLocalTime	DATETIME,
			@err__msg			NVARCHAR(4000),
			@errorloc			NVARCHAR(50),
			@errormsg			NVARCHAR(4000),
			@errorsev			INT,
			@errorstate			INT,
			@scratch__int		INT;

	IF @init NOT IN (255, 1, 2)
	BEGIN
		RAISERROR('Parameter @init must be a valid Collection Initiator ID. (For AutoWho, that is 1, 2, or 255).', 16, 1);
		RETURN -1;
	END

	--Either single-time must be passed in or start/end must be passed in
	IF @singletimeUTC IS NOT NULL
	BEGIN
		IF (@startUTC IS NOT NULL OR @endUTC IS NOT NULL)
		BEGIN
			RAISERROR('Either @singletimeUTC must be provided or @startUTC AND @endUTC must be provided, but not both at the same time', 16, 1);
			RETURN -1;
		END
	END
	ELSE
	BEGIN
		--single-time is NULL. We must have both start and end
		IF @startUTC IS NULL OR @endUTC IS NULL 
		BEGIN
			RAISERROR('If @singletimeUTC is not specified, parameters @startUTC and @endUTC must be non-null and valid datetime values in the past.', 16, 1);
			RETURN -1;
		END

		IF @startUTC >= GETUTCDATE() OR @endUTC >= GETUTCDATE()
		BEGIN
			RAISERROR('Parameters @startUTC and @endUTC must be valid datetime values in the past.', 16, 1);
			RETURN -1;
		END
		
		IF @startUTC >= @endUTC
		BEGIN
			RAISERROR('Parameter @endUTC must be more recent than parameter @startUTC.', 16, 1);
			RETURN -1;
		END
	END
	
	--params are ok, now get our app lock and start doing real work
	SET @lv__AppLockResource = N'AutoWhoPostProcessor' + CONVERT(NVARCHAR(20),@init);

	EXEC @lv__ProcRC = sp_getapplock @Resource=@lv__AppLockResource,
				@LockOwner='Session',
				@LockMode='Exclusive',
				@LockTimeout=5000;

	IF @lv__ProcRC < 0
	BEGIN
		SET @err__msg = N'Unable to obtain exclusive app lock for post-processing.';
		RAISERROR(@err__msg, 16,1);
		RETURN -1;
	END

BEGIN TRY

	IF @singletimeUTC IS NOT NULL
	BEGIN
		--caller wants to process a single time. Set @start and @end to that same time, for both UTC and local time variables
		SET @lv__ExecMode = 1;

		SELECT 
			@lv__startLocalTime = ct.SPIDCaptureTime,
			@lv__endLocalTime = ct.SPIDCaptureTime,
			@startUTC = ct.UTCCaptureTime,
			@endUTC = ct.UTCCaptureTime
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @init 
		AND ct.UTCCaptureTime = @singletimeUTC;

		IF @startUTC IS NULL OR @endUTC IS NULL OR @lv__startLocalTime IS NULL OR @lv__endLocalTime IS NULL
		BEGIN
			EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
			RAISERROR('No AutoWho capture found for the time specified in @singletimeUTC for this @init Collection initiator.', 16, 1);
			RETURN -1;
		END
	END
	ELSE
	BEGIN
		--caller provided a start/end. Grab the local time equivalents and check for NULL to ensure
		--that these times are valid in the @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes table
		SET @lv__ExecMode = 2;

		SELECT 
			@lv__startLocalTime = ct.SPIDCaptureTime
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @init 
		AND ct.UTCCaptureTime = @startUTC;

		SELECT 
			@lv__endLocalTime = ct.SPIDCaptureTime
		FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		WHERE ct.CollectionInitiatorID = @init 
		AND ct.UTCCaptureTime = @endUTC;

		IF @lv__startLocalTime IS NULL OR @lv__endLocalTime IS NULL
		BEGIN
			EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
			RAISERROR('No AutoWho captures found for the time window specified in @startUTC and @endUTC for this @init Collection initiator.', 16, 1);
			RETURN -1;
		END
	END 

	--Ok, if we get here, we know we have a valid start/end range (even if the "range" is a single time).
	--We now call each sub-proc as appropriate based on the options set in AutoWho.Options
	DECLARE 
		@opt__ResolvePageLatches NCHAR(1),
		@opt__ResolveLockWaits	NCHAR(1);

	SET @errorloc = N'Obtain options';
	IF @optionset = N'BackgroundTrace'
	BEGIN
		SELECT 
			@opt__ResolvePageLatches	= [ResolvePageLatches],
			@opt__ResolveLockWaits		= [ResolveLockWaits]
		FROM @@CHIRHO_SCHEMA@@.AutoWho_Options o;
	END
	ELSE
	BEGIN
		SELECT 
			@opt__ResolvePageLatches	= [ResolvePageLatches],
			@opt__ResolveLockWaits		= [ResolveLockWaits]
		FROM @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions o
		WHERE o.OptionSet = @optionset;
	END

	--If this is the background trace we're processing, update the batch and statement stats
	IF @init = 255 AND @lv__ExecMode = 2
	BEGIN
		SET @errorloc = 'Call CalcBatchStmtCaptureTimes';
		BEGIN TRY
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_CalcBatchStmtCaptureTimes @FirstCaptureTimeUTC = @startUTC, @LastCaptureTimeUTC = @endUTC;
		END TRY
		BEGIN CATCH
			--We are going to swallow and log the exception, because there's still value in executing the other Post-processing subprocs
			--(they are largely independent of each other). The sub-proc should have logged its failure reason. We just need
			--to rollback any trans initiated by the sub-proc.
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @errorstate = ERROR_STATE();
			SET @errorsev = ERROR_SEVERITY();

			SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
				N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
				N' Message: ' + ERROR_MESSAGE();

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@errormsg;
		END CATCH
	END

	SET @errorloc = 'Call ResolveNodeStatusInfo';
	BEGIN TRY
		EXEC @@CHIRHO_SCHEMA@@.AutoWho_ResolveNodeStatusInfo @CollectionInitiatorID=@init, @FirstCaptureTimeUTC=@startUTC, @LastCaptureTimeUTC=@endUTC;
	END TRY
	BEGIN CATCH
		--We are going to swallow and log the exception, because there's still value in executing the other Post-processing subprocs
		--(they are largely independent of each other). The sub-proc should have logged its failure reason. We just need
		--to rollback any trans initiated by the sub-proc.
		IF @@TRANCOUNT > 0 ROLLBACK;

		SET @errorstate = ERROR_STATE();
		SET @errorsev = ERROR_SEVERITY();

		SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
			N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
			N' Message: ' + ERROR_MESSAGE();

		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@errormsg;
	END CATCH

	IF @opt__ResolveLockWaits = N'Y' --TODO: should I keep this check? (probably, need to implement logic above for it) AND ISNULL(@InData_NumLocks,0) > 0
	BEGIN
		SET @errorloc = 'Call ResolveLockWaits';
		BEGIN TRY
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_ResolveLockWaits @CollectionInitiatorID=@init, @FirstCaptureTimeUTC=@startUTC, @LastCaptureTimeUTC=@endUTC;
		END TRY
		BEGIN CATCH
			--We are going to swallow the exception, because there's still value in executing the other Post-processing subprocs
			--(they are largely independent of each other). The sub-proc should have logged its failure reason. We just need
			--to rollback any trans initiated by the sub-proc.
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @errorstate = ERROR_STATE();
			SET @errorsev = ERROR_SEVERITY();

			SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
				N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
				N' Message: ' + ERROR_MESSAGE();

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@errormsg;
		END CATCH
	END

	IF IS_SRVROLEMEMBER ('sysadmin') = 1 AND @opt__ResolvePageLatches = N'Y'
		--should I keep this check? (probably, need to implement logic above for it) AND ISNULL(@InData_NumPageLatch,0) > 0
	BEGIN
		SET @errorloc = 'Call ResolvePageLatches';
		BEGIN TRY
			EXEC @@CHIRHO_SCHEMA@@.AutoWho_ResolvePageLatches @CollectionInitiatorID=@init, @FirstCaptureTimeUTC=@startUTC, @LastCaptureTimeUTC=@endUTC;
		END TRY
		BEGIN CATCH
			--We are going to swallow the exception, because there's still value in executing the other Post-processing subprocs
			--(they are largely independent of each other). The sub-proc should have logged its failure reason. We just need
			--to rollback any trans initiated by the sub-proc.
			IF @@TRANCOUNT > 0 ROLLBACK;

			SET @errorstate = ERROR_STATE();
			SET @errorsev = ERROR_SEVERITY();

			SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
				N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
				N' Message: ' + ERROR_MESSAGE();

			EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location=N'CATCH Block', @Message=@errormsg;
		END CATCH
	END

	EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
	RETURN 0;

END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @errormsg = N'Unexpected exception occurred at location ("' + ISNULL(@errorloc,N'<null>') + '"). Error #: ' + CONVERT(NVARCHAR(20),ERROR_NUMBER()) + 
		N' Sev: ' + CONVERT(NVARCHAR(20), ERROR_SEVERITY()) + N' State: ' + CONVERT(NVARCHAR(20), ERROR_STATE()) + 
		N' Message: ' + ERROR_MESSAGE();
	
	IF @init = 255
	BEGIN
		EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='ResolveExcept', @Message=@errormsg;
	END

	--besides the log message, swallow these errors
	--TODO: now that this logic can be called by users, this exception policy
	-- doesn't seem very appropriate. Need to address at some point.
	EXEC sp_releaseapplock @Resource = @lv__AppLockResource, @LockOwner = 'Session';
	RETURN 0;
END CATCH

	RETURN 0;
END
GO
