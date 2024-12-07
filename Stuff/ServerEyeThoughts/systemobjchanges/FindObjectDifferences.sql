USE DMVCompare
GO
;with old as (
	SELECT *
	FROM dbo.AllObjects ao
	WHERE ao.SQLVersion = '2016 SP1'
),
new as (
	SELECT *
	FROM dbo.AllObjects ao
	WHERE ao.SQLVersion = '2017 RTM'
)
SELECT * 
FROM old o
	FULL OUTER JOIN new n
		ON o.SchemaName = n.SchemaName
		AND o.name = n.name
WHERE o.name IS NULL OR n.name IS NULL
ORDER BY ISNULL(o.name, n.name) ASC
