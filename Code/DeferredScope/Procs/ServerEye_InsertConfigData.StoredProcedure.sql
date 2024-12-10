SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[InsertConfigData] 
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

	FILE NAME: ServerEye.InsertConfigData.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.InsertConfigData

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Runs at install time and inserts configuration data.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.InsertConfigData @DaysToKeep=30

--use to reset the data:
truncate table ServerEye.UserCollectionOptions
truncate table ServerEye.UserCollectionOptions_History
truncate table ServerEye.Options
truncate table ServerEye.Options_History
*/
(
	@DaysToKeep INT
)
AS
BEGIN
	SET NOCOUNT ON;

	IF ISNULL(@DaysToKeep,-1) <= 3 OR ISNULL(@DaysToKeep,9999) > 180
	BEGIN
		RAISERROR('The @DaysToKeep parameter cannot be <= 0 or > 180 days.',16,1);
		RETURN -1;
	END

	--To prevent this proc from damaging the installation after it has already been run, check for existing data.
	IF EXISTS (SELECT * FROM ServerEye.Options)
		OR EXISTS (SELECT * FROM ServerEye.UserCollectionOptions)
		OR EXISTS (SELECT * 
					FROM ServerEye.DatabaseInclusion di
						INNER JOIN sys.databases d
							ON di.DBName = d.name
					WHERE NOT (di.InclusionType = N'IndexStats'
							AND di.DBName = DB_NAME()
							)
					)
	BEGIN
		RAISERROR('The ServerEye configuration tables are not empty. You must clear these tables first before this procedure will insert config data', 16,1);
		RETURN -2;
	END

	IF NOT EXISTS (
		SELECT * 
			FROM ServerEye.DatabaseInclusion di
				INNER JOIN sys.databases d
					ON di.DBName = d.name
			WHERE di.InclusionType = N'IndexStats'
			AND di.DBName = DB_NAME()
	)
	BEGIN
		INSERT INTO ServerEye.DatabaseInclusion (
			DBName,
			InclusionType
		)
		SELECT DB_NAME(), 'IndexStats';
	END

	--Options
	EXEC ServerEye.ResetOptions; 

	--Retention variables are based on the DaysToKeep input parameter
	UPDATE ServerEye.Options SET Retention_Days = @DaysToKeep;

	EXEC ServerEye.ResetUserCollectionOptions;

	--INSERT INTO CoreXR.ProcessingTimes (Label, LastProcessedTime, LastProcessedTimeUTC)
	--SELECT N'ServerEyeStoreLastTouched', NULL, NULL;

	RETURN 0;
END

GO
