SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[ResetOptions] 
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

	FILE NAME: ServerEye.ResetOptions.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.ResetOptions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Deletes the row in ServerEye.Options and re-inserts a row based on default values

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.ResetOptions

SELECT * FROM ServerEye.Options
*/
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO ServerEye.Options_History
	(
	RowID, ServerEyeEnabled, BeginTime, EndTime, BeginEndIsUTC, IntervalLength, IncludeDBs, ExcludeDBs, Retention_Days, DebugSpeed, PurgeUnextractedData,
	HistoryInsertDate,
	HistoryInsertDateUTC,
	TriggerAction,
	LastModifiedUser)
	SELECT 
	RowID, ServerEyeEnabled, BeginTime, EndTime, BeginEndIsUTC, IntervalLength, IncludeDBs, ExcludeDBs, Retention_Days, DebugSpeed, PurgeUnextractedData,
	GETDATE(),
	GETUTCDATE(),
	'Reset',
	SUSER_NAME()
	FROM ServerEye.Options;

	DISABLE TRIGGER ServerEye.trgDEL_ServerEyeOptions ON ServerEye.Options;

	DELETE FROM ServerEye.Options;

	ENABLE TRIGGER ServerEye.trgDEL_ServerEyeOptions ON ServerEye.Options;

	INSERT INTO ServerEye.Options 
		DEFAULT VALUES;

	RETURN 0;
END



GO
