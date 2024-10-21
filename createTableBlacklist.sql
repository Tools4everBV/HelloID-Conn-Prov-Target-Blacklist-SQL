USE Blacklist
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[blacklist](
	[attributeName] [nvarchar](50) NOT NULL,
	[attributeValue] [nvarchar](50) NOT NULL,
	[employeeId] [nvarchar](50) NOT NULL,
	[whenDeleted] [date] NULL
) ON [PRIMARY]
GO

CREATE NONCLUSTERED INDEX [IX_blacklist] ON [dbo].[blacklist]
(
	[attributeName] ASC,
	[attributeValue] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

SET ANSI_PADDING ON
GO

CREATE NONCLUSTERED INDEX [IX_blacklist_1] ON [dbo].[blacklist]
(
	[attributeValue] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

SET ANSI_PADDING ON
GO

CREATE NONCLUSTERED INDEX [IX_blacklist_2] ON [dbo].[blacklist]
(
	[employeeId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

SET ANSI_PADDING ON
GO