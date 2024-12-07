USE [DMVCompare]
GO

/****** Object:  Table [dbo].[ViewColumns]    Script Date: 11/28/2017 04:04:04 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[ViewColumns](
	[SQLVersion] [varchar](100) NULL,
	[SQLBuild] [varchar](50) NOT NULL,
	[ObjectName] [nvarchar](128) NOT NULL,
	[object_id] [int] NOT NULL,
	[schema_id] [int] NOT NULL,
	[SchemaName] [nvarchar](128) NULL,
	[type] [char](2) NOT NULL,
	[is_ms_shipped] [bit] NOT NULL,
	[ColumnName] [nvarchar](128) NULL,
	[column_id] [int] NOT NULL,
	[system_type_id] [tinyint] NOT NULL,
	[max_length] [smallint] NOT NULL,
	[precision] [tinyint] NOT NULL,
	[scale] [tinyint] NOT NULL,
	[is_nullable] [bit] NULL
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO


