USE [DMVCompare]
GO

/****** Object:  Table [dbo].[AllObjects]    Script Date: 11/28/2017 04:03:58 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[AllObjects](
	[SQLVersion] [varchar](100) NULL,
	[SQLBuild] [varchar](50) NOT NULL,
	[object_id] [int] NOT NULL,
	[type] [char](2) NOT NULL,
	[name] [nvarchar](128) NOT NULL,
	[schema_id] [int] NOT NULL,
	[SchemaName] [nvarchar](128) NULL,
	[is_ms_shipped] [bit] NOT NULL
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO


