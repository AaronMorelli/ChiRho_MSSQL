SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[CollectorLowFreqRingBuffer]
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

	FILE NAME: ServerEye.CollectorLowFreqRingBuffer.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.CollectorLowFreqRingBuffer

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs underneath the low-frequency collection proc and pulls various ring buffer data.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------

*/
(
	@init				TINYINT,
	@LocalCaptureTime	DATETIME, 
	@UTCCaptureTime		DATETIME,
	@SQLServerStartTime DATETIME
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @errorloc NVARCHAR(100),
			@err__ErrorSeverity INT, 
			@err__ErrorState INT, 
			@err__ErrorText NVARCHAR(4000),
			@lv__AllRBsSuccessful INT,
			@lv__scratchint INT;

BEGIN TRY
	/* TODOs
			There's a DELETE below that removes any ring buffers not in an IN-list. That DELETE is 
			temporary as I implement the various ring buffers that I actually want to persist. It
			allows the #RingBufferTempContents to just hold ring buffers that the below code
			already handles.

	*/

	SET @lv__AllRBsSuccessful = 1;		--start assuming things will work

	IF OBJECT_ID('tempdb..#RingBufferTempContents') IS NOT NULL DROP TABLE #RingBufferTempContents;
	CREATE TABLE #RingBufferTempContents (
		ring_buffer_address varbinary(8) NOT NULL, 
		ring_buffer_type nvarchar(60) NOT NULL, 
		timestamp bigint not null, 
		record nvarchar(3072) null
	);


	INSERT INTO #RingBufferTempContents (
		ring_buffer_address,	--don't need this for anything, AFAIK
		ring_buffer_type,
		timestamp,
		record
	)
	SELECT rb.ring_buffer_address, rb.ring_buffer_type, rb.timestamp, rb.record
	FROM ServerEye.RingBufferProgress rbp
		RIGHT OUTER hash JOIN
		sys.dm_os_ring_buffers rb
			ON rbp.ring_buffer_type = rb.ring_buffer_type
	WHERE 
		--if a totally new ring buffer (i.e. isn't in the RingBufferProgress table, which is pre-populated when the 
		-- Executor is starting up), then save it off so we can post process this unknown/new type.
		rbp.ring_buffer_type IS NULL 
		OR (
			rbp.ring_buffer_type IS NOT NULL 

			/* This deserves some explaining: 
				the "timestamp" field in dm_os_ring_buffers is NOT unique per ring_buffer_type; in fact, there are 
				often duplicates. This means, of course that multiple entries for a ring buffer can occur for the same
				timestamp value. The unique identifier is the RecordID value. However, RecordID is the XML, and parsing
				the XML is expensive. Thus, we use a hack to maintain efficiency while also giving a reasonable effort
				to only eliminate records we've already processed. We basically throw away ring buffer entries 
				whose timestamp is less than *last max timestamp processed - 5 seconds*. The 5 second buffer means
				that if our last captured managed to capture some ring buffer entries for a given timestamp but other
				entries for that timestamp were still being written to the ring buffer (i.e. were not captured by us),
				then we are likely to captured them in the next run.

				The actual persist to the permanent table uses RecordID to weed out things we've already persisted, of course.
			*/
			AND rb.timestamp > (rbp.max_timestamp_processed - 5000)	

			--certain RBs just aren't very interesting (too geeky or data is better-accessible from a DMV now)
			AND rb.ring_buffer_type NOT IN (N'RING_BUFFER_HOBT_SCHEMAMGR', 
				N'RING_BUFFER_MEMORY_BROKER_CLERKS', N'RING_BUFFER_XE_BUFFER_STATE',
				N'RING_BUFFER_SCHEDULER')
		)
	OPTION(FORCE ORDER);


	/* RING_BUFFER_SCHEDULER_MONITOR
		This is the only format I've seen. Useful data!

		<Record id = "2333" type ="RING_BUFFER_SCHEDULER_MONITOR" time ="438203849">
			<SchedulerMonitorEvent>
				<SystemHealth>
					<ProcessUtilization>0</ProcessUtilization>
					<SystemIdle>96</SystemIdle>
					<UserModeTime>0</UserModeTime>
					<KernelModeTime>0</KernelModeTime>
					<PageFaults>69</PageFaults>
					<WorkingSetDelta>0</WorkingSetDelta>
					<MemoryUtilization>100</MemoryUtilization>
				</SystemHealth>
			</SchedulerMonitorEvent>
		</Record>
	*/
		--we do this before each collection, as it makes our timestamp processing more accurate
	DECLARE @cpu_ticks BIGINT, 
			@ms_ticks BIGINT;
	SELECT 
		@cpu_ticks = i.cpu_ticks,
		@ms_ticks = i.ms_ticks
	FROM sys.dm_os_sys_info i;

	BEGIN TRY
		INSERT INTO ServerEye.RingBufferSchedulerMonitor (
			SQLServerStartTime, 
			RecordID,
			[timestamp],
			ExceptionTime,
			UTCCaptureTime,
			LocalCaptureTime,
			ProcessUtilization,
			SystemIdle,
			UserModeTime,
			KernelModeTime,
			PageFaults,
			WorkingSetDelta,
			MemoryUtilization
		)
		SELECT 
			@SQLServerStartTime,
			RecordID, 
			ss1.timestamp,
			ExceptionTime,
			@UTCCaptureTime,
			@LocalCaptureTime,
			ProcessUtilization,
			SystemIdle,
			UserModeTime,
			KernelModeTime,
			PageFaults,
			WorkingSetDelta,
			MemoryUtilization
		FROM (
			SELECT 
				[RecordID] = recordXML.value('(./Record/@id)[1]', 'int'),
				ss0.timestamp,
				--Got this calculation from Jonathan Kehayias
				--https://www.sqlskills.com/blogs/jonathan/identifying-external-memory-pressure-with-dm_os_ring_buffers-and-ring_buffer_resource_monitor/
				ExceptionTime = DATEADD (ss, (-1 * ((@cpu_ticks / CONVERT (float, ( @cpu_ticks / @ms_ticks ))) - ss0.timestamp)/1000), GETDATE()),

				[ProcessUtilization] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int'),
				[SystemIdle] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'),
				[UserModeTime] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/UserModeTime)[1]', 'int'),
				[KernelModeTime] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/KernelModeTime)[1]', 'int'),
				[PageFaults] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/PageFaults)[1]', 'int'),
				[WorkingSetDelta] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/WorkingSetDelta)[1]', 'int'),
				[MemoryUtilization] = recordXML.value('(./Record/SchedulerMonitorEvent/SystemHealth/MemoryUtilization)[1]', 'int')
			FROM (
				SELECT rb.timestamp,
					CONVERT(XML,rb.record) as recordXML
				FROM #RingBufferTempContents rb
				WHERE rb.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
			) ss0
		) ss1
		WHERE NOT EXISTS (
			SELECT *
			FROM ServerEye.RingBufferSchedulerMonitor e
			WHERE e.SQLServerStartTime = @SQLServerStartTime
			AND ss1.RecordID = e.RecordID
		);
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		SET @lv__AllRBsSuccessful = 0;

		--save off our problematic data for later analysis
		INSERT INTO ServerEye.RingBufferCausedExceptions (
			UTCCaptureTime,
			LocalCaptureTime,
			ring_buffer_address,
			ring_buffer_type,
			timestamp,
			record
		)
		SELECT @UTCCaptureTime,
			@LocalCaptureTime,
			t.ring_buffer_address, 
			t.ring_buffer_type, 
			t.timestamp,
			t.record
		FROM #RingBufferTempContents t
		WHERE t.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR';

		SET @err__ErrorSeverity = ERROR_SEVERITY();
		SET @err__ErrorState = ERROR_STATE();
		SET @err__ErrorText = N'Error occurred during processing of RING_BUFFER_SCHEDULER_MONITOR. Error #: ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='SchedMonRB', @Message=@err__ErrorText;
		--we log the message, but we don't re-raise the exception. 
	END CATCH

	--Regardless of whether this capture was successful, we update the high watermark. If an exception
	--occurred, we don't want the next run to encounter the same exception.
	UPDATE targ 
	SET targ.max_timestamp_processed = ISNULL(ss.max_timestamp, targ.max_timestamp_processed)
	FROM ServerEye.RingBufferProgress targ 
		LEFT OUTER JOIN (
			SELECT MAX(t.timestamp) as max_timestamp
			FROM #RingBufferTempContents t
			WHERE t.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
			) ss
				ON 1=1
	WHERE targ.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR';


	/* RING_BUFFER_EXCEPTION
		Basic structure (haven't seen significant variance yet)

			<Record id = "1751" type ="RING_BUFFER_EXCEPTION" time ="3081238494">

				<Exception>
					<Task address="0x000000165675D088"></Task>
					<Error>1222</Error>
					<Severity>16</Severity>
					<State>18</State>
					<UserDefined>0</UserDefined>
					<Origin>1</Origin>
				</Exception>
	
				<Stack>
					<frame id = "0">0X00007FFD10A1BE4A</frame>
					... etc
				</Stack>
			</Record>
	*/
	SELECT 
		@cpu_ticks = i.cpu_ticks,
		@ms_ticks = i.ms_ticks
	FROM sys.dm_os_sys_info i;

	--Instead of inserting directly into the ServerEye.RingBufferException table, we insert into a temp table
	--so that we can break the data out into dims and facts. This helps to keep the footprint smaller in the event
	--of a flood of exceptions.
	IF OBJECT_ID('tempdb..#RingBufferException') IS NOT NULL DROP TABLE #RingBufferException;
	CREATE TABLE #RingBufferException (
		[RecordID]		[bigint] NOT NULL,
		[timestamp]		[bigint] NOT NULL,
		[ExceptionTime] [datetime] NOT NULL,
		[Error]			[int] NULL,
		[Severity]		[int] NULL,
		[State]			[int] NULL,
		[UserDefined]	[int] NULL,
		[Origin]		[int] NULL
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #RingBufferException(RecordID);

	BEGIN TRY
		INSERT INTO #RingBufferException (
			[RecordID],
			[timestamp],
			[ExceptionTime],
			[Error],
			[Severity],
			[State],
			[UserDefined],
			[Origin]
		)
		SELECT 
			RecordID, 
			ss1.timestamp,
			ExceptionTime,
			Error, 
			Severity, 
			ss1.State, 
			UserDefined, 
			Origin
		FROM (
			SELECT 
				[RecordID] = recordXML.value('(./Record/@id)[1]', 'int'),
				ss0.timestamp,
				--Got this calculation from Jonathan Kehayias
				--https://www.sqlskills.com/blogs/jonathan/identifying-external-memory-pressure-with-dm_os_ring_buffers-and-ring_buffer_resource_monitor/
				ExceptionTime = DATEADD (ss, 
											(-1 * (
													(@cpu_ticks / CONVERT (float, ( @cpu_ticks / @ms_ticks ))) 
													- ss0.timestamp
												  )/1000
											), 
											GETDATE()
										),

				[Error] = recordXML.value('(./Record/Exception/Error)[1]', 'int'),
				[Severity] = recordXML.value('(./Record/Exception/Severity)[1]', 'int'),
				[State] = recordXML.value('(./Record/Exception/State)[1]', 'int'),
				[UserDefined] = recordXML.value('(./Record/Exception/UserDefined)[1]', 'int'),
				[Origin] = recordXML.value('(./Record/Exception/Origin)[1]', 'int')
			FROM (
				SELECT rb.timestamp,
					CONVERT(XML,rb.record) as recordXML
				FROM #RingBufferTempContents rb
				WHERE rb.ring_buffer_type = N'RING_BUFFER_EXCEPTION'
			) ss0
		) ss1;

		SET @lv__scratchint = ROWCOUNT_BIG();

		IF @lv__scratchint > 0
		BEGIN
			--Insert new dims, if any
			INSERT INTO [ServerEye].[DimRBException](
				[Error],
				[Severity],
				[State],
				[UserDefined],
				[Origin],
				[TimeAdded],
				[TimeAddedUTC]
			)
			SELECT 
				[Error],
				[Severity],
				[State],
				[UserDefined],
				[Origin],
				GETDATE(),
				GETUTCDATE()
			FROM (
				SELECT DISTINCT 
					[Error] = ISNULL(t.Error,-555),
					[Severity] = ISNULL(t.Severity,-555),
					[State] = ISNULL(t.State,-555),
					[UserDefined] = ISNULL(t.UserDefined,-555),
					[Origin] = ISNULL(t.Origin,-555)
				FROM #RingBufferException t
			) ss
			WHERE NOT EXISTS (
				SELECT *
				FROM ServerEye.DimRBException dime
				WHERE ss.[Error] = dime.[Error]
				AND ss.[Severity] = dime.[Severity]
				AND ss.[State] = dime.[State]
				AND ss.[UserDefined] = dime.[UserDefined]
				AND ss.[Origin] = dime.[Origin]
			);

			--Now, insert new facts
			INSERT INTO [ServerEye].[RingBufferException](
				[SQLServerStartTime],
				[RecordID],
				[UTCCaptureTime],
				[DimRBExceptionID],
				[timestamp],
				[ExceptionTime]
			)
			SELECT 
				@SQLServerStartTime,
				t.RecordID,
				@UTCCaptureTime,
				d.DimRBExceptionID,
				t.timestamp,
				t.ExceptionTime
			FROM #RingBufferException t
				INNER JOIN [ServerEye].[DimRBException] d
					ON t.[Error] = d.[Error]
					AND t.[Severity] = d.[Severity]
					AND t.[State] = d.[State]
					AND t.[UserDefined] = d.[UserDefined]
					AND t.[Origin] = d.[Origin]
			WHERE NOT EXISTS (
				SELECT *
				FROM ServerEye.RingBufferException e
				WHERE e.SQLServerStartTime = @SQLServerStartTime
				AND e.RecordID = t.RecordID
			);
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		SET @lv__AllRBsSuccessful = 0;

		--save off our problematic data for later analysis
		INSERT INTO ServerEye.RingBufferCausedExceptions (
			UTCCaptureTime,
			LocalCaptureTime,
			ring_buffer_address,
			ring_buffer_type,
			timestamp,
			record
		)
		SELECT @UTCCaptureTime,
			@LocalCaptureTime,
			t.ring_buffer_address, 
			t.ring_buffer_type, 
			t.timestamp,
			t.record
		FROM #RingBufferTempContents t
		WHERE t.ring_buffer_type = N'RING_BUFFER_EXCEPTION';

		SET @err__ErrorSeverity = ERROR_SEVERITY();
		SET @err__ErrorState = ERROR_STATE();
		SET @err__ErrorText = N'Error occurred during processing of RING_BUFFER_EXCEPTION. Error #: ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

		--we log the message, but we don't re-raise the exception. 
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='RBException', @Message=@err__ErrorText;
	END CATCH


	UPDATE targ 
	SET targ.max_timestamp_processed = ISNULL(ss.max_timestamp, targ.max_timestamp_processed)
	FROM ServerEye.RingBufferProgress targ 
		LEFT OUTER JOIN (
			SELECT MAX(t.timestamp) as max_timestamp
			FROM #RingBufferTempContents t
			WHERE t.ring_buffer_type = N'RING_BUFFER_EXCEPTION'
			) ss
				ON 1=1
	WHERE targ.ring_buffer_type = N'RING_BUFFER_EXCEPTION';



	/* RING_BUFFER_SECURITY_ERROR
	
		Basic structure (haven't seen significant variance yet)

		<Record id = "61" type ="RING_BUFFER_SECURITY_ERROR" time ="3039605062">
			<Error>
				<SPID>299</SPID>
				<APIName>ImpersonateSecurityContext</APIName>
				<CallingAPIName>NLShimImpersonate</CallingAPIName>
				<ErrorCode>0x139F</ErrorCode>
				<SQLErrorCode>x_cse_Success</SQLErrorCode>
			</Error>
	
			<Stack>
				<frame id = "0">0X00007FFD119B532E</frame>
				...etc
			</Stack>
		</Record>

		http://i1.blogs.msdn.com/b/psssql/archive/2008/03/24/how-it-works-sql-server-2005-sp2-security-ring-buffer-ring-buffer-security-error.aspx
	*/
	IF OBJECT_ID('tempdb..#RingBufferSecurityError') IS NOT NULL DROP TABLE #RingBufferSecurityError;
	CREATE TABLE #RingBufferSecurityError(
		[RecordID] [bigint] NOT NULL,
		[timestamp] [bigint] NOT NULL,
		[ExceptionTime] [datetime] NOT NULL,
		[SPID] [int] NULL,
		[APIName] [nvarchar](512) NULL,
		[CallingAPIName] [nvarchar](512) NULL,
		[ErrorCode] [nvarchar](60) NULL,
		[SQLErrorCode] [nvarchar](60) NULL
	);
	CREATE UNIQUE CLUSTERED INDEX CL1 ON #RingBufferSecurityError(RecordID);

	SELECT 
		@cpu_ticks = i.cpu_ticks,
		@ms_ticks = i.ms_ticks
	FROM sys.dm_os_sys_info i;

	BEGIN TRY
		INSERT INTO #RingBufferSecurityError (
			RecordID,
			timestamp,
			ExceptionTime,
			SPID, 
			APIName,
			CallingAPIName, 
			ErrorCode,
			SQLErrorCode
		)
		SELECT 
			RecordID, 
			ss1.timestamp,
			ExceptionTime,
			SPID, 
			APIName, 
			CallingAPIName, 
			ErrorCode, 
			SQLErrorCode
		FROM (
			SELECT 
				[RecordID] = recordXML.value('(./Record/@id)[1]', 'int'),
				ss0.timestamp,
				--Got this calculation from Jonathan Kehayias
				--https://www.sqlskills.com/blogs/jonathan/identifying-external-memory-pressure-with-dm_os_ring_buffers-and-ring_buffer_resource_monitor/
				ExceptionTime = DATEADD (ss, (-1 * ((@cpu_ticks / CONVERT (float, ( @cpu_ticks / @ms_ticks ))) - ss0.timestamp)/1000), GETDATE()),

				[SPID] = recordXML.value('(./Record/Error/SPID)[1]', 'int'),
				[APIName] = recordXML.value('(./Record/Error/APIName)[1]', 'nvarchar(512)'),
				[CallingAPIName] = recordXML.value('(./Record/Error/CallingAPIName)[1]', 'nvarchar(512)'),
				[ErrorCode] = recordXML.value('(./Record/Error/ErrorCode)[1]', 'nvarchar(60)'),
				[SQLErrorCode] = recordXML.value('(./Record/Error/SQLErrorCode)[1]', 'nvarchar(60)')
			FROM (
				SELECT rb.timestamp,
					CONVERT(XML,rb.record) as recordXML
				FROM #RingBufferTempContents rb
				WHERE rb.ring_buffer_type = N'RING_BUFFER_SECURITY_ERROR'
			) ss0
		) ss1;

		SET @lv__scratchint = ROWCOUNT_BIG();

		IF @lv__scratchint > 0
		BEGIN
			--insert new dims, if any
			INSERT INTO [ServerEye].[DimRBSecurityError](
				[APIName],
				[CallingAPIName],
				[ErrorCode],
				[SQLErrorCode],
				[TimeAdded],
				[TimeAddedUTC]
			)
			SELECT 
				ss.APIName,
				ss.CallingAPIName,
				ss.ErrorCode,
				ss.SQLErrorCode,
				GETDATE(),
				GETUTCDATE()
			FROM (
				SELECT DISTINCT
					[APIName] = ISNULL(t.APIName,N'<null>'),
					[CallingAPIName] = ISNULL(t.CallingAPIName,N'<null>'),
					[ErrorCode] = ISNULL(t.ErrorCode,N'<null>'),
					[SQLErrorCode] = ISNULL(t.SQLErrorCode,N'<null>')
				FROM #RingBufferSecurityError t
			) ss
			WHERE NOT EXISTS (
				SELECT * 
				FROM [ServerEye].[DimRBSecurityError] d
				WHERE d.APIName = ss.APIName 
				AND d.CallingAPIName = ss.CallingAPIName
				AND d.ErrorCode = ss.ErrorCode 
				AND d.SQLErrorCode = ss.SQLErrorCode
			);

			--Insert facts
			INSERT INTO [ServerEye].[RingBufferSecurityError](
				[SQLServerStartTime],
				[RecordID],
				[timestamp],
				[ExceptionTime],
				[UTCCaptureTime],
				[DimRBExceptionID],
				[SPID]
			)
			SELECT 
				@SQLServerStartTime,
				f.RecordID,
				f.timestamp,
				f.ExceptionTime,
				@UTCCaptureTime,
				d.DimRBExceptionID,
				f.SPID
			FROM #RingBufferSecurityError f
				INNER JOIN [ServerEye].[DimRBSecurityError] d
					ON d.APIName = f.APIName 
					AND d.CallingAPIName = f.CallingAPIName
					AND d.ErrorCode = f.ErrorCode 
					AND d.SQLErrorCode = f.SQLErrorCode
			WHERE NOT EXISTS (
				SELECT *
				FROM ServerEye.RingBufferSecurityError e
				WHERE e.SQLServerStartTime = @SQLServerStartTime
				AND e.RecordID = f.RecordID
			);
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		SET @lv__AllRBsSuccessful = 0;

		--save off our problematic data for later analysis
		INSERT INTO ServerEye.RingBufferCausedExceptions (
			UTCCaptureTime,
			LocalCaptureTime,
			ring_buffer_address,
			ring_buffer_type,
			timestamp,
			record
		)
		SELECT @UTCCaptureTime,
			@LocalCaptureTime,
			t.ring_buffer_address, 
			t.ring_buffer_type, 
			t.timestamp,
			t.record
		FROM #RingBufferTempContents t
		WHERE t.ring_buffer_type = N'RING_BUFFER_SECURITY_ERROR';

		SET @err__ErrorSeverity = ERROR_SEVERITY();
		SET @err__ErrorState = ERROR_STATE();
		SET @err__ErrorText = N'Error occurred during processing of RING_BUFFER_SECURITY_ERROR. Error #: ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

		--we log the message, but we don't re-raise the exception. 
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='RBSecError', @Message=@err__ErrorText;
	END CATCH



	UPDATE targ 
	SET targ.max_timestamp_processed = ISNULL(ss.max_timestamp, targ.max_timestamp_processed)
	FROM ServerEye.RingBufferProgress targ 
		LEFT OUTER JOIN (
			SELECT MAX(t.timestamp) as max_timestamp
			FROM #RingBufferTempContents t
			WHERE t.ring_buffer_type = N'RING_BUFFER_SECURITY_ERROR'
			) ss
				ON 1=1
	WHERE targ.ring_buffer_type = N'RING_BUFFER_SECURITY_ERROR';





	SELECT 
		@cpu_ticks = i.cpu_ticks,
		@ms_ticks = i.ms_ticks
	FROM sys.dm_os_sys_info i;

	BEGIN TRY
		INSERT INTO [ServerEye].[RingBufferConnectivity](
			[SQLServerStartTime],					--1
			[RecordID],
			[timestamp],
			[ExceptionTime],
			[UTCCaptureTime],						--5
			[LocalCaptureTime],

			RecordType,
			RecordSource,
			Spid,
			SniConnId,								--10
			OSError,
			ClientConnectionId,
			SniConsumerError,
			SniProvider,
			State,									--15
			RemoteHost,
			RemotePort,
			LocalHost,
			LocalPort,
			RecordTime,								--20
			TdsBufInfo_InputBufError,
			TdsBufInfo_OutputBufError,
			TdsBufInfo_InputBufBytes,

			LoginTimers_TotalTime,
			LoginTimers_EnqueueTime,				--25
			LoginTimers_NetWritesTime,
			LoginTimers_NetReadsTime,
			LoginTimersSSL_TotalTime,
			LoginTimersSSL_NetReadsTime,
			LoginTimersSSL_NetWritesTime,			--30
			LoginTimersSSL_SecAPITime,
			LoginTimersSSL_EnqueueTime,
			LoginTimersSSPI_TotalTime,
			LoginTimersSSPI_NetReadsTime,
			LoginTimersSSPI_NetWritesTime,			--35
			LoginTimersSSPI_SecAPITime,
			LoginTimersSSPI_EnqueueTime,
			LoginTimers_TriggerAndResGovTime,

			[TdsDisconnectFlags_PhysicalConnectionIsKilled],
			[TdsDisconnectFlags_DisconnectDueToReadError],		--40
			[TdsDisconnectFlags_NetworkErrorFoundInInputStream],
			[TdsDisconnectFlags_ErrorFoundBeforeLogin],
			[TdsDisconnectFlags_SessionIsKilled],
			[TdsDisconnectFlags_NormalDisconnect],
			[TdsDisconnectFlags_NormalLogout]			--45

		)
		SELECT 
			@SQLServerStartTime,					--1
			RecordID, 
			ss1.timestamp,
			ExceptionTime,
			@UTCCaptureTime,						--5
			@LocalCaptureTime,
			
			RecordType, 
			RecordSource, 
			Spid, 
			SniConnId = ISNULL(SniConnId,SniConnectionId2),		--10
			OSError,
			ClientConnectionId,						--10
			SniConsumerError,
			SniProvider,
			State,									--15
			RemoteHost,
			RemotePort,	
			LocalHost,
			LocalPort,
			RecordTime,								--20
			TdsBufInfo_InputBufError = ISNULL(TdsBufInfo_InputBufError, TdsBufInfo_InputBufError2),
			TdsBufInfo_OutputBufError = ISNULL(TdsBufInfo_OutputBufError, TdsBufInfo_OutputBufError2),
			TdsBufInfo_InputBufBytes = ISNULL(TdsBufInfo_InputBufBytes, TdsBufInfo_InputBufBytes2),

			LoginTimers_TotalTime = ISNULL(LoginTimers_TotalTime, LoginTimers_TotalTime2),
			LoginTimers_EnqueueTime = ISNULL(LoginTimers_EnqueueTime, LoginTimers_EnqueueTime2),				--25
			LoginTimers_NetWritesTime = ISNULL(LoginTimers_NetWritesTime, LoginTimers_NetWritesTime2),
			LoginTimers_NetReadsTime = ISNULL(LoginTimers_NetReadsTime, LoginTimers_NetReadsTime2),
			LoginTimersSSL_TotalTime = ISNULL(LoginTimersSSL_TotalTime, LoginTimersSSL_TotalTime2),
			LoginTimersSSL_NetReadsTime,
			LoginTimersSSL_NetWritesTime,			--30
			LoginTimersSSL_SecAPITime, 
			LoginTimersSSL_EnqueueTime,
			LoginTimersSSPI_TotalTime = ISNULL(LoginTimersSSPI_TotalTime, LoginTimersSSPI_TotalTime2),
			LoginTimersSSPI_NetReadsTime,
			LoginTimersSSPI_NetWritesTime,			--35
			LoginTimersSSPI_SecAPITime,
			LoginTimersSSPI_EnqueueTime,
			LoginTimers_TriggerAndResGovTime = ISNULL(LoginTimers_TriggerAndResGovTime, LoginTimers_TriggerAndResGovTime2),
			[TdsDisconnectFlags_PhysicalConnectionIsKilled],	
			[TdsDisconnectFlags_DisconnectDueToReadError],		--40
			[TdsDisconnectFlags_NetworkErrorFoundInInputStream],
			[TdsDisconnectFlags_ErrorFoundBeforeLogin],
			[TdsDisconnectFlags_SessionIsKilled],
			[TdsDisconnectFlags_NormalDisconnect],
			[TdsDisconnectFlags_NormalLogout]					--45
		FROM (
			SELECT 
				[RecordID] = recordXML.value('(./Record/@id)[1]', 'int'),
				ss0.timestamp,
				--Got this calculation from Jonathan Kehayias
				--https://www.sqlskills.com/blogs/jonathan/identifying-external-memory-pressure-with-dm_os_ring_buffers-and-ring_buffer_resource_monitor/
				ExceptionTime = DATEADD (ss, (-1 * ((@cpu_ticks / CONVERT (float, ( @cpu_ticks / @ms_ticks ))) - ss0.timestamp)/1000), GETDATE()),

				[RecordType]						= recordXML.value('(./Record/ConnectivityTraceRecord/RecordType)[1]', 'nvarchar(128)'),
				[RecordSource]						= recordXML.value('(./Record/ConnectivityTraceRecord/RecordSource)[1]', 'nvarchar(64)'),
				[Spid]								= recordXML.value('(./Record/ConnectivityTraceRecord/Spid)[1]', 'int'),
				[SniConnId]							= recordXML.value('(./Record/ConnectivityTraceRecord/SniConnId)[1]', 'nvarchar(128)'),
				[OSError]							= recordXML.value('(./Record/ConnectivityTraceRecord/OSError)[1]', 'int'),
				[ClientConnectionId]				= recordXML.value('(./Record/ConnectivityTraceRecord/ClientConnectionId)[1]', 'nvarchar(128)'),
				[SniConsumerError]					= recordXML.value('(./Record/ConnectivityTraceRecord/SniConsumerError)[1]', 'int'),
				[SniProvider]						= recordXML.value('(./Record/ConnectivityTraceRecord/SniProvider)[1]', 'int'),
				[State]								= recordXML.value('(./Record/ConnectivityTraceRecord/State)[1]', 'int'),
				[RemoteHost]						= recordXML.value('(./Record/ConnectivityTraceRecord/RemoteHost)[1]', 'nvarchar(128)'),
				[RemotePort]						= recordXML.value('(./Record/ConnectivityTraceRecord/RemotePort)[1]', 'int'),
				[LocalHost]							= recordXML.value('(./Record/ConnectivityTraceRecord/LocalHost)[1]', 'nvarchar(128)'),
				[LocalPort]							= recordXML.value('(./Record/ConnectivityTraceRecord/LocalPort)[1]', 'int'),
				[RecordTime]						= recordXML.value('(./Record/ConnectivityTraceRecord/RecordTime)[1]', 'nvarchar(64)'),
				[TdsBufInfo_InputBufError]			= recordXML.value('(./Record/ConnectivityTraceRecord/TdsBufInfo/InputBufError)[1]', 'int'),
				[TdsBufInfo_OutputBufError]			= recordXML.value('(./Record/ConnectivityTraceRecord/TdsBufInfo/OutputBufError)[1]', 'int'),
				[TdsBufInfo_InputBufBytes]			= recordXML.value('(./Record/ConnectivityTraceRecord/TdsBufInfo/InputBufBytes)[1]', 'int'),
				[LoginTimers_TotalTime]				= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TotalTime)[1]', 'bigint'),
				[LoginTimers_EnqueueTime]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/EnqueueTime)[1]', 'bigint'),
				[LoginTimers_NetWritesTime]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/NetWritesTime)[1]', 'bigint'),
				[LoginTimers_NetReadsTime]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/NetReadsTime)[1]', 'bigint'),
				[LoginTimersSSL_TotalTime]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Ssl/TotalTime)[1]', 'bigint'),
				[LoginTimersSSL_NetReadsTime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Ssl/NetReadsTime)[1]', 'bigint'),
				[LoginTimersSSL_NetWritesTime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Ssl/NetWritesTime)[1]', 'bigint'),
				[LoginTimersSSL_SecAPITime]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Ssl/SecAPITime)[1]', 'bigint'),
				[LoginTimersSSL_EnqueueTime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Ssl/EnqueueTime)[1]', 'bigint'),
				[LoginTimersSSPI_TotalTime]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Sspi/TotalTime)[1]', 'bigint'),
				[LoginTimersSSPI_NetReadsTime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Sspi/NetReadsTime)[1]', 'bigint'),
				[LoginTimersSSPI_NetWritesTime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Sspi/NetWritesTime)[1]', 'bigint'),
				[LoginTimersSSPI_SecAPITime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Sspi/SecAPITime)[1]', 'bigint'),
				[LoginTimersSSPI_EnqueueTime]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Sspi/EnqueueTime)[1]', 'bigint'),
				[LoginTimers_TriggerAndResGovTime]	= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TriggerAndResGovTime)[1]', 'bigint'),
				[TdsDisconnectFlags_PhysicalConnectionIsKilled]		= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/PhysicalConnectionIsKilled)[1]', 'int'),
				[TdsDisconnectFlags_DisconnectDueToReadError]		= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/DisconnectDueToReadError)[1]', 'int'),
				[TdsDisconnectFlags_NetworkErrorFoundInInputStream]	= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/NetworkErrorFoundInInputStream)[1]', 'int'),
				[TdsDisconnectFlags_ErrorFoundBeforeLogin]			= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/ErrorFoundBeforeLogin)[1]', 'int'),
				[TdsDisconnectFlags_SessionIsKilled]				= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/SessionIsKilled)[1]', 'int'),
				[TdsDisconnectFlags_NormalDisconnect]				= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalDisconnect)[1]', 'int'),
				[TdsDisconnectFlags_NormalLogout]					= recordXML.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/NormalLogout)[1]', 'int'),

				--I've seen a variance in the schema for some fields here: 
				-- http://dba.stackexchange.com/questions/11073/tdsinputbuffererror-not-0-in-logintimers-errors-of-ring-buffer-connectivity-of-s

				[SniConnectionId2]						= recordXML.value('(./Record/ConnectivityTraceRecord/SniConnectionId)[1]', 'nvarchar(128)'),
				[TdsBufInfo_InputBufError2]				= recordXML.value('(./Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferError)[1]', 'int'),
				[TdsBufInfo_OutputBufError2]			= recordXML.value('(./Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsOutputBufferError)[1]', 'int'),
				[TdsBufInfo_InputBufBytes2]				= recordXML.value('(./Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferBytes)[1]', 'int'),
				[LoginTimers_TotalTime2]				= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/TotalLoginTimeInMilliseconds)[1]', 'bigint'),
				[LoginTimers_EnqueueTime2]				= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/LoginTaskEnqueuedInMilliseconds)[1]', 'bigint'),
				[LoginTimers_NetWritesTime2]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/NetworkWritesInMilliseconds)[1]', 'bigint'),
				[LoginTimers_NetReadsTime2]				= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/NetworkReadsInMilliseconds)[1]', 'bigint'),
				[LoginTimersSSL_TotalTime2]				= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/SslProcessingInMilliseconds)[1]', 'bigint'),
				[LoginTimersSSPI_TotalTime2]			= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/SspiProcessingInMilliseconds)[1]', 'bigint'),
				[LoginTimers_TriggerAndResGovTime2]		= recordXML.value('(./Record/ConnectivityTraceRecord/LoginTimers/LoginTriggerAndResourceGovernorProcessingInMilliseconds)[1]', 'bigint')
			FROM (
				SELECT rb.timestamp,
					CONVERT(XML,rb.record) as recordXML
				FROM #RingBufferTempContents rb
				WHERE rb.ring_buffer_type = N'RING_BUFFER_CONNECTIVITY'
			) ss0
		) ss1
		WHERE NOT EXISTS (
			SELECT *
			FROM ServerEye.RingBufferConnectivity e
			WHERE e.SQLServerStartTime = @SQLServerStartTime
			AND ss1.RecordID = e.RecordID
		);
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		SET @lv__AllRBsSuccessful = 0;

		--save off our problematic data for later analysis
		INSERT INTO ServerEye.RingBufferCausedExceptions (
			UTCCaptureTime,
			LocalCaptureTime,
			ring_buffer_address,
			ring_buffer_type,
			timestamp,
			record
		)
		SELECT @UTCCaptureTime,
			@LocalCaptureTime,
			t.ring_buffer_address, 
			t.ring_buffer_type, 
			t.timestamp,
			t.record
		FROM #RingBufferTempContents t
		WHERE t.ring_buffer_type = N'RING_BUFFER_CONNECTIVITY';

		SET @err__ErrorSeverity = ERROR_SEVERITY();
		SET @err__ErrorState = ERROR_STATE();
		SET @err__ErrorText = N'Error occurred during processing of RING_BUFFER_CONNECTIVITY. Error #: ' + 
			CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
			CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

		--we log the message, but we don't re-raise the exception. 
		EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=-999, @TraceID=NULL, @Location='RBCONN', @Message=@err__ErrorText;
	END CATCH

	UPDATE targ 
	SET targ.max_timestamp_processed = ISNULL(ss.max_timestamp, targ.max_timestamp_processed)
	FROM ServerEye.RingBufferProgress targ 
		LEFT OUTER JOIN (
			SELECT MAX(t.timestamp) as max_timestamp
			FROM #RingBufferTempContents t
			WHERE t.ring_buffer_type = N'RING_BUFFER_CONNECTIVITY'
			) ss
				ON 1=1
	WHERE targ.ring_buffer_type = N'RING_BUFFER_CONNECTIVITY';





	IF @lv__AllRBsSuccessful = 0
	BEGIN
		RETURN -1;
	END
	ELSE
	BEGIN
		RETURN 0;
	END
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;

	SET @err__ErrorSeverity = ERROR_SEVERITY();
	SET @err__ErrorState = ERROR_STATE();
	SET @err__ErrorText = N'Unexpected exception occurred at location "' + ISNULL(@errorloc,N'<null>') + '". Error #: ' + 
		CONVERT(NVARCHAR(20),ERROR_NUMBER()) + N'; State: ' + CONVERT(NVARCHAR(20),ERROR_STATE()) + N'; Severity: ' + 
		CONVERT(NVARCHAR(20),ERROR_SEVERITY()) + N'; message: ' + ERROR_MESSAGE();

	RAISERROR(@err__ErrorText, @err__ErrorSeverity, @err__ErrorState);
	RETURN -1;
END CATCH

	RETURN 0;
END
GO