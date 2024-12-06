SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.CoreXR_TraceTimeInfo
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

	FILE NAME: CoreXR_TraceTimeInfo.StoredProcedure.sql

	PROCEDURE NAME: CoreXR_TraceTimeInfo

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Given a point in time in UTC (usually executed with the current time), finds the earliest start time and end time in UTC
	where the point in time is between (inclusive) the start and end, i.e. when the trace should be running.
	That "earliest" time includes start/end times whene point-in-time is after the start and before the end, which basically
	means "the trace should be running now". Consumers can use this both to determine whether the trace should be running now,
	and if so, what the end time should be.

	OUTSTANDING ISSUES: None at this time

To Execute
------------------------
DECLARE @rc INT,
	@pit DATETIME, 
	@en NCHAR(1),
	@st DATETIME, 
	@nd DATETIME

EXEC @rc = @@CHIRHO_SCHEMA@@.CoreXR_TraceTimeInfo @Utility=N'AutoWho', @PointInTimeUTC = @pit, @UtilityIsEnabled = @en OUTPUT, 
		@UtilityStartTimeUTC = @st OUTPUT, @UtilityEndTimeUTC = @nd OUTPUT

SELECT @rc as ProcRC, @en as Enabled, @st as StartTime, @nd as EndTime
*/
(
	@Utility				NVARCHAR(20),
	@PointInTimeUTC			DATETIME,		--The caller is responsible for passing in a UTC datetime rather than a local time.
	@UtilityIsEnabled		NCHAR(1) OUTPUT,
	@UtilityStartTimeUTC	DATETIME OUTPUT,
	@UtilityEndTimeUTC		DATETIME OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE	
		@lmsg				NVARCHAR(4000),
		@rc					INT,
		@opt__BeginTime		TIME(0),
		@opt__EndTime		TIME(0),
		@opt__BeginEndIsUTC NCHAR(1),

		@BeginTimeUTC		TIME(0),
		@EndTimeUTC			TIME(0),
		@RangeDescription	VARCHAR(10),
		@PointInTime_TimeOnly TIME(0),
		
		@UTCDiffMinutesFromLocalTime	INT,
		@BeginTimeWithDate	DATETIME,
		@EndTimeWithDate	DATETIME,
		@PointInTimeWithDate	DATETIME;

	IF @PointInTimeUTC IS NULL
	BEGIN
		SET @PointInTimeUTC = GETUTCDATE();
	END

	IF @Utility NOT IN (N'AutoWho', N'ServerEye')
	BEGIN
		RAISERROR('Parameter @Utility must be in the following list: AutoWho, ServerEye', 16, 1);
		RETURN -1;
	END

	SET @UTCDiffMinutesFromLocalTime = DATEDIFF(MINUTE,GETDATE(), GETUTCDATE());	--use minutes, not hours, b/c of time zones that are 30 minutes shifted.

	IF @Utility = N'AutoWho'
	BEGIN
		SELECT 
			@UtilityIsEnabled		 = [AutoWhoEnabled],
			@opt__BeginTime			 = [BeginTime],
			@opt__EndTime			 = [EndTime],
			@opt__BeginEndIsUTC		 = [BeginEndIsUTC]
		FROM @@CHIRHO_SCHEMA@@.AutoWho_Options o;
	END
	ELSE IF @Utility = N'ServerEye'
	BEGIN
		SELECT 
			@UtilityIsEnabled		 = [ServerEyeEnabled],
			@opt__BeginTime			 = [BeginTime],
			@opt__EndTime			 = [EndTime],
			@opt__BeginEndIsUTC		 = [BeginEndIsUTC]
		FROM @@CHIRHO_SCHEMA@@.ServerEye_Options o;
	END

	--First, check to see if the begin/end options are UTC or local. If local, convert to UTC.
	--The logic below works because the TIME data type wraps. E.g. if you pass in '20:00' and add 7 hours, you get 03:00
	IF @opt__BeginEndIsUTC = N'Y'
	BEGIN
		SET @BeginTimeUTC = @opt__BeginTime;
		SET @EndTimeUTC = @opt__EndTime;
	END
	ELSE
	BEGIN
		SET @BeginTimeUTC = DATEADD(MINUTE, @UTCDiffMinutesFromLocalTime, @opt__BeginTime);
		SET @EndTimeUTC = DATEADD(MINUTE, @UTCDiffMinutesFromLocalTime, @opt__EndTime);
	END

	SET @PointInTime_TimeOnly = CONVERT(TIME(0),@PointInTimeUTC);

	--Our logic differs based on whether Begin is < End or Begin is > End.
	-- (If Begin is > End, e.g. 16:00 and 4:00, it means that End represents the next day, e.g. 16:00 on one day and 4:00 on the next day)
	IF @BeginTimeUTC < @EndTimeUTC
	BEGIN
		--trace is contained in one day
		IF @PointInTime_TimeOnly <= @BeginTimeUTC
			OR (@PointInTime_TimeOnly >= @BeginTimeUTC AND @PointInTime_TimeOnly < @EndTimeUTC)
		BEGIN
			SET @UtilityStartTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@BeginTimeUTC);
			SET @UtilityEndTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@EndTimeUTC);
		END
		ELSE 
		BEGIN
			--PIT must be > @BeginTimeUTC AND > @EndTimeUTC. The next run is tomorrow
			SET @UtilityStartTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@BeginTimeUTC);
			SET @UtilityStartTimeUTC = DATEADD(DAY, 1, @UtilityStartTimeUTC);
			SET @UtilityEndTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@EndTimeUTC);
			SET @UtilityEndTimeUTC = DATEADD(DAY, 1, @UtilityEndTimeUTC);
		END
	END
	ELSE
	BEGIN
		--trace spans 2 days
		IF @PointInTime_TimeOnly >= @BeginTimeUTC	--if after the BeginTime the trace should run the rest of the day and into tomorrow

			OR (@PointInTime_TimeOnly < @BeginTimeUTC AND @PointInTime_TimeOnly >= @EndTimeUTC)
			-- conceptually, this is before today's run and after yesterday's run ended. So the next start time 
			-- is today's start/tomorrow's end.
		BEGIN
			SET @UtilityStartTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@BeginTimeUTC);
			SET @UtilityEndTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@EndTimeUTC);
			SET @UtilityEndTimeUTC = DATEADD(DAY, 1, @UtilityEndTimeUTC);
		END
		ELSE
		BEGIN
			--PIT is < begin and also < end. Conceptually this means it is within the range of yesterday's start time/today's end time.
			SET @UtilityStartTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@BeginTimeUTC);
			SET @UtilityStartTimeUTC = DATEADD(DAY, -1, @UtilityStartTimeUTC);
			SET @UtilityEndTimeUTC = CONVERT(DATETIME,CONVERT(DATE,@PointInTimeUTC)) + CONVERT(DATETIME,@EndTimeUTC)
		END
	END

	RETURN 0;
END 
GO