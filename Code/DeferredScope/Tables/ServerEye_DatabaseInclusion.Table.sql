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

	FILE NAME: ServerEye_DatabaseInclusion.Table.sql

	TABLE NAME: ServerEye_DatabaseInclusion

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores a configurable list of database names and inclusion types so that the administrator of ChiRho can
		choose which databases are included in certain collections. For example, data from dm_db_index_operational_stats
		and dm_db_index_usage_stats is only gathered for databases in this table. 
*/
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DatabaseInclusion(
	[DBName] [nvarchar](128) NOT NULL,
	[InclusionType] [nvarchar](20) NOT NULL,
 CONSTRAINT [PKDatabaseInclusion] PRIMARY KEY CLUSTERED 
(
	[DBName] ASC,
	[InclusionType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_DatabaseInclusion  WITH CHECK ADD  CONSTRAINT [CK_DatabaseInclusion_InclusionType] CHECK  (([InclusionType]=N'IndexStats'))
GO
ALTER TABLE @@CHIRHO_SCHEMA@@.ServerEye_DatabaseInclusion CHECK CONSTRAINT [CK_DatabaseInclusion_InclusionType]
GO
