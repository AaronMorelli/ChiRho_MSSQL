USE DMVCompare
GO
declare 
	@old varchar(100)='2016 SP1',
	@new varchar(100)='2017 RTM';
;with old as (
	SELECT 
		vc.*
	FROM dbo.AllObjects ao
		INNER JOIN dbo.ViewColumns vc
			ON ao.object_id = vc.object_id
	WHERE ao.SQLVersion = @old
	AND vc.SQLVersion = @old
	--restrict this set just to objects that are also present in the new set
	--so that any new objects don't show up repeatedly for all of their columns
	AND EXISTS (
		SELECT * 
		FROM dbo.AllObjects ao2
		WHERE ao2.SQLVersion = @new 
		AND ao2.SchemaName = ao.SchemaName
		AND ao2.name = ao.name
	)
),
new as (
	SELECT 
		vc.*
	FROM dbo.AllObjects ao
		INNER JOIN dbo.ViewColumns vc
			ON ao.object_id = vc.object_id
	WHERE ao.SQLVersion = @new
	AND vc.SQLVersion = @new
	--restrict this set just to objects that are also present in the old set
	--so that any new objects don't show up repeatedly for all of their columns
	AND EXISTS (
		SELECT * 
		FROM dbo.AllObjects ao2
		WHERE ao2.SQLVersion = @old
		AND ao2.SchemaName = ao.SchemaName
		AND ao2.name = ao.name
	)
)
SELECT 
	o.SQLVersion,
	n.SQLVersion,
	ObjectName = ISNULL(o.ObjectName, n.ObjectName),
	old_type = o.type, 
	new_type = n.type,
	SchemaName = ISNULL(o.SchemaName, n.SchemaName),
	ColumnName = ISNULL(o.ColumnName, n.ColumnName),
	old_system_type = o.system_type_id,
	new_system_type = n.system_type_id,
	old_max_length = o.max_length,
	new_max_length = n.max_length,
	old_precision = o.precision,
	new_precision = n.precision,
	old_scale = o.scale,
	new_scale = n.scale,
	old_is_nullable = o.is_nullable,
	new_is_nullable = n.is_nullable
FROM old o
	FULL OUTER JOIN new n
		ON o.SchemaName = n.SchemaName
		AND o.ObjectName = n.ObjectName
		AND o.ColumnName = n.ColumnName
WHERE o.ColumnName IS NULL
OR n.ColumnName IS NULL
OR (
	o.ColumnName IS NOT NULL 
	AND n.ColumnName IS NOT NULL
	AND (
		ISNULL(CONVERT(int,o.system_type_id),-1) <> ISNULL(CONVERT(int,n.system_type_id),-1)
		OR ISNULL(CONVERT(int,o.max_length),-1) <> ISNULL(CONVERT(int,n.max_length),-1)
		OR ISNULL(CONVERT(int,o.precision),-1) <> ISNULL(CONVERT(int,n.precision),-1)
		OR ISNULL(CONVERT(int,o.scale),-1) <> ISNULL(CONVERT(int,n.scale),-1)
		--OR ISNULL(CONVERT(int,o.is_nullable),254) <> ISNULL(CONVERT(int,n.is_nullable),254)
	)
)
/*
WHERE ISNULL(o.ObjectName, n.ObjectName) NOT IN (
	'all_objects',
	'all_views',
	'assembly_types',
	'data_spaces',
	'database_principals',
	'databases',
	'dm_clr_appdomains',
)
*/
ORDER BY ISNULL(o.SchemaName, n.SchemaName),
	ISNULL(o.ObjectName, n.ObjectName),
	ISNULL(o.ColumnName, n.ColumnName)

