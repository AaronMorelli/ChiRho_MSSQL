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

	FILE NAME: CoreXR_CollectionInitiators.Table.sql

	TABLE NAME: CoreXR_CollectionInitiators

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: A simple lookup table mapping the IDs used for various "sections of code that trigger
		the collection of data". The ID is used in a number of tables, e.g. the AutoWho data collection
		tables, and allows the users of various sp_XR_* procs to choose whether they are reviewing 
		data captured by the standard AutoWho or ServerEye traces, or special "one-off" traces triggered
		through the sp_XR_* procs themselves.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.CoreXR_CollectionInitiators(
	[CollectionInitiatorID] [tinyint] NOT NULL,
	[CollectionInitiator] [nvarchar](100) NOT NULL,
 CONSTRAINT [PKCollectionInitiators] PRIMARY KEY CLUSTERED 
(
	[CollectionInitiatorID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

) ON [PRIMARY]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
