select
	/* 
	maxObjectName = max(len(object_name)),
	maxCounterName = max(len(counter_name)),
	maxInstanceName = max(len(instance_name))
	*/
	object_name = substring(object_name, 1, 40),
	counter_name = substring(counter_name,1,60),
	instance_name = substring(instance_name,1,80)
from sys.dm_os_performance_counters pc
order by pc.object_name, pc.counter_name, pc.instance_name

/* This was run on a SQL 2014 instance



--Feature-specific, unlikely to use anytime soon
SQLServer:Availability Replica          	Bytes Received from Replica/sec                             	_Total                                                                          
SQLServer:Availability Replica          	Bytes Sent to Replica/sec                                   	_Total                                                                          
SQLServer:Availability Replica          	Bytes Sent to Transport/sec                                 	_Total                                                                          
SQLServer:Availability Replica          	Flow Control Time (ms/sec)                                  	_Total                                                                          
SQLServer:Availability Replica          	Flow Control/sec                                            	_Total                                                                          
SQLServer:Availability Replica          	Receives from Replica/sec                                   	_Total                                                                          
SQLServer:Availability Replica          	Resent Messages/sec                                         	_Total                                                                          
SQLServer:Availability Replica          	Sends to Replica/sec                                        	_Total                                                                          
SQLServer:Availability Replica          	Sends to Transport/sec                                      	_Total                                                                          
SQLServer:Broker Activation             	Stored Procedures Invoked/sec                               	_Total                                                                          
SQLServer:Broker Activation             	Stored Procedures Invoked/sec                               	<dbname>
SQLServer:Broker Activation             	Stored Procedures Invoked/sec                               	tempdb                                                                          
SQLServer:Broker Activation             	Task Limit Reached                                          	_Total                                                                          
SQLServer:Broker Activation             	Task Limit Reached                                          	<dbname>
SQLServer:Broker Activation             	Task Limit Reached                                          	tempdb                                                                          
SQLServer:Broker Activation             	Task Limit Reached/sec                                      	_Total                                                                          
SQLServer:Broker Activation             	Task Limit Reached/sec                                      	<dbname>
SQLServer:Broker Activation             	Task Limit Reached/sec                                      	tempdb                                                                          
SQLServer:Broker Activation             	Tasks Aborted/sec                                           	_Total                                                                          
SQLServer:Broker Activation             	Tasks Aborted/sec                                           	<dbname>
SQLServer:Broker Activation             	Tasks Aborted/sec                                           	tempdb                                                                          
SQLServer:Broker Activation             	Tasks Running                                               	_Total                                                                          
SQLServer:Broker Activation             	Tasks Running                                               	<dbname>
SQLServer:Broker Activation             	Tasks Running                                               	tempdb                                                                          
SQLServer:Broker Activation             	Tasks Started/sec                                           	_Total                                                                          
SQLServer:Broker Activation             	Tasks Started/sec                                           	<dbname>
SQLServer:Broker Activation             	Tasks Started/sec                                           	tempdb                                                                          
SQLServer:Broker Statistics             	Activation Errors Total                                     	                                                                                
SQLServer:Broker Statistics             	Broker Transaction Rollbacks                                	                                                                                
SQLServer:Broker Statistics             	Corrupted Messages Total                                    	                                                                                
SQLServer:Broker Statistics             	Dequeued TransmissionQ Msgs/sec                             	                                                                                
SQLServer:Broker Statistics             	Dialog Timer Event Count                                    	                                                                                
SQLServer:Broker Statistics             	Dropped Messages Total                                      	                                                                                
SQLServer:Broker Statistics             	Enqueued Local Messages Total                               	                                                                                
SQLServer:Broker Statistics             	Enqueued Local Messages/sec                                 	                                                                                
SQLServer:Broker Statistics             	Enqueued Messages Total                                     	                                                                                
SQLServer:Broker Statistics             	Enqueued Messages/sec                                       	                                                                                
SQLServer:Broker Statistics             	Enqueued P1 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P10 Messages/sec                                   	                                                                                
SQLServer:Broker Statistics             	Enqueued P2 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P3 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P4 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P5 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P6 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P7 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P8 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued P9 Messages/sec                                    	                                                                                
SQLServer:Broker Statistics             	Enqueued TransmissionQ Msgs/sec                             	                                                                                
SQLServer:Broker Statistics             	Enqueued Transport Msg Frag Tot                             	                                                                                
SQLServer:Broker Statistics             	Enqueued Transport Msg Frags/sec                            	                                                                                
SQLServer:Broker Statistics             	Enqueued Transport Msgs Total                               	                                                                                
SQLServer:Broker Statistics             	Enqueued Transport Msgs/sec                                 	                                                                                
SQLServer:Broker Statistics             	Forwarded Messages Total                                    	                                                                                
SQLServer:Broker Statistics             	Forwarded Messages/sec                                      	                                                                                
SQLServer:Broker Statistics             	Forwarded Msg Byte Total                                    	                                                                                
SQLServer:Broker Statistics             	Forwarded Msg Bytes/sec                                     	                                                                                
SQLServer:Broker Statistics             	Forwarded Msg Discarded Total                               	                                                                                
SQLServer:Broker Statistics             	Forwarded Msgs Discarded/sec                                	                                                                                
SQLServer:Broker Statistics             	Forwarded Pending Msg Bytes                                 	                                                                                
SQLServer:Broker Statistics             	Forwarded Pending Msg Count                                 	                                                                                
SQLServer:Broker Statistics             	SQL RECEIVE Total                                           	                                                                                
SQLServer:Broker Statistics             	SQL RECEIVEs/sec                                            	                                                                                
SQLServer:Broker Statistics             	SQL SEND Total                                              	                                                                                
SQLServer:Broker Statistics             	SQL SENDs/sec                                               	                                                                                
SQLServer:Broker TO Statistics          	Avg. Length of Batched Writes                               	                                                                                
SQLServer:Broker TO Statistics          	Avg. Length of Batched Writes BS                            	                                                                                
SQLServer:Broker TO Statistics          	Avg. Time Between Batches (ms)                              	                                                                                
SQLServer:Broker TO Statistics          	Avg. Time Between Batches Base                              	                                                                                
SQLServer:Broker TO Statistics          	Avg. Time to Write Batch (ms)                               	                                                                                
SQLServer:Broker TO Statistics          	Avg. Time to Write Batch Base                               	                                                                                
SQLServer:Broker TO Statistics          	Transmission Obj Gets/Sec                                   	                                                                                
SQLServer:Broker TO Statistics          	Transmission Obj Set Dirty/Sec                              	                                                                                
SQLServer:Broker TO Statistics          	Transmission Obj Writes/Sec                                 	                                                                                
SQLServer:Broker/DBM Transport          	Current Bytes for Recv I/O                                  	                                                                                
SQLServer:Broker/DBM Transport          	Current Bytes for Send I/O                                  	                                                                                
SQLServer:Broker/DBM Transport          	Current Msg Frags for Send I/O                              	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P1 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P10 Sends/sec                              	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P2 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P3 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P4 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P5 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P6 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P7 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P8 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment P9 Sends/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment Receives/sec                               	                                                                                
SQLServer:Broker/DBM Transport          	Message Fragment Sends/sec                                  	                                                                                
SQLServer:Broker/DBM Transport          	Msg Fragment Recv Size Avg                                  	                                                                                
SQLServer:Broker/DBM Transport          	Msg Fragment Recv Size Avg Base                             	                                                                                
SQLServer:Broker/DBM Transport          	Msg Fragment Send Size Avg                                  	                                                                                
SQLServer:Broker/DBM Transport          	Msg Fragment Send Size Avg Base                             	                                                                                
SQLServer:Broker/DBM Transport          	Open Connection Count                                       	                                                                                
SQLServer:Broker/DBM Transport          	Pending Bytes for Recv I/O                                  	                                                                                
SQLServer:Broker/DBM Transport          	Pending Bytes for Send I/O                                  	                                                                                
SQLServer:Broker/DBM Transport          	Pending Msg Frags for Recv I/O                              	                                                                                
SQLServer:Broker/DBM Transport          	Pending Msg Frags for Send I/O                              	                                                                                
SQLServer:Broker/DBM Transport          	Receive I/O bytes/sec                                       	                                                                                
SQLServer:Broker/DBM Transport          	Receive I/O Len Avg                                         	                                                                                
SQLServer:Broker/DBM Transport          	Receive I/O Len Avg Base                                    	                                                                                
SQLServer:Broker/DBM Transport          	Receive I/Os/sec                                            	                                                                                
SQLServer:Broker/DBM Transport          	Recv I/O Buffer Copies bytes/sec                            	                                                                                
SQLServer:Broker/DBM Transport          	Recv I/O Buffer Copies Count                                	                                                                                
SQLServer:Broker/DBM Transport          	Send I/O bytes/sec                                          	                                                                                
SQLServer:Broker/DBM Transport          	Send I/O Len Avg                                            	                                                                                
SQLServer:Broker/DBM Transport          	Send I/O Len Avg Base                                       	                                                                                
SQLServer:Broker/DBM Transport          	Send I/Os/sec                                               	                                                                                
SQLServer:CLR                           	CLR Execution                                               	                 
SQLServer:Database Replica              	File Bytes Received/sec                                     	_Total                                                                          
SQLServer:Database Replica              	Log Bytes Received/sec                                      	_Total                                                                          
SQLServer:Database Replica              	Log remaining for undo                                      	_Total                                                                          
SQLServer:Database Replica              	Log Send Queue                                              	_Total                                                                          
SQLServer:Database Replica              	Mirrored Write Transactions/sec                             	_Total                                                                          
SQLServer:Database Replica              	Recovery Queue                                              	_Total                                                                          
SQLServer:Database Replica              	Redo blocked/sec                                            	_Total                                                                          
SQLServer:Database Replica              	Redo Bytes Remaining                                        	_Total                                                                          
SQLServer:Database Replica              	Redone Bytes/sec                                            	_Total                                                                          
SQLServer:Database Replica              	Total Log requiring undo                                    	_Total                                                                          
SQLServer:Database Replica              	Transaction Delay                                           	_Total                                                                          

SQLServer:Databases                     	Log Pool Cache Misses/sec                                   	_Total                                                                          
SQLServer:Databases                     	Log Pool Cache Misses/sec                                   	<dbname>
SQLServer:Databases                     	Log Pool Cache Misses/sec                                   	tempdb                                                                          
SQLServer:Databases                     	Log Pool Disk Reads/sec                                     	_Total                                                                          
SQLServer:Databases                     	Log Pool Disk Reads/sec                                     	<dbname>
SQLServer:Databases                     	Log Pool Disk Reads/sec                                     	tempdb                                                                          
SQLServer:Databases                     	Log Pool Requests/sec                                       	_Total
SQLServer:Databases                     	Log Pool Requests/sec                                       	tempdb
SQLServer:Databases                     	Repl. Pending Xacts                                         	_Total
SQLServer:Databases                     	Repl. Trans. Rate                                           	_Total
SQLServer:Databases                     	XTP Memory Used (KB)                                        	_Total                                                                          
SQLServer:Databases                     	XTP Memory Used (KB)                                        	<dbname>
SQLServer:Deprecated Features           	Usage                                                       	'#' and '##' as the name of temporary tables and stored procedures              
SQLServer:Deprecated Features           	Usage                                                       	'::' function calling syntax                                                    
SQLServer:Deprecated Features           	Usage                                                       	'@' and names that start with '@@' as Transact-SQL identifiers                  
SQLServer:Deprecated Features           	Usage                                                       	ADDING TAPE DEVICE                                                              
SQLServer:Deprecated Features           	Usage                                                       	ALL Permission                                                                  
SQLServer:Deprecated Features           	Usage                                                       	ALTER DATABASE WITH TORN_PAGE_DETECTION                                         
SQLServer:Deprecated Features           	Usage                                                       	ALTER LOGIN WITH SET CREDENTIAL                                                 
SQLServer:Deprecated Features           	Usage                                                       	asymmetric_keys                                                                 
SQLServer:Deprecated Features           	Usage                                                       	asymmetric_keys.attested_by                                                     
SQLServer:Deprecated Features           	Usage                                                       	Azeri_Cyrillic_90                                                               
SQLServer:Deprecated Features           	Usage                                                       	Azeri_Latin_90                                                                  
SQLServer:Deprecated Features           	Usage                                                       	BACKUP DATABASE or LOG TO TAPE                                                  
SQLServer:Deprecated Features           	Usage                                                       	certificates                                                                    
SQLServer:Deprecated Features           	Usage                                                       	certificates.attested_by                                                        
SQLServer:Deprecated Features           	Usage                                                       	Create/alter SOAP endpoint                                                      
SQLServer:Deprecated Features           	Usage                                                       	CREATE_DROP_DEFAULT                                                             
SQLServer:Deprecated Features           	Usage                                                       	CREATE_DROP_RULE                                                                
SQLServer:Deprecated Features           	Usage                                                       	Data types: text ntext or image                                                 
SQLServer:Deprecated Features           	Usage                                                       	Database compatibility level 100                                                
SQLServer:Deprecated Features           	Usage                                                       	Database compatibility level 110                                                
SQLServer:Deprecated Features           	Usage                                                       	Database compatibility level 90                                                 
SQLServer:Deprecated Features           	Usage                                                       	Database Mirroring                                                              
SQLServer:Deprecated Features           	Usage                                                       	DATABASEPROPERTY                                                                
SQLServer:Deprecated Features           	Usage                                                       	DATABASEPROPERTYEX('IsFullTextEnabled')                                         
SQLServer:Deprecated Features           	Usage                                                       	DBCC [UN]PINTABLE                                                               
SQLServer:Deprecated Features           	Usage                                                       	DBCC DBREINDEX                                                                  
SQLServer:Deprecated Features           	Usage                                                       	DBCC INDEXDEFRAG                                                                
SQLServer:Deprecated Features           	Usage                                                       	DBCC SHOWCONTIG                                                                 
SQLServer:Deprecated Features           	Usage                                                       	DBCC_EXTENTINFO                                                                 
SQLServer:Deprecated Features           	Usage                                                       	DBCC_IND                                                                        
SQLServer:Deprecated Features           	Usage                                                       	DEFAULT keyword as a default value                                              
SQLServer:Deprecated Features           	Usage                                                       	Deprecated Attested Option                                                      
SQLServer:Deprecated Features           	Usage                                                       	Deprecated encryption algorithm                                                 
SQLServer:Deprecated Features           	Usage                                                       	DESX algorithm                                                                  
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs                                                          
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.is_paused                                                
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.previous_status                                          
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.previous_status_description                              
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.row_count_in_thousands                                   
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.status                                                   
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.status_description                                       
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_active_catalogs.worker_count                                             
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_memory_buffers                                                           
SQLServer:Deprecated Features           	Usage                                                       	dm_fts_memory_buffers.row_count                                                 
SQLServer:Deprecated Features           	Usage                                                       	DROP INDEX with two-part name                                                   
SQLServer:Deprecated Features           	Usage                                                       	endpoint_webmethods                                                             
SQLServer:Deprecated Features           	Usage                                                       	EXTPROP_LEVEL0TYPE                                                              
SQLServer:Deprecated Features           	Usage                                                       	EXTPROP_LEVEL0USER                                                              
SQLServer:Deprecated Features           	Usage                                                       	FILE_ID                                                                         
SQLServer:Deprecated Features           	Usage                                                       	fn_get_sql                                                                      
SQLServer:Deprecated Features           	Usage                                                       	fn_servershareddrives                                                           
SQLServer:Deprecated Features           	Usage                                                       	fn_trace_geteventinfo                                                           
SQLServer:Deprecated Features           	Usage                                                       	fn_trace_getfilterinfo                                                          
SQLServer:Deprecated Features           	Usage                                                       	fn_trace_getinfo                                                                
SQLServer:Deprecated Features           	Usage                                                       	fn_trace_gettable                                                               
SQLServer:Deprecated Features           	Usage                                                       	fn_virtualservernodes                                                           
SQLServer:Deprecated Features           	Usage                                                       	fulltext_catalogs                                                               
SQLServer:Deprecated Features           	Usage                                                       	fulltext_catalogs.data_space_id                                                 
SQLServer:Deprecated Features           	Usage                                                       	fulltext_catalogs.file_id                                                       
SQLServer:Deprecated Features           	Usage                                                       	fulltext_catalogs.path                                                          
SQLServer:Deprecated Features           	Usage                                                       	FULLTEXTCATALOGPROPERTY('LogSize')                                              
SQLServer:Deprecated Features           	Usage                                                       	FULLTEXTCATALOGPROPERTY('PopulateStatus')                                       
SQLServer:Deprecated Features           	Usage                                                       	FULLTEXTSERVICEPROPERTY('ConnectTimeout')                                       
SQLServer:Deprecated Features           	Usage                                                       	FULLTEXTSERVICEPROPERTY('DataTimeout')                                          
SQLServer:Deprecated Features           	Usage                                                       	FULLTEXTSERVICEPROPERTY('ResourceUsage')                                        
SQLServer:Deprecated Features           	Usage                                                       	GROUP BY ALL                                                                    
SQLServer:Deprecated Features           	Usage                                                       	Hindi                                                                           
SQLServer:Deprecated Features           	Usage                                                       	IDENTITYCOL                                                                     
SQLServer:Deprecated Features           	Usage                                                       	IN PATH                                                                         
SQLServer:Deprecated Features           	Usage                                                       	Index view select list without COUNT_BIG(*)                                     
SQLServer:Deprecated Features           	Usage                                                       	INDEX_OPTION                                                                    
SQLServer:Deprecated Features           	Usage                                                       	INDEXKEY_PROPERTY                                                               
SQLServer:Deprecated Features           	Usage                                                       	Indirect TVF hints                                                              
SQLServer:Deprecated Features           	Usage                                                       	INSERT NULL into TIMESTAMP columns                                              
SQLServer:Deprecated Features           	Usage                                                       	INSERT_HINTS                                                                    
SQLServer:Deprecated Features           	Usage                                                       	Korean_Wansung_Unicode                                                          
SQLServer:Deprecated Features           	Usage                                                       	Lithuanian_Classic                                                              
SQLServer:Deprecated Features           	Usage                                                       	Macedonian                                                                      
SQLServer:Deprecated Features           	Usage                                                       	MODIFY FILEGROUP READONLY                                                       
SQLServer:Deprecated Features           	Usage                                                       	MODIFY FILEGROUP READWRITE                                                      
SQLServer:Deprecated Features           	Usage                                                       	More than two-part column name                                                  
SQLServer:Deprecated Features           	Usage                                                       	Multiple table hints without comma                                              
SQLServer:Deprecated Features           	Usage                                                       	NOLOCK or READUNCOMMITTED in UPDATE or DELETE                                   
SQLServer:Deprecated Features           	Usage                                                       	Numbered stored procedures                                                      
SQLServer:Deprecated Features           	Usage                                                       	numbered_procedure_parameters                                                   
SQLServer:Deprecated Features           	Usage                                                       	numbered_procedures                                                             
SQLServer:Deprecated Features           	Usage                                                       	objidupdate                                                                     
SQLServer:Deprecated Features           	Usage                                                       	Old NEAR Syntax                                                                 
SQLServer:Deprecated Features           	Usage                                                       	OLEDB for ad hoc connections                                                    
SQLServer:Deprecated Features           	Usage                                                       	PERMISSIONS                                                                     
SQLServer:Deprecated Features           	Usage                                                       	READTEXT                                                                        
SQLServer:Deprecated Features           	Usage                                                       	REMSERVER                                                                       
SQLServer:Deprecated Features           	Usage                                                       	RESTORE DATABASE or LOG WITH MEDIAPASSWORD                                      
SQLServer:Deprecated Features           	Usage                                                       	RESTORE DATABASE or LOG WITH PASSWORD                                           
SQLServer:Deprecated Features           	Usage                                                       	Returning results from trigger                                                  
SQLServer:Deprecated Features           	Usage                                                       	ROWGUIDCOL                                                                      
SQLServer:Deprecated Features           	Usage                                                       	SET ANSI_NULLS OFF                                                              
SQLServer:Deprecated Features           	Usage                                                       	SET ANSI_PADDING OFF                                                            
SQLServer:Deprecated Features           	Usage                                                       	SET CONCAT_NULL_YIELDS_NULL OFF                                                 
SQLServer:Deprecated Features           	Usage                                                       	SET ERRLVL                                                                      
SQLServer:Deprecated Features           	Usage                                                       	SET FMTONLY ON                                                                  
SQLServer:Deprecated Features           	Usage                                                       	SET OFFSETS                                                                     
SQLServer:Deprecated Features           	Usage                                                       	SET REMOTE_PROC_TRANSACTIONS                                                    
SQLServer:Deprecated Features           	Usage                                                       	SET ROWCOUNT                                                                    
SQLServer:Deprecated Features           	Usage                                                       	SETUSER                                                                         
SQLServer:Deprecated Features           	Usage                                                       	soap_endpoints                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_addapprole                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_addextendedproc                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_addlogin                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_addremotelogin                                                               
SQLServer:Deprecated Features           	Usage                                                       	sp_addrole                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sp_addrolemember                                                                
SQLServer:Deprecated Features           	Usage                                                       	sp_addserver                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_addsrvrolemember                                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_addtype                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sp_adduser                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sp_approlepassword                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_attach_db                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_attach_single_file_db                                                        
SQLServer:Deprecated Features           	Usage                                                       	sp_bindefault                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_bindrule                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_bindsession                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_certify_removable                                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_change_users_login                                                           
SQLServer:Deprecated Features           	Usage                                                       	sp_changedbowner                                                                
SQLServer:Deprecated Features           	Usage                                                       	sp_changeobjectowner                                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'affinity mask'                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'affinity64 mask'                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'allow updates'                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'c2 audit mode'                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'default trace enabled'                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'disallow results from triggers'                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'ft crawl bandwidth (max)'                                         
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'ft crawl bandwidth (min)'                                         
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'ft notify bandwidth (max)'                                        
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'ft notify bandwidth (min)'                                        
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'locks'                                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'open objects'                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'priority boost'                                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'remote proc trans'                                                
SQLServer:Deprecated Features           	Usage                                                       	sp_configure 'set working set size'                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_control_dbmasterkey_password                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_create_removable                                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_db_increased_partitions                                                      
SQLServer:Deprecated Features           	Usage                                                       	sp_db_selective_xml_index                                                       
SQLServer:Deprecated Features           	Usage                                                       	sp_db_vardecimal_storage_format                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_dbcmptlevel                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_dbfixedrolepermission                                                        
SQLServer:Deprecated Features           	Usage                                                       	sp_dbremove                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_defaultdb                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_defaultlanguage                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_denylogin                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_depends                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sp_detach_db @keepfulltextindexfile                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_dropapprole                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_dropextendedproc                                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_droplogin                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sp_dropremotelogin                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_droprole                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_droprolemember                                                               
SQLServer:Deprecated Features           	Usage                                                       	sp_dropsrvrolemember                                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_droptype                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_dropuser                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_estimated_rowsize_reduction_for_vardecimal                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_catalog                                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_column                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_database                                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_service @action=clean_up                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_service @action=connect_timeout                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_service @action=data_timeout                                        
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_service @action=resource_usage                                      
SQLServer:Deprecated Features           	Usage                                                       	sp_fulltext_table                                                               
SQLServer:Deprecated Features           	Usage                                                       	sp_getbindtoken                                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_grantdbaccess                                                                
SQLServer:Deprecated Features           	Usage                                                       	sp_grantlogin                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_catalog_components                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_catalogs                                                       
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_catalogs_cursor                                                
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_columns                                                        
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_columns_cursor                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_tables                                                         
SQLServer:Deprecated Features           	Usage                                                       	sp_help_fulltext_tables_cursor                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_helpdevice                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sp_helpextendedproc                                                             
SQLServer:Deprecated Features           	Usage                                                       	sp_helpremotelogin                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_indexoption                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_lock                                                                         
SQLServer:Deprecated Features           	Usage                                                       	sp_password                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_remoteoption                                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_renamedb                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sp_resetstatus                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_revokedbaccess                                                               
SQLServer:Deprecated Features           	Usage                                                       	sp_revokelogin                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sp_srvrolepermission                                                            
SQLServer:Deprecated Features           	Usage                                                       	sp_trace_create                                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_trace_getdata                                                                
SQLServer:Deprecated Features           	Usage                                                       	sp_trace_setevent                                                               
SQLServer:Deprecated Features           	Usage                                                       	sp_trace_setfilter                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_trace_setstatus                                                              
SQLServer:Deprecated Features           	Usage                                                       	sp_unbindefault                                                                 
SQLServer:Deprecated Features           	Usage                                                       	sp_unbindrule                                                                   
SQLServer:Deprecated Features           	Usage                                                       	SQL_AltDiction_CP1253_CS_AS                                                     
SQLServer:Deprecated Features           	Usage                                                       	sql_dependencies                                                                
SQLServer:Deprecated Features           	Usage                                                       	String literals as column aliases                                               
SQLServer:Deprecated Features           	Usage                                                       	sysaltfiles                                                                     
SQLServer:Deprecated Features           	Usage                                                       	syscacheobjects                                                                 
SQLServer:Deprecated Features           	Usage                                                       	syscolumns                                                                      
SQLServer:Deprecated Features           	Usage                                                       	syscomments                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sysconfigures                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sysconstraints                                                                  
SQLServer:Deprecated Features           	Usage                                                       	syscurconfigs                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sysdatabases                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sysdepends                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sysdevices                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sysfilegroups                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sysfiles                                                                        
SQLServer:Deprecated Features           	Usage                                                       	sysforeignkeys                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sysfulltextcatalogs                                                             
SQLServer:Deprecated Features           	Usage                                                       	sysindexes                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sysindexkeys                                                                    
SQLServer:Deprecated Features           	Usage                                                       	syslockinfo                                                                     
SQLServer:Deprecated Features           	Usage                                                       	syslogins                                                                       
SQLServer:Deprecated Features           	Usage                                                       	sysmembers                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sysmessages                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sysobjects                                                                      
SQLServer:Deprecated Features           	Usage                                                       	sysoledbusers                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sysopentapes                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sysperfinfo                                                                     
SQLServer:Deprecated Features           	Usage                                                       	syspermissions                                                                  
SQLServer:Deprecated Features           	Usage                                                       	sysprocesses                                                                    
SQLServer:Deprecated Features           	Usage                                                       	sysprotects                                                                     
SQLServer:Deprecated Features           	Usage                                                       	sysreferences                                                                   
SQLServer:Deprecated Features           	Usage                                                       	sysremotelogins                                                                 
SQLServer:Deprecated Features           	Usage                                                       	sysservers                                                                      
SQLServer:Deprecated Features           	Usage                                                       	systypes                                                                        
SQLServer:Deprecated Features           	Usage                                                       	sysusers                                                                        
SQLServer:Deprecated Features           	Usage                                                       	Table hint without WITH                                                         
SQLServer:Deprecated Features           	Usage                                                       	Text in row table option                                                        
SQLServer:Deprecated Features           	Usage                                                       	TEXTPTR                                                                         
SQLServer:Deprecated Features           	Usage                                                       	TEXTVALID                                                                       
SQLServer:Deprecated Features           	Usage                                                       	TIMESTAMP                                                                       
SQLServer:Deprecated Features           	Usage                                                       	UPDATETEXT or WRITETEXT                                                         
SQLServer:Deprecated Features           	Usage                                                       	USER_ID                                                                         
SQLServer:Deprecated Features           	Usage                                                       	Using OLEDB for linked servers                                                  
SQLServer:Deprecated Features           	Usage                                                       	Vardecimal storage format                                                       
SQLServer:Deprecated Features           	Usage                                                       	XMLDATA                                                                         
SQLServer:Deprecated Features           	Usage                                                       	XP_API                                                                          
SQLServer:Deprecated Features           	Usage                                                       	xp_grantlogin                                                                   
SQLServer:Deprecated Features           	Usage                                                       	xp_loginconfig                                                                  
SQLServer:Deprecated Features           	Usage                                                       	xp_revokelogin                                                                  

SQLServer:FileTable                     	Avg time delete FileTable item                              	                                                                                
SQLServer:FileTable                     	Avg time FileTable enumeration                              	                                                                                
SQLServer:FileTable                     	Avg time FileTable handle kill                              	                                                                                
SQLServer:FileTable                     	Avg time move FileTable item                                	                                                                                
SQLServer:FileTable                     	Avg time per file I/O request                               	                                                                                
SQLServer:FileTable                     	Avg time per file I/O response                              	                                                                                
SQLServer:FileTable                     	Avg time rename FileTable item                              	                                                                                
SQLServer:FileTable                     	Avg time to get FileTable item                              	                                                                                
SQLServer:FileTable                     	Avg time update FileTable item                              	                                                                                
SQLServer:FileTable                     	FileTable db operations/sec                                 	                                                                                
SQLServer:FileTable                     	FileTable enumeration reqs/sec                              	                                                                                
SQLServer:FileTable                     	FileTable file I/O requests/sec                             	                                                                                
SQLServer:FileTable                     	FileTable file I/O response/sec                             	                                                                                
SQLServer:FileTable                     	FileTable item delete reqs/sec                              	                                                                                
SQLServer:FileTable                     	FileTable item get requests/sec                             	                                                                                
SQLServer:FileTable                     	FileTable item move reqs/sec                                	                                                                                
SQLServer:FileTable                     	FileTable item rename reqs/sec                              	                                                                                
SQLServer:FileTable                     	FileTable item update reqs/sec                              	                                                                                
SQLServer:FileTable                     	FileTable kill handle ops/sec                               	                                                                                
SQLServer:FileTable                     	FileTable table operations/sec                              	                                                                                
SQLServer:FileTable                     	Time delete FileTable item BASE                             	                                                                                
SQLServer:FileTable                     	Time FileTable enumeration BASE                             	                                                                                
SQLServer:FileTable                     	Time FileTable handle kill BASE                             	                                                                                
SQLServer:FileTable                     	Time move FileTable item BASE                               	                                                                                
SQLServer:FileTable                     	Time per file I/O request BASE                              	                                                                                
SQLServer:FileTable                     	Time per file I/O response BASE                             	                                                                                
SQLServer:FileTable                     	Time rename FileTable item BASE                             	                                                                                
SQLServer:FileTable                     	Time to get FileTable item BASE                             	                                                                                
SQLServer:FileTable                     	Time update FileTable item BASE                             	                                                                                

SQLServer:HTTP Storage                  	Avg. Bytes/Read                                             	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. Bytes/Read BASE                                        	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. Bytes/Transfer                                         	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. Bytes/Transfer BASE                                    	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. Bytes/Write                                            	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. Bytes/Write BASE                                       	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. microsec/Read                                          	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. microsec/Read BASE                                     	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. microsec/Transfer                                      	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. microsec/Transfer BASE                                 	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. microsec/Write                                         	_Total                                                                          
SQLServer:HTTP Storage                  	Avg. microsec/Write BASE                                    	_Total                                                                          
SQLServer:HTTP Storage                  	HTTP Storage IO retry/sec                                   	_Total                                                                          
SQLServer:HTTP Storage                  	Outstanding HTTP Storage IO                                 	_Total                                                                          
SQLServer:HTTP Storage                  	Read Bytes/Sec                                              	_Total                                                                          
SQLServer:HTTP Storage                  	Reads/Sec                                                   	_Total                                                                          
SQLServer:HTTP Storage                  	Total Bytes/Sec                                             	_Total                                                                          
SQLServer:HTTP Storage                  	Transfers/Sec                                               	_Total                                                                          
SQLServer:HTTP Storage                  	Write Bytes/Sec                                             	_Total                                                                          
SQLServer:HTTP Storage                  	Writes/Sec                                                  	_Total                                                                          
SQLServer:User Settable                 	Query                                                       	User counter 1                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 10                                                                 
SQLServer:User Settable                 	Query                                                       	User counter 2                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 3                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 4                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 5                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 6                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 7                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 8                                                                  
SQLServer:User Settable                 	Query                                                       	User counter 9                                                                  

XTP Cursors                             	Cursor deletes/sec                                          	MSSQLSERVER                                                                     
XTP Cursors                             	Cursor inserts/sec                                          	MSSQLSERVER                                                                     
XTP Cursors                             	Cursor scans started/sec                                    	MSSQLSERVER                                                                     
XTP Cursors                             	Cursor unique violations/sec                                	MSSQLSERVER                                                                     
XTP Cursors                             	Cursor updates/sec                                          	MSSQLSERVER                                                                     
XTP Cursors                             	Cursor write conflicts/sec                                  	MSSQLSERVER                                                                     
XTP Cursors                             	Dusty corner scan retries/sec (user-issued)                 	MSSQLSERVER                                                                     
XTP Cursors                             	Expired rows removed/sec                                    	MSSQLSERVER                                                                     
XTP Cursors                             	Expired rows touched/sec                                    	MSSQLSERVER                                                                     
XTP Cursors                             	Rows returned/sec                                           	MSSQLSERVER                                                                     
XTP Cursors                             	Rows touched/sec                                            	MSSQLSERVER                                                                     
XTP Cursors                             	Tentatively-deleted rows touched/sec                        	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Dusty corner scan retries/sec (GC-issued)                   	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Main GC work items/sec                                      	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Parallel GC work item/sec                                   	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Rows processed/sec                                          	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Rows processed/sec (first in bucket and removed)            	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Rows processed/sec (first in bucket)                        	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Rows processed/sec (marked for unlink)                      	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Rows processed/sec (no sweep needed)                        	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Sweep expired rows removed/sec                              	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Sweep expired rows touched/sec                              	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Sweep expiring rows touched/sec                             	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Sweep rows touched/sec                                      	MSSQLSERVER                                                                     
XTP Garbage Collection                  	Sweep scans started/sec                                     	MSSQLSERVER                                                                     
XTP Phantom Processor                   	Dusty corner scan retries/sec (Phantom-issued)              	MSSQLSERVER                                                                     
XTP Phantom Processor                   	Phantom expired rows removed/sec                            	MSSQLSERVER                                                                     
XTP Phantom Processor                   	Phantom expired rows touched/sec                            	MSSQLSERVER                                                                     
XTP Phantom Processor                   	Phantom expiring rows touched/sec                           	MSSQLSERVER                                                                     
XTP Phantom Processor                   	Phantom rows touched/sec                                    	MSSQLSERVER                                                                     
XTP Phantom Processor                   	Phantom scans started/sec                                   	MSSQLSERVER                                                                     
XTP Storage                             	Checkpoints Closed                                          	MSSQLSERVER                                                                     
XTP Storage                             	Checkpoints Completed                                       	MSSQLSERVER                                                                     
XTP Storage                             	Core Merges Completed                                       	MSSQLSERVER                                                                     
XTP Storage                             	Merge Policy Evaluations                                    	MSSQLSERVER                                                                     
XTP Storage                             	Merge Requests Outstanding                                  	MSSQLSERVER                                                                     
XTP Storage                             	Merges Abandoned                                            	MSSQLSERVER                                                                     
XTP Storage                             	Merges Installed                                            	MSSQLSERVER                                                                     
XTP Storage                             	Total Files Merged                                          	MSSQLSERVER                                                                     
XTP Transaction Log                     	Log bytes written/sec                                       	MSSQLSERVER                                                                     
XTP Transaction Log                     	Log records written/sec                                     	MSSQLSERVER                                                                     
XTP Transactions                        	Cascading aborts/sec                                        	MSSQLSERVER                                                                     
XTP Transactions                        	Commit dependencies taken/sec                               	MSSQLSERVER                                                                     
XTP Transactions                        	Read-only transactions prepared/sec                         	MSSQLSERVER                                                                     
XTP Transactions                        	Save point refreshes/sec                                    	MSSQLSERVER                                                                     
XTP Transactions                        	Save point rollbacks/sec                                    	MSSQLSERVER                                                                     
XTP Transactions                        	Save points created/sec                                     	MSSQLSERVER                                                                     
XTP Transactions                        	Transaction validation failures/sec                         	MSSQLSERVER                                                                     
XTP Transactions                        	Transactions aborted by user/sec                            	MSSQLSERVER                                                                     
XTP Transactions                        	Transactions aborted/sec                                    	MSSQLSERVER                                                                     
XTP Transactions                        	Transactions created/sec                                    	MSSQLSERVER     



*/