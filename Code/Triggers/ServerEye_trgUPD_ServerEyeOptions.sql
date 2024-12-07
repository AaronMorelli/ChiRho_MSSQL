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

	FILE NAME: ServerEye_trgUPD_ServerEyeOptions.sql

	TRIGGER NAME: ServerEye_trgUPD_ServerEyeOptions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Copies data updated in the Options table to the history table.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TRIGGER @@CHIRHO_SCHEMA@@.ServerEye_trgUPD_ServerEyeOptions ON @@CHIRHO_SCHEMA@@.ServerEye_Options

FOR UPDATE
AS 	BEGIN

INSERT INTO @@CHIRHO_SCHEMA@@.ServerEye_Options_History (
RowID, ServerEyeEnabled, BeginTime, EndTime, BeginEndIsUTC, IntervalLength, IncludeDBs, ExcludeDBs, Retention_Days, DebugSpeed, PurgeUnextractedData,
HistoryInsertDate,
HistoryInsertDateUTC,
TriggerAction,
LastModifiedUser)
SELECT 
RowID, ServerEyeEnabled, BeginTime, EndTime, BeginEndIsUTC, IntervalLength, IncludeDBs, ExcludeDBs, Retention_Days, DebugSpeed, PurgeUnextractedData,
GETDATE(),
GETUTCDATE(),
'Update',
SUSER_SNAME()
FROM inserted

END
GO