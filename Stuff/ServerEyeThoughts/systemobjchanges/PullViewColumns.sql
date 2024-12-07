use DMVCompare 
go
INSERT INTO dbo.ViewColumns (
	SQLVersion,
	SQLBuild,
	ObjectName,
	object_id,
	schema_id,
	SchemaName,
	type,
	is_ms_shipped,
	ColumnName,
	column_id,
	system_type_id,
	max_length,
	precision,
	scale,
	is_nullable
)
SELECT 
	[SQLVersion] = CONVERT(VARCHAR(100),'2016 SP1'),
	[SQLBuild] = '13.0.4001.0',
	ObjectName = ao.name,
	ao.object_id,
	ao.schema_id,
	[SchemaName] = SCHEMA_NAME(ao.schema_id),
	ao.type,
	ao.is_ms_shipped,
	[ColumnName] = c.name,
	c.column_id,
	c.system_type_id,
	c.max_length,
	c.precision,
	c.scale,
	c.is_nullable
FROM DEVOPSDBA2.master.sys.all_objects ao
	INNER JOIN DEVOPSDBA2.master.sys.all_columns c
		on ao.object_id = c.object_id
WHERE ao.type IN ('U', 'V')

