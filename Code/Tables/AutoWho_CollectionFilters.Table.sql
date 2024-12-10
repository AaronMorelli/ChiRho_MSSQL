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

	FILE NAME: AutoWho_CollectionFilters.Table.sql

	TABLE NAME: AutoWho_CollectionFilters

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Typically contains one or more types of filters (e.g. "session", or "database")
	along with the filtering value(s).
	NOTE: currently not planning to index this as this table should never have more than a few rows.
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.AutoWho_CollectionFilters (
	[CollectionInitiatorID]	[tinyint] NOT NULL,
	[FilterType] [tinyint] NOT NULL,
	[FilterID] [int] NOT NULL,
	[FilterName] [nvarchar](255) NULL
)
GO