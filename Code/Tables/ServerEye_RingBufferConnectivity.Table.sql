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

	FILE NAME: ServerEye_RingBufferConnectivity.Table.sql

	TABLE NAME: ServerEye_RingBufferConnectivity

	AUTHOR:			Aaron Morelli
					aaronmorelli@zoho.com
					@sqlcrossjoin
					sqlcrossjoin.wordpress.com

	PURPOSE: Stores contents of the CONNECTIVITY ring buffer
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE @@CHIRHO_SCHEMA@@.ServerEye_RingBufferConnectivity(
	[SQLServerStartTime] [datetime] NOT NULL,
	[RecordID] [bigint] NOT NULL,
	[timestamp] [bigint] NOT NULL,
	[ExceptionTime] [datetime] NOT NULL,
	[UTCCaptureTime] [datetime] NOT NULL,
	[LocalCaptureTime] [datetime] NOT NULL,
	[RecordType] [nvarchar](128) NULL,
	[RecordSource] [nvarchar](64) NULL,
	[Spid] [int] NULL,
	[SniConnId] [nvarchar](128) NULL,
	[OSError] [int] NULL,
	[ClientConnectionId] [nvarchar](128) NULL,
	[SniConsumerError] [int] NULL,
	[SniProvider] [int] NULL,
	[State] [int] NULL,
	[RemoteHost] [nvarchar](128) NULL,
	[RemotePort] [int] NULL,
	[LocalHost] [nvarchar](128) NULL,
	[LocalPort] [int] NULL,
	[RecordTime] [nvarchar](64) NULL,
	[TdsBufInfo_InputBufError] [int] NULL,
	[TdsBufInfo_OutputBufError] [int] NULL,
	[TdsBufInfo_InputBufBytes] [int] NULL,
	[LoginTimers_TotalTime] [bigint] NULL,
	[LoginTimers_EnqueueTime] [bigint] NULL,
	[LoginTimers_NetWritesTime] [bigint] NULL,
	[LoginTimers_NetReadsTime] [bigint] NULL,
	[LoginTimersSSL_TotalTime] [bigint] NULL,
	[LoginTimersSSL_NetReadsTime] [bigint] NULL,
	[LoginTimersSSL_NetWritesTime] [bigint] NULL,
	[LoginTimersSSL_SecAPITime] [bigint] NULL,
	[LoginTimersSSL_EnqueueTime] [bigint] NULL,
	[LoginTimersSSPI_TotalTime] [bigint] NULL,
	[LoginTimersSSPI_NetReadsTime] [bigint] NULL,
	[LoginTimersSSPI_NetWritesTime] [bigint] NULL,
	[LoginTimersSSPI_SecAPITime] [bigint] NULL,
	[LoginTimersSSPI_EnqueueTime] [bigint] NULL,
	[LoginTimers_TriggerAndResGovTime] [bigint] NULL,
	[TdsDisconnectFlags_PhysicalConnectionIsKilled] [int] NULL,
	[TdsDisconnectFlags_DisconnectDueToReadError] [int] NULL,
	[TdsDisconnectFlags_NetworkErrorFoundInInputStream] [int] NULL,
	[TdsDisconnectFlags_ErrorFoundBeforeLogin] [int] NULL,
	[TdsDisconnectFlags_SessionIsKilled] [int] NULL,
	[TdsDisconnectFlags_NormalDisconnect] [int] NULL,
	[TdsDisconnectFlags_NormalLogout] [int] NULL,
 CONSTRAINT [PKRingBufferConnectivity] PRIMARY KEY NONCLUSTERED 
(
	[SQLServerStartTime] ASC,
	[RecordID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
CREATE CLUSTERED INDEX CL1 ON @@CHIRHO_SCHEMA@@.ServerEye_RingBufferConnectivity(UTCCaptureTime);
GO