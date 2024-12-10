SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_ObtainSessionsForThresholdIgnore
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

	FILE NAME: AutoWho_ObtainSessionsForThresholdIgnore.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ObtainSessionsForThresholdIgnore

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: The AutoWho collector uses "threshold" parameters to determine whether certain, more-expensive
		activities (collecting query plans, input buffers, tran or lock info, etc) are required. If no SPIDs
		cross those thresholds on a given run, that extra info will not be collected. This strategy helps keep
		the collector efficient. 

		The main driver for these thresholds is spid (active or idle) duration. However, there are sessions that
		we know will be active all day (e.g. the AutoWho and Server Executor/Collector SPIDs), so we need to 
		exclude those sessions from the threshold calculation. This proc is called from @@CHIRHO_SCHEMA@@.AutoWho_Executor every
		5 minutes and re-calcs the Session IDs. 

		NOTE: this proc is intended to be customized by users on an as-needed basis. 

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_ObtainSessionsForThresholdIgnore 

*/
AS
BEGIN
	SET NOCOUNT ON;
	/* 
		Sessions we want to identify:
			Self (because even if the AutoWho.Options table has us including SELF, we still don't
				want it to trigger the thresholds)
			TODO: ServerEye's Executor/Collector
				Note that I do not have any logic in this proc yet for this case!
	*/
	DECLARE @SPIDsToFilter TABLE (SessionID INT); 

	INSERT INTO @SPIDsToFilter (SessionID)
	SELECT @@SPID;

	--For some spids, we may want to identify them based on their DBCC INPUTBUFFER.
	DECLARE @SPIDsToIB TABLE (SessionID INT, DatabaseID SMALLINT);
	DECLARE @IBResults TABLE (
		EventType VARCHAR(100), 
		[Parameters] INT, 
		InputBuffer NVARCHAR(4000)
	);

	/*
	--TODO: The @IBResults table and the logic below assist in obtaining DBCC INPUTBUFFER results
	--for certain spids. The idea here is that first you write an INSERT statement (not shown here) into @SPIDsToIB
	-- that looks at the open sessions on the instance and restricts them based on some criteria, e.g.
	-- DBID of the SPID. This is more efficient than just running DBCC INPUTBUFFER on every spid, every time.
	-- Then, for the smaller set of SPIDs that pass your initial logic, the below loop will obtain the input buffer
	-- for each, and then additional filtering can determine whether it is a SPID that you really do want to ignore
	--for certain collection thresholds.

	DECLARE @tmpSPID INT, 
			@tmpDBID SMALLINT,
			@DynSQL VARCHAR(MAX);

	DECLARE iterateSPIDs CURSOR LOCAL FAST_FORWARD FOR 
	SELECT SessionID, DatabaseID 
	FROM @SPIDsToIB;

	OPEN iterateSPIDs
	FETCH iterateSPIDs INTO @tmpSPID, @tmpDBID;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		--print @tmp
		DELETE FROM @IBResults;
		SET @DynSQL = 'DBCC INPUTBUFFER(' + CONVERT(VARCHAR(20),@tmpSPID) + ') WITH NO_INFOMSGS;';

		BEGIN TRY
			INSERT INTO @IBResults
				EXEC (@DynSQL);
		END TRY
		BEGIN CATCH
			--no-op
		END CATCH

		INSERT INTO @SPIDsToFilter (SessionID)
		SELECT DISTINCT @tmpSPID
		FROM @IBResults t
		WHERE (
			t.InputBuffer LIKE '%some important text goes here%'
			)
		AND NOT EXISTS (SELECT * FROM @SPIDsToFilter t2
						WHERE t2.SessionID = @tmpSPID);


		FETCH iterateSPIDs INTO @tmpSPID, @tmpDBID;
	END

	CLOSE iterateSPIDs
	DEALLOCATE iterateSPIDs;
	*/

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_ThresholdFilterSpids ([ThresholdFilterSpid])
	SELECT DISTINCT t.SessionID
	FROM @SPIDsToFilter t;

	RETURN 0
END
GO