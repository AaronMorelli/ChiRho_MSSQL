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

	FILE NAME: dbo.CoreXRFiltersType.UserDefinedTableType.sql

	TYPE NAME: dbo.CoreXRFiltersType

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: This table type is passed around as a parameter and typically
	contains one or more types of filters (e.g. "session", or "database")
	along with the filtering value(s).
*/
CREATE TYPE [dbo].[CoreXRFiltersType] AS TABLE(
	[FilterType] [tinyint] NOT NULL,
	[FilterID] [int] NOT NULL,
	[FilterName] [nvarchar](255) NULL
)
GO
