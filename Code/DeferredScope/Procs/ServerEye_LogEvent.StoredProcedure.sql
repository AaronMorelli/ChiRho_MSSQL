SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [ServerEye].[LogEvent]
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

	FILE NAME: ServerEye.LogEvent.StoredProcedure.sql

	PROCEDURE NAME: ServerEye.LogEvent

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Wrapper proc to provide quick access to logging errors, warnings, or informational events that occur.

	OUTSTANDING ISSUES: None at this time.

To Execute
------------------------
EXEC ServerEye.LogEvent @ProcID=@@PROCID, @EventCode=0, @TraceID=NULL, @Location='text that identifies the statement we just captured a rowcount for', @Message='The details of what is to be logged.';
*/
(
	@ProcID			INT,
	@EventCode		BIGINT,		--meaning is defined by the calling proc
	@TraceID		INT,
	@Location		NVARCHAR(100),
	@Message		NVARCHAR(MAX)
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

	INSERT INTO [ServerEye].[Log](
		[LogDT],
		[LogDTUTC],
		[TraceID],
		[ProcID],
		[ProcName],
		[NestLevel],
		[ServerEyeCode],
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
		[ServerEyeCode] = ISNULL(@EventCode,-9999999),
		[LocationTag] = ISNULL(@Location,'<null>'),
		[LogMessage] = ISNULL(@Message,'<null>');

	RETURN 0;
END
GO