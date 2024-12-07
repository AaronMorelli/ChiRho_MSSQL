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

--All of the below counters are in object_name = 'SQLServer:Databases'


Hi Freq
--------------------------------------------------
Backup/Restore Throughput/sec			for _Total and all DBnames
DBCC Logical Scan Bytes/sec				for _Total and all DBNames
Percent Log Used						for all DBnames, but omit _Total
Active Transactions						for _Total and all DBNames
Transactions/sec						ditto
Write Transactions/sec					ditto
Bulk Copy Rows/sec						for _Total and all DBNames
Bulk Copy Throughput/sec				for _Total and all DBNames
Log Bytes Flushed/sec					for _Total and all DBNames
Log Flush Wait Time						ditto
Log Flush Waits/sec						ditto
Log Flush Write Time (ms)				ditto
Log Flushes/sec							ditto
Tracked transactions/sec                                    	_Total             don't know what these are                                                             
Tracked transactions/sec                                    	<dbname>
Tracked transactions/sec                                    	tempdb                                                                          



Mezzanine Freq
--------------------------------------------------


Medium Freq
-------------------------------------------------
Data File(s) Size (KB)					for all DBNames		we can compare this to what we get through sys.database_files or master_files
Log File(s) Size (KB)					ditto
Log File(s) Used Size (KB)				compare to % used. May not add any value.
Shrink Data Movement Bytes/sec			for _Total and all DBNames
Commit table entries                                        	_Total			this is for the Change Tracking feature                                                                     
Commit table entries                                        	<dbname>
Commit table entries                                        	tempdb                                                                          
Group Commit Time/sec                                       	_Total			is this for Availability Groups? Delayed Durability?                         
Group Commit Time/sec                                       	<dbname>
Group Commit Time/sec                                       	tempdb                                                                          
Log Cache Hit Ratio                                         	_Total                                                                          
Log Cache Hit Ratio                                         	<dbname>
Log Cache Hit Ratio                                         	tempdb                                                                          
Log Cache Hit Ratio Base                                    	_Total                                                                          
Log Cache Hit Ratio Base                                    	<dbname>
Log Cache Hit Ratio Base                                    	tempdb                                                                          
Log Cache Reads/sec                                         	_Total                                                                          
Log Cache Reads/sec                                         	<dbname>
Log Cache Reads/sec                                         	tempdb                                                                          
Log Growths                                                 	_Total                                                                          
Log Growths                                                 	<dbname>
Log Growths                                                 	tempdb                                                                          
Log Shrinks                                                 	_Total                                                                          
Log Shrinks                                                 	<dbname>
Log Shrinks                                                 	tempdb                                                                          
Log Truncations                                             	_Total                                                                          
Log Truncations                                             	<dbname>
Log Truncations                                             	tempdb                                                                          


*/