SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CoreXR].[UpdateDBMapping] 
/*   
   Copyright 2016 Aaron Morelli

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

	PROJECT NAME: ChiRho https://github.com/AaronMorelli/ChiRho

	PROJECT DESCRIPTION: A T-SQL toolkit for troubleshooting performance and stability problems on SQL Server instances

	FILE NAME: CoreXR.UpdateDBMapping.StoredProcedure.sql

	PROCEDURE NAME: CoreXR.UpdateDBMapping

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Since our app stored historical data, and DBs are sometimes detached/re-attached, etc,
	 we want to keep a mapping between DBID and DBName. (Most of the AutoWho/ServerEye tables just store DBID rather than DBName).
	 We make the (usually-safe, but not always) assumption that 2 DBs with the same name are really the same database.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC CoreXR.UpdateDBMapping
*/
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @EffectiveTime DATETIME = GETDATE(),
			@EffectiveTimeUTC DATETIME = GETUTCDATE();

	CREATE TABLE #CurrentDBIDNameMapping (
		DBID	INT NOT NULL, 
		DBName	NVARCHAR(256) NOT NULL
	);

	INSERT INTO #CurrentDBIDNameMapping (
		DBID, 
		DBName
	)
	SELECT 
		d.database_id, 
		d.name
	FROM sys.databases d;

	/* The CoreXR.DBIDNameMapping table tracks time ranges for mappings, and there is (of course) also
		the concept of a "current set", i.e. every row where EffectiveEndTimeUTC IS NULL.

		First, we close out every row where we have a DBName present in both the current set and in our SQL catalog,
		but the DBIDs don't match. This probably indicates something like a detach/re-attach.
	*/

	UPDATE targ 
	SET EffectiveEndTimeUTC = @EffectiveTimeUTC,
		EffectiveEndTime = @EffectiveTime
	FROM CoreXR.DBIDNameMapping targ 
		INNER JOIN #CurrentDBIDNameMapping t
			ON t.DBName = targ.DBName
			AND t.DBID <> targ.DBID
	WHERE targ.EffectiveEndTimeUTC IS NULL;

	/*
		Next, we insert any DBNames where the name is in the catalog but not present at all in our current set. 
		(It could be present in an older, already-closed-out row).
		It could be a new DB, or it could have been detached for a while, its row in CoreXR.DBIDNameMapping closed out,
		and then re-attached.
	*/
	INSERT INTO CoreXR.DBIDNameMapping (
		DBID, 
		DBName, 
		EffectiveStartTimeUTC, 
		EffectiveEndTimeUTC, 
		EffectiveStartTime, 
		EffectiveEndTime
	)
	SELECT 
		t.DBID, 
		t.DBName, 
		@EffectiveTimeUTC, 
		NULL ,
		@EffectiveTime, 
		NULL 
	FROM #CurrentDBIDNameMapping t
	WHERE NOT EXISTS (
		SELECT * 
		FROM CoreXR.DBIDNameMapping m
		WHERE m.DBName = t.DBName
		AND m.EffectiveEndTimeUTC IS NULL 
	);

	/* 
		Finally, we close out any current set members that are not present at all in the SQL catalog
	*/
	UPDATE targ 
	SET EffectiveEndTimeUTC = @EffectiveTimeUTC,
		EffectiveEndTime = @EffectiveTime
	FROM CoreXR.DBIDNameMapping targ 
	WHERE targ.EffectiveEndTimeUTC IS NULL
	AND NOT EXISTS (
		SELECT * FROM #CurrentDBIDNameMapping t
		WHERE t.DBName = targ.DBName
	);

	RETURN 0;
END
GO
