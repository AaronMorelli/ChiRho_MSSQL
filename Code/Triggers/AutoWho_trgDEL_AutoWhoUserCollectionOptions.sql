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

	FILE NAME: AutoWho_trgDEL_AutoWhoUserCollectionOptions.sql

	TRIGGER NAME: AutoWho_trgDEL_AutoWhoUserCollectionOptions

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Prevents deletes on the AutoWho_UserCollectionOptions table.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TRIGGER @@CHIRHO_SCHEMA@@.AutoWho_trgDEL_AutoWhoUserCollectionOptions ON @@CHIRHO_SCHEMA@@.AutoWho_UserCollectionOptions

FOR DELETE
AS 	BEGIN

--We don't allow deletes.
RAISERROR('Deletes on the UserCollectionOption table are forbidden. To reset the options to defaults, call the AutoWho_ResetUserCollectionOptions procedure.',10,1);
ROLLBACK TRANSACTION;

RETURN;

END
GO
