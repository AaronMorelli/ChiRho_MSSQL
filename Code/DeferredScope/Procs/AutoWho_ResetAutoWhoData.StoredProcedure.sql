SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_ResetAutoWhoData
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

	FILE NAME: AutoWho_ResetAutoWhoData.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_ResetAutoWhoData

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Clear out/reset all "collected" data in the AutoWho tables so that we can start testing
			over again. This proc is primarily aimed at development/testing

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
exec @@CHIRHO_SCHEMA@@.AutoWho_ResetAutoWhoData @DeleteConfig=N'N'
*/
(
	@DeleteConfig NCHAR(1)=N'N'
)
AS
BEGIN
	SET NOCOUNT ON;

	IF @DeleteConfig IS NULL OR UPPER(@DeleteConfig) NOT IN (N'N', N'Y')
	BEGIN
		SET @DeleteConfig = N'N';
	END

	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LightweightSessions;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LightweightTasks;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LightweightTrans;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_LockDetails;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_TransactionDetails;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_TasksAndWaits;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_SessionsAndRequests;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_BlockingGraphs;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_ThresholdFilterSpids;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_SARException;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_TAWException;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_SignalTable;

	--We have pre-reserved certain ID values for certain dimension members, so we need to keep those.
	DELETE FROM @@CHIRHO_SCHEMA@@.AutoWho_DimCommand WHERE DimCommandID > 3;
	DELETE FROM @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute WHERE DimConnectionAttributeID > 1;
	DELETE FROM @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName WHERE DimLoginNameID > 2;
	DELETE FROM @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress WHERE DimNetAddressID > 2;
	DELETE FROM @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute WHERE DimSessionAttributeID > 1;
	DELETE @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType WHERE DimWaitTypeID > 2;

	DELETE FROM @@CHIRHO_SCHEMA@@.CoreXR_OrdinalCachePosition WHERE Utility IN (N'AutoWho',N'SessionViewer',N'QueryProgress');
	DELETE FROM @@CHIRHO_SCHEMA@@.CoreXR_CaptureOrdinalCache WHERE Utility IN (N'AutoWho', N'SessionViewer', N'QueryProgress');
	DELETE FROM @@CHIRHO_SCHEMA@@.CoreXR_Traces WHERE Utility = N'AutoWho';

	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_CaptureSummary;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_CaptureTimes;
	TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_Log;

	IF @DeleteConfig = N'Y'
	BEGIN
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_CollectorOptFakeout;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_Options;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_Options_History;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.CoreXR_Version;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.CoreXR_Version_History;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimCommand;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimConnectionAttribute;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimLoginName;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimNetAddress;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimSessionAttribute;
		TRUNCATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_DimWaitType;
	END

	RETURN 0;
END
GO