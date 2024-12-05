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

	FILE NAME: CoreXR.ProfilerTraceEvents.Table.sql

	TABLE NAME: CoreXR.ProfilerTraceEvents

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Currently not in use. Will hold a list of all SQL Server profiler events
	and whether they are being collected or not.
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE @@COREXR_SCHEMA@@.ProfilerTraceEvents(
	[EventGroup] [nvarchar](40) NOT NULL,
	[trace_event_id] [smallint] NOT NULL,
	[event_name] [nvarchar](128) NOT NULL,
	[category_name] [nvarchar](128) NOT NULL,
	[isEnabled] [nchar](1) NOT NULL,
 CONSTRAINT [PKProfilerTraceEvents] PRIMARY KEY CLUSTERED 
(
	[EventGroup] ASC,
	[trace_event_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING ON
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKProfileTraceEvents] ON @@COREXR_SCHEMA@@.ProfilerTraceEvents
(
	[EventGroup] ASC,
	[event_name] ASC,
	[category_name] ASC
)
INCLUDE ( 	[isEnabled]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
ALTER TABLE @@COREXR_SCHEMA@@.ProfilerTraceEvents  WITH CHECK ADD  CONSTRAINT [CK_ProfilerTraceEvents_isEnabled] CHECK  (([isEnabled]=N'N' OR [isEnabled]=N'Y'))
GO
ALTER TABLE @@COREXR_SCHEMA@@.ProfilerTraceEvents CHECK CONSTRAINT [CK_ProfilerTraceEvents_isEnabled]
GO
