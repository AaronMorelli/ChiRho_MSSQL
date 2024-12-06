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

	FILE NAME: ServerEye_DimUserProfileLogin.Table.sql

	TABLE NAME: ServerEye_DimUserProfileLogin

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores a unique combo of session attributes, essentially as a junk dimension
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimUserProfileLogin(
	[DimUserProfileLoginID]	[int] IDENTITY(1,1) NOT NULL,
	[security_id]			[varbinary](85) NOT NULL,
	[login_name]			[nvarchar](128) NOT NULL,
	[nt_domain]				[nvarchar](128) NOT NULL,
	[nt_user_name]			[nvarchar](128) NOT NULL,
	[original_security_id]	[varbinary](85) NOT NULL,
	[original_login_name]	[nvarchar](128) NOT NULL,
	[group_id]				[int] NOT NULL,
	[session_database_id]	[smallint] NOT NULL,
	[request_database_id]	[smallint] NOT NULL,
	[request_user_id]		[int] NOT NULL,
	[TimeAdded]				[datetime] NOT NULL,
	[TimeAddedUTC]			[datetime] NOT NULL,
 CONSTRAINT [PKDimUserProfileLogin] PRIMARY KEY CLUSTERED 
(
	[DimUserProfileLoginID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKDimUserProfileLogin] ON @@CHIRHO_SCHEMA@@.ServerEye_DimUserProfileLogin(
	[security_id],
	[login_name],
	[nt_domain],
	[nt_user_name],
	[original_security_id],
	[original_login_name],
	[group_id],
	[session_database_id],
	[request_database_id],
	[request_user_id]
);
GO