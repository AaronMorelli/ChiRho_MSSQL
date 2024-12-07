SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE @@CHIRHO_SCHEMA@@.AutoWho_LogRowCount
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

	FILE NAME: AutoWho_LogRowCount.StoredProcedure.sql

	PROCEDURE NAME: AutoWho_LogRowCount

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Wrapper proc to provide quick access to logging row counts.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC @@CHIRHO_SCHEMA@@.AutoWho_LogRowCount @ProcID=@@PROCID, @RC=@lv__RowCount, @TraceID=NULL, @Location='text that identifies the statement we just captured a rowcount for';
*/
(
	@ProcID			INT,
	@RC				BIGINT,
	@TraceID		INT,
	@Location		NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @ProcName NVARCHAR(256);

	IF @ProcID IS NOT NULL
	BEGIN
		SELECT 
			@ProcName = QUOTENAME(SCHEMA_NAME(o.schema_id)) + '.' + QUOTENAME(o.name)
		FROM sys.objects o
		WHERE o.object_id = @ProcID;
	END

	INSERT INTO @@CHIRHO_SCHEMA@@.AutoWho_Log(
		[LogDT],
		[LogDTUTC],
		[TraceID],
		[ProcID],
		[ProcName],
		[NestLevel],
		[RowCount],
		[AutoWhoCode],
		[LocationTag],
		[LogMessage]
	)
	SELECT
		[LogDT] = SYSDATETIME(), 
		[LogDTUTC] = SYSUTCDATETIME(),
		[TraceID] = @TraceID,
		[ProcID] = @ProcID,
		[ProcName] = @ProcName,
		[NestLevel] = @@NESTLEVEL - 1,
		[RowCount] = ISNULL(@RC,-1),
		[AutoWhoCode] = 5500,		--special code for AutoWho row-count logging
		[LocationTag] = ISNULL(@Location,'<null>'),
		[LogMessage] = '';		--not applicable

	RETURN 0;
END
GO