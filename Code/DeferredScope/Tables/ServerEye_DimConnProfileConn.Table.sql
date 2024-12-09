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

	FILE NAME: ServerEye_DimUserProfileConn.Table.sql

	TABLE NAME: ServerEye_DimUserProfileConn

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores a unique combo of connection attributes, essentially as a junk dimension
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_DimUserProfileConn(
	[DimUserProfileConnID]	[int] IDENTITY(1,1) NOT NULL,
	[net_transport]		[nvarchar](40) NOT NULL,
	[protocol_type]		[nvarchar](40) NOT NULL,
	[protocol_version]	[int] NOT NULL,
	[endpoint_id]		[int] NOT NULL,
	[encrypt_option]	[nvarchar](40) NOT NULL,
	[auth_scheme]		[nvarchar](40) NOT NULL,
	[node_affinity]		[smallint] NOT NULL,
	[net_packet_size]	[int] NOT NULL,
	[client_net_address] [varchar](48) NOT NULL,
	[local_net_address]	[varchar](48) NOT NULL,
	[local_tcp_port]	[int] NOT NULL,
	[TimeAdded]			[datetime] NOT NULL,
	[TimeAddedUTC]		[datetime] NOT NULL,
 CONSTRAINT [PKDimUserProfileConn] PRIMARY KEY CLUSTERED 
(
	[DimUserProfileConnID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [AKDimUserProfileConn] ON @@CHIRHO_SCHEMA@@.ServerEye_DimUserProfileConn(
	[net_transport],
	[protocol_type],
	[protocol_version],
	[endpoint_id],
	[encrypt_option],
	[auth_scheme],
	[node_affinity],
	[net_packet_size],
	[client_net_address],
	[local_net_address],
	[local_tcp_port]
);
GO