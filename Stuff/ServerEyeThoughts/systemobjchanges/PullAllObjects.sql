use DMVCompare 
go
--CREATE UNIQUE CLUSTERED INDEX CL1 ON dbo.AllObjects(SQLVersion, object_id)
INSERT INTO dbo.AllObjects (
	SQLVersion,
	SQLBuild,
	object_id,
	type,
	name,
	schema_id, 
	SchemaName,
	is_ms_shipped
)
SELECT 
	[SQLVersion] = CONVERT(VARCHAR(100),'2016 SP1'),
	[SQLBuild] = '13.0.4001.0',
	ao.object_id,
	ao.type,
	ao.name,
	ao.schema_id,
	[SchemaName] = SCHEMA_NAME(ao.schema_id),
	ao.is_ms_shipped
FROM DEVOPSDBA2.master.sys.all_objects ao


