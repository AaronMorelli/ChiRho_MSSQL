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

	FILE NAME: CoreXR_trgINS_CoreXR_Version.sql

	TRIGGER NAME: CoreXR_trgINS_CoreXR_Version

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Maintains the CoreXR_Version_History table
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TRIGGER @@CHIRHO_SCHEMA@@.CoreXR_trgINS_CoreXR_Version ON @@CHIRHO_SCHEMA@@.CoreXR_Version

FOR INSERT
AS 	BEGIN

INSERT INTO @@CHIRHO_SCHEMA@@.CoreXR_Version_History
([Version], 
EffectiveDate, 
EffectiveDateUTC,
HistoryInsertDate,
historyInsertDateUTC,
TriggerAction)
SELECT 
[Version], 
EffectiveDate, 
EffectiveDateUTC,
GETDATE(),
GETUTCDATE(),
'Insert'
FROM inserted
END
GO

