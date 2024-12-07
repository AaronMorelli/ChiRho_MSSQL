SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_CollectorDuration
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

	FILE NAME: AutoWho_CollectorDuration.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_CollectorDuration

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Splits out the comma-separated entries in the "DurationBreakdown" field of @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes
		into aggregated rows, to allow us to see which statements in the AutoWho Collector are typically the
		most expensive. The Messages tab also holds a query that can be used to view the detailed data for
		ad-hoc analysis.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_CollectorDuration @StartTime='2016-04-23 04:00', @EndTime = '2016-04-23 06:00'
*/
(
	@StartTime	DATETIME=NULL,
	@EndTime	DATETIME=NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	IF @StartTime IS NULL
	BEGIN
		--All-time past
		SET @StartTime = CONVERT(DATETIME,'2000-01-01');
	END

	IF @EndTime IS NULL
	BEGIN
		--All-time future
		SET @EndTime = CONVERT(DATETIME,'2100-01-01');
	END

	IF @EndTime <= @StartTime
	BEGIN
		RAISERROR('Parameter @EndTime must be greater than parameter @StartTime.', 16, 10);
		RETURN -1;
	END

	SELECT Tag, 
		[NumExecutions] = COUNT(*), 
		[SumDuration_ms] = SUM(TagDuration_ms),
		[AvgDuration_ms] = AVG(TagDuration_ms),
		[MinDuration_ms] = MIN(TagDuration_ms),
		[MaxDuration_ms] = MAX(TagDuration_ms)
	FROM (
		SELECT 
			SPIDCaptureTime, 
			AutoWhoDuration_ms, 
			Tag, 
			[TagDuration_ms] = CONVERT(BIGINT,TagDuration_ms)
		FROM (
			SELECT 
				ss2.SPIDCaptureTime, 
				ss2.AutoWhoDuration_ms, 
				[Tag] = SUBSTRING(TagWithDuration,1, CHARINDEX(':', TagWithDuration)-1), 
				[TagDuration_ms] = SUBSTRING(TagWithDuration, CHARINDEX(':', TagWithDuration)+1, LEN(TagWithDuration)),
				TagWithDuration
			FROM (
				SELECT ss.*, 
					[TagWithDuration] = Split.a.value(N'.', 'NVARCHAR(512)')
				FROM (
					SELECT 
						t.SPIDCaptureTime, 
						t.AutoWhoDuration_ms, 
						[loclist] = CAST(N'<M>' + REPLACE(DurationBreakdown,  N',' , N'</M><M>') + N'</M>' AS XML)
					FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes t WITH (NOLOCK)
					WHERE t.RunWasSuccessful = 1
					AND t.SPIDCaptureTime BETWEEN @StartTime AND @EndTime
				) ss
					CROSS APPLY loclist.nodes(N'/M') Split(a)
			) ss2
			WHERE LTRIM(RTRIM(TagWithDuration)) <> ''
		) ss3
	) ss4
	GROUP BY Tag
	ORDER BY 3 DESC
	OPTION(RECOMPILE);

	--We print out the un-grouped query to the Messages tab so the user can sift through & filter
	-- the detailed data in an ad-hoc fashion
	DECLARE @printtotab NVARCHAR(4000);

	SET @printtotab = N'
	DECLARE @StartTime datetime = ''' + 
		REPLACE(CONVERT(NVARCHAR(40),@StartTime,102),'.','-') + ' ' + 
		CONVERT(NVARCHAR(40), @StartTime,108) + '.' + 
		CONVERT(NVARCHAR(40),DATEPART(MILLISECOND, @StartTime)) + ''';
	DECLARE @EndTime datetime = ''' + 
		REPLACE(CONVERT(NVARCHAR(40),@EndTime,102),'.','-') + ' ' + 
		CONVERT(NVARCHAR(40), @EndTime,108) + '.' + 
		CONVERT(NVARCHAR(40),DATEPART(MILLISECOND, @EndTime)) + '''; 
	SELECT 
		SPIDCaptureTime, 
		AutoWhoDuration_ms, 
		Tag, 
		TagDuration_ms,
		UTCCaptureTime
	FROM (
		SELECT 
			ss2.SPIDCaptureTime, 
			ss2.AutoWhoDuration_ms, 
			[Tag] = SUBSTRING(TagWithDuration,1, CHARINDEX('':'', TagWithDuration)-1), 
			[TagDuration_ms] = SUBSTRING(TagWithDuration, CHARINDEX('':'', TagWithDuration)+1, LEN(TagWithDuration)),
			[TagWithDuration],
			ss2.UTCCaptureTime
		FROM (
			SELECT ss.*, 
				[TagWithDuration] = Split.a.value(N''.'', ''NVARCHAR(512)'')
			FROM (
				SELECT 
					t.SPIDCaptureTime, 
					t.UTCCaptureTime,
					t.AutoWhoDuration_ms, 
					[loclist] = CAST(N''<M>'' + REPLACE(DurationBreakdown,  N'','' , N''</M><M>'') + N''</M>'' AS XML)
				FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes t with(nolock)
				WHERE t.RunWasSuccessful = 1
				AND t.SPIDCaptureTime BETWEEN @StartTime AND @EndTime
			) ss
				CROSS APPLY loclist.nodes(N''/M'') Split(a)
		) ss2
		WHERE LTRIM(RTRIM(TagWithDuration)) <> ''''
	) ss3
	--ORDER BY ss3.UTCCaptureTime
	OPTION(RECOMPILE)
	;';

	PRINT @printtotab;
	RETURN 0;
END 
GO
