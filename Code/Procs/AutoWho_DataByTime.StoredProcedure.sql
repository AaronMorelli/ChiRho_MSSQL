SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_DataByTime
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

	FILE NAME: AutoWho_DataByTime.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_DataByTime

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Just dumps out data for each table organized by time. Mainly for quick data collection review during development.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_DataByTime
*/
AS
BEGIN
	SET NOCOUNT ON;

	SELECT tb.TableName, d.*
	FROM
	(SELECT 'AutoWho_SignalTable' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT * 
		FROM @@CHIRHO_SCHEMA@@.AutoWho_SignalTable
		) d
		ON 1=1;

	SELECT tb.TableName, d.*
	FROM
	(SELECT 'AutoWho_ThresholdFilterSpids' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT *
		FROM @@CHIRHO_SCHEMA@@.AutoWho_ThresholdFilterSpids
		) d
		ON 1=1;

	SELECT tb.TableName, d.*
	FROM
	(SELECT 'AutoWho_Log' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT CONVERT(DATE, LogDT) as LogDT, TraceID, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_Log
			GROUP BY CONVERT(DATE, LogDT), TraceID
		) d
		ON 1=1
	ORDER BY d.LogDT ASC, d.TraceID;

	SELECT tb.TableName, d.*
	FROM
	(SELECT 'CoreXR_Traces' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT *
		FROM @@CHIRHO_SCHEMA@@.CoreXR_Traces
		WHERE Utility = N'AutoWho'
		) d
		ON 1=1
	ORDER BY d.TraceID;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.CoreXR_CaptureOrdinalCache' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT DISTINCT t.StartTime, t.EndTime
			FROM @@CHIRHO_SCHEMA@@.CoreXR_CaptureOrdinalCache t
			WHERE t.Utility = N'AutoWho'
		) d
		ON 1=1
	ORDER BY d.StartTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT CONVERT(DATE,cs.SPIDCaptureTime) as CaptureDT
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary cs
		) d
		ON 1=1
	ORDER BY d.CaptureDT;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT CONVERT(DATE,ct.SPIDCaptureTime) as CaptureDT
			FROM @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes ct
		) d
		ON 1=1
	ORDER BY d.CaptureDT;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_LightweightSessions' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT l.SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_LightweightSessions l
			GROUP BY l.SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_LightweightTasks' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT l.SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_LightweightTasks l
			GROUP BY l.SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_LightweightTrans' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT l.SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_LightweightTrans l
			GROUP BY l.SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT 'AutoWho.BlockingGraphs' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs bg
			GROUP BY SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_LockDetails' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@AutoWho_LockDetails
			GROUP BY SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT t.SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails t
			GROUP BY t.SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT sar.SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests sar
			GROUP BY sar.SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT taw.SPIDCaptureTime, COUNT(*) as NumRows
			FROM @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits taw
			GROUP BY taw.SPIDCaptureTime
		) d
		ON 1=1
	ORDER BY d.SPIDCaptureTime;

	SELECT tb.TableName, d.InsertHour, COUNT(InsertHour) as NumRows
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT InsertHour = CONVERT(varchar(30),CONVERT(DATE, InsertedBy_UTCCaptureTime)) + 
							' ' + CONVERT(varchar(30),DATEPART(HOUR, InsertedBy_UTCCaptureTime)) + ':00'
			FROM @@CHIRHO_SCHEMA@@.CoreXR_InputBufferStore
		) d
		ON 1=1
	GROUP BY tb.TableName, d.InsertHour
	ORDER BY d.InsertHour;

	SELECT tb.TableName, d.InsertHour, COUNT(InsertHour) as NumRows
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT InsertHour = CONVERT(varchar(30),CONVERT(DATE, InsertedBy_UTCCaptureTime)) + 
						' ' + CONVERT(varchar(30),DATEPART(HOUR, InsertedBy_UTCCaptureTime)) + ':00'
		FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanBatchStore
		) d
		ON 1=1
	GROUP BY tb.TableName, d.InsertHour
	ORDER BY d.InsertHour;

	SELECT tb.TableName, d.InsertHour, COUNT(InsertHour) as NumRows
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT InsertHour = CONVERT(varchar(30),CONVERT(DATE, InsertedBy_UTCCaptureTime)) + 
						' ' + CONVERT(varchar(30),DATEPART(HOUR, InsertedBy_UTCCaptureTime)) + ':00'
		FROM @@CHIRHO_SCHEMA@@.CoreXR_QueryPlanStmtStore
		) d
		ON 1=1
	GROUP BY tb.TableName, d.InsertHour
	ORDER BY d.InsertHour;

	SELECT tb.TableName, d.InsertHour, COUNT(InsertHour) as NumRows
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT InsertHour = CONVERT(varchar(30),CONVERT(DATE, InsertedBy_UTCCaptureTime)) + 
						' ' + CONVERT(varchar(30),DATEPART(HOUR, InsertedBy_UTCCaptureTime)) + ':00'
		FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLBatchStore
		) d
		ON 1=1
	GROUP BY tb.TableName, d.InsertHour
	ORDER BY d.InsertHour;

	SELECT tb.TableName, d.InsertHour, COUNT(InsertHour) as NumRows
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore' as TableName) Tb
		LEFT OUTER JOIN (
		SELECT InsertHour = CONVERT(varchar(30),CONVERT(DATE, InsertedBy_UTCCaptureTime)) + 
						' ' + CONVERT(varchar(30),DATEPART(HOUR, InsertedBy_UTCCaptureTime)) + ':00'
		FROM @@CHIRHO_SCHEMA@@.CoreXR_SQLStmtStore
		) d
		ON 1=1
	GROUP BY tb.TableName, d.InsertHour
	ORDER BY d.InsertHour;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_DimCommand' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimCommand
		) d
		ON 1=1
	ORDER BY d.TimeAdded;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute
		) d
		ON 1=1
	ORDER BY d.TimeAdded;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_DimLoginName' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName
		) d
		ON 1=1
	ORDER BY d.TimeAdded;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress
		) d
		ON 1=1
	ORDER BY d.TimeAdded;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute
		) d
		ON 1=1
	ORDER BY d.TimeAdded;

	SELECT tb.TableName, d.*
	FROM
	(SELECT '@@CHIRHO_SCHEMA@@.AutoWho_DimWaitType' as TableName) Tb
		LEFT OUTER JOIN (
			SELECT * FROM @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType
		) d
		ON 1=1
	ORDER BY d.TimeAdded;

	RETURN 0;
END
GO
