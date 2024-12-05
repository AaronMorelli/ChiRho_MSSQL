/*
   Copyright 2024 Aaron Morelli

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

	FILE NAME: CoreXR.Traces.Table.sql

	TABLE NAME: CoreXR.Traces

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Table for storing generic trace entities used by various
	components in the ChiRho system
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@COREXR_SCHEMA@@.Traces(
	[TraceID] [int] IDENTITY(1,1) NOT NULL,
	[Utility] [nvarchar](20) NOT NULL,
	[Type] [nvarchar](20) NOT NULL CONSTRAINT [DF_CoreXRTraces_Type]  DEFAULT (N'N''Background'),
	[CreateTime] [datetime] NOT NULL CONSTRAINT [DF_CoreXRTraces_CreateTime]  DEFAULT (getdate()),
	[CreateTimeUTC] [datetime] NOT NULL CONSTRAINT [DF_CoreXRTraces_CreateTimeUTC]  DEFAULT (getutcdate()),
	[IntendedStopTime] [datetime] NOT NULL,
	[IntendedStopTimeUTC] [datetime] NOT NULL,
	[StopTime] [datetime] NULL,
	[StopTimeUTC] [datetime] NULL,
	[AbortCode] [nchar](1) NULL,
	[TerminationMessage] [nvarchar](MAX) NULL,
	[Payload_int] [int] NULL,
	[Payload_bigint] [bigint] NULL, 
	[Payload_decimal] [decimal](28,9) NULL,
	[Payload_datetime] [datetime] NULL,
	[Payload_datetimeUTC] [datetime] NULL,
	[Payload_nvarchar] [nvarchar](MAX) NULL
 CONSTRAINT [PKCoreXRTraces] PRIMARY KEY CLUSTERED 
(
	[TraceID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
