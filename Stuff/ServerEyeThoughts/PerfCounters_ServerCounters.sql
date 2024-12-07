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

NOTE: I'm going to include lots to start, and after I get some runtime in the field will selectively disable stuff that is redundant with the DMVs I'm already collecting.


Hi Frequency
-------------------------------------------------------------------------
SQLServer:SQL Statistics                	SQL Attention rate                                          	                                                                                
SQLServer:SQL Statistics                	Batch Requests/sec                                          	                                                                                
SQLServer:SQL Statistics                	SQL Compilations/sec                                        	                                                                                
SQLServer:SQL Statistics                	SQL Re-Compilations/sec                                     	                                                                                
SQLServer:Transactions                  	Transactions                                                	                                                                                
SQLServer:General Statistics            	Transactions                                                	                                                                                
SQLServer:Buffer Manager                	Background writer pages/sec                                 	                                                                                
SQLServer:Buffer Manager                	Checkpoint pages/sec                                        	                                                                                
SQLServer:Buffer Manager                	Lazy writes/sec                                             	                                                                                
SQLServer:Buffer Manager                	Page lookups/sec                                            	                                                                                
SQLServer:Buffer Manager                	Page reads/sec                                              	                                                                                
SQLServer:Buffer Manager                	Page writes/sec                                             	                                                                                
SQLServer:Buffer Manager                	Readahead pages/sec                                         	                                                                                
SQLServer:Buffer Manager                	Readahead time/sec                                          	                                                                                
SQLServer:Buffer Manager                	Free list stalls/sec                                        	                                                                                
SQLServer:General Statistics            	Connection Reset/sec                                        	                                                                                
SQLServer:SQL Errors                    	Errors/sec                                                  	_Total                                                                          
SQLServer:SQL Errors                    	Errors/sec                                                  	DB Offline Errors                                                               
SQLServer:SQL Errors                    	Errors/sec                                                  	Info Errors                                                                     
SQLServer:SQL Errors                    	Errors/sec                                                  	Kill Connection Errors                                                          
SQLServer:SQL Errors                    	Errors/sec                                                  	User Errors                                                                     
SQLServer:General Statistics            	Logins/sec                                                  	                                                                                
SQLServer:General Statistics            	Logouts/sec                                                 	                                                                                
SQLServer:Resource Pool Stats           	CPU control effect %                                        	default                                                                         
SQLServer:Resource Pool Stats           	CPU control effect %                                        	internal                                                                        
SQLServer:Resource Pool Stats           	CPU usage %                                                 	default                                                                         
SQLServer:Resource Pool Stats           	CPU usage %                                                 	internal                                                                        
SQLServer:Resource Pool Stats           	CPU usage % base                                            	default                                                                         
SQLServer:Resource Pool Stats           	CPU usage % base                                            	internal                                                                        
SQLServer:Resource Pool Stats           	CPU usage target %                                          	default                                                                         
SQLServer:Resource Pool Stats           	CPU usage target %                                          	internal                                                                        
SQLServer:Resource Pool Stats           	Disk Read Bytes/sec                                         	default                                                                         
SQLServer:Resource Pool Stats           	Disk Read Bytes/sec                                         	internal                                                                        
SQLServer:Resource Pool Stats           	Disk Read IO Throttled/sec                                  	default                                                                         
SQLServer:Resource Pool Stats           	Disk Read IO Throttled/sec                                  	internal                                                                        
SQLServer:Resource Pool Stats           	Disk Read IO/sec                                            	default                                                                         
SQLServer:Resource Pool Stats           	Disk Read IO/sec                                            	internal                                                                        
SQLServer:Resource Pool Stats           	Disk Write Bytes/sec                                        	default                                                                         
SQLServer:Resource Pool Stats           	Disk Write Bytes/sec                                        	internal                                                                        
SQLServer:Resource Pool Stats           	Disk Write IO Throttled/sec                                 	default                                                                         
SQLServer:Resource Pool Stats           	Disk Write IO Throttled/sec                                 	internal                                                                        
SQLServer:Resource Pool Stats           	Disk Write IO/sec                                           	default                                                                         
SQLServer:Resource Pool Stats           	Disk Write IO/sec                                           	internal                                                                        
SQLServer:Resource Pool Stats           	Avg Disk Read IO (ms)                                       	default                                                                         
SQLServer:Resource Pool Stats           	Avg Disk Read IO (ms)                                       	internal                                                                        
SQLServer:Resource Pool Stats           	Avg Disk Read IO (ms) Base                                  	default                                                                         
SQLServer:Resource Pool Stats           	Avg Disk Read IO (ms) Base                                  	internal                                                                        
SQLServer:Resource Pool Stats           	Avg Disk Write IO (ms)                                      	default                                                                         
SQLServer:Resource Pool Stats           	Avg Disk Write IO (ms)                                      	internal                                                                        
SQLServer:Resource Pool Stats           	Avg Disk Write IO (ms) Base                                 	default                                                                         
SQLServer:Resource Pool Stats           	Avg Disk Write IO (ms) Base                                 	internal                                                                        
SQLServer:Buffer Node                   	Local node page lookups/sec                                 	000                                                                             
SQLServer:Buffer Node                   	Remote node page lookups/sec                                	000                                                                             
SQLServer:Resource Pool Stats           	Memory grant timeouts/sec                                   	default                                                                         
SQLServer:Resource Pool Stats           	Memory grant timeouts/sec                                   	internal                                                                        
SQLServer:Resource Pool Stats           	Memory grants/sec                                           	default                                                                         
SQLServer:Resource Pool Stats           	Memory grants/sec                                           	internal                                                                        
SQLServer:Workload Group Stats          	Active parallel threads                                     	default                                                                         
SQLServer:Workload Group Stats          	Active parallel threads                                     	internal                                                                        
SQLServer:Workload Group Stats          	Active requests                                             	default                                                                         
SQLServer:Workload Group Stats          	Active requests                                             	internal                                                                        
SQLServer:Workload Group Stats          	Blocked tasks                                               	default                                                                         
SQLServer:Workload Group Stats          	Blocked tasks                                               	internal                                                                        
SQLServer:Workload Group Stats          	CPU usage %                                                 	default                                                                         
SQLServer:Workload Group Stats          	CPU usage %                                                 	internal                                                                        
SQLServer:Workload Group Stats          	CPU usage % base                                            	default                                                                         
SQLServer:Workload Group Stats          	CPU usage % base                                            	internal                                                                        
SQLServer:Workload Group Stats          	Requests completed/sec                                      	default                                                                         
SQLServer:Workload Group Stats          	Requests completed/sec                                      	internal                                                                        
SQLServer:Workload Group Stats          	Queued requests                                             	default                                                                         
SQLServer:Workload Group Stats          	Queued requests                                             	internal                                                                        
SQLServer:Latches                       	Average Latch Wait Time (ms)                                	                                                                                
SQLServer:Latches                       	Average Latch Wait Time Base                                	                                                                                
SQLServer:Latches                       	Latch Waits/sec                                             	                                                                                
SQLServer:Latches                       	Total Latch Wait Time (ms)                                  	                                                                                
SQLServer:Locks                         	Number of Deadlocks/sec                                     	_Total                                                                          
SQLServer:Locks                         	Lock Requests/sec                                           	_Total                                                                          
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	_Total                                                                          
SQLServer:Locks                         	Lock Timeouts/sec                                           	_Total                                                                          
SQLServer:Locks                         	Lock Waits/sec                                              	_Total                                                                          



Mezzanine Frequency
-------------------------------------------------------------------------
SQLServer:Buffer Manager                	Buffer cache hit ratio                                      	                                                                                
SQLServer:Buffer Manager                	Buffer cache hit ratio base                                 	                                                                                
SQLServer:Buffer Manager                	Page life expectancy                                        	                                                                                
SQLServer:Buffer Manager                	Target pages                                                	                                                                                
SQLServer:Buffer Node                   	Database pages                                              	000                                                                             
SQLServer:Buffer Node                   	Page life expectancy                                        	000                                                                             
SQLServer:General Statistics            	Logical Connections                                         	                                                                                
SQLServer:General Statistics            	User Connections                                            	                                                                                
SQLServer:General Statistics            	Processes blocked                                           	                                                                                
SQLServer:Resource Pool Stats           	Pending memory grants count                                 	default                                                                         
SQLServer:Resource Pool Stats           	Pending memory grants count                                 	internal                                                                        
SQLServer:Memory Manager                	Memory Grants Outstanding                                   	                                                                                
SQLServer:Memory Manager                	Memory Grants Pending                                       	                                                                                
SQLServer:General Statistics            	Active Temp Tables                                          	                                                                                
SQLServer:General Statistics            	Temp Tables Creation Rate                                   	                                                                                
SQLServer:General Statistics            	Temp Tables For Destruction                                 	                                                                                
SQLServer:Access Methods                	Workfiles Created/sec                                       	                                                                                
SQLServer:Access Methods                	Worktables Created/sec                                      	                                                                                
SQLServer:Access Methods                	Worktables From Cache Base                                  	                                                                                
SQLServer:Access Methods                	Worktables From Cache Ratio                                 	                                                                                
SQLServer:Buffer Manager                	Database pages                                              	                                                                                
SQLServer:Access Methods                	Forwarded Records/sec                                       	                                                                                
SQLServer:Access Methods                	Skipped Ghosted Records/sec                                 	                                                                                
SQLServer:Access Methods                	Mixed page allocations/sec                                  	                                                                                
SQLServer:Access Methods                	Extent Deallocations/sec                                    	                                                                                
SQLServer:Access Methods                	Extents Allocated/sec                                       	                                                                                
SQLServer:Access Methods                	Full Scans/sec                                              	                                                                                
SQLServer:Access Methods                	Index Searches/sec                                          	                                                                                
SQLServer:Access Methods                	Page Deallocations/sec                                      	                                                                                
SQLServer:Access Methods                	Page compression attempts/sec                               	                                                                                
SQLServer:Access Methods                	Pages compressed/sec                                        	                                                                                
SQLServer:Access Methods                	Pages Allocated/sec                                         	                                                                                
SQLServer:Access Methods                	Probe Scans/sec                                             	                                                                                
SQLServer:Access Methods                	Range Scans/sec                                             	                                                                                
SQLServer:Transactions                  	Update conflict ratio                                       	                                                                                
SQLServer:Transactions                  	Update conflict ratio base                                  	                                                                                
SQLServer:Transactions                  	Version Cleanup rate (KB/s)                                 	                                                                                
SQLServer:Transactions                  	Version Generation rate (KB/s)    
SQLServer:Memory Broker Clerks          	Periodic evictions (pages)                                  	Buffer Pool                                                                     
SQLServer:Memory Broker Clerks          	Periodic evictions (pages)                                  	Column store object pool                                                        
SQLServer:Memory Broker Clerks          	Pressure evictions (pages/sec)                              	Buffer Pool                                                                     
SQLServer:Memory Broker Clerks          	Pressure evictions (pages/sec)                              	Column store object pool                                                        
SQLServer:SQL Statistics                	Auto-Param Attempts/sec                                     	                                                                                
SQLServer:SQL Statistics                	Failed Auto-Params/sec                                      	                                                                                
SQLServer:SQL Statistics                	Forced Parameterizations/sec                                	                                                                                
SQLServer:SQL Statistics                	Guided plan executions/sec                                  	                                                                                
SQLServer:SQL Statistics                	Misguided plan executions/sec                               	                                                                                
SQLServer:SQL Statistics                	Safe Auto-Params/sec                                        	                                                                                
SQLServer:SQL Statistics                	Unsafe Auto-Params/sec                                      	                                                                                
SQLServer:Workload Group Stats          	Query optimizations/sec                                     	default                                                                         
SQLServer:Workload Group Stats          	Query optimizations/sec                                     	internal                                                                        
SQLServer:Workload Group Stats          	Suboptimal plans/sec                                        	default                                                                         
SQLServer:Workload Group Stats          	Suboptimal plans/sec                                        	internal                                                                        
SQLServer:Workload Group Stats          	Reduced memory grants/sec                                   	default                                                                         
SQLServer:Workload Group Stats          	Reduced memory grants/sec                                   	internal                                                                        
SQLServer:Latches                       	Number of SuperLatches                                      	                                                                                
SQLServer:Latches                       	SuperLatch Demotions/sec                                    	                                                                                
SQLServer:Latches                       	SuperLatch Promotions/sec                                   	                                                                                
SQLServer:Exec Statistics               	DTC calls                                                   	Average execution time (ms)                                                     
SQLServer:Exec Statistics               	DTC calls                                                   	Cumulative execution time (ms) per second                                       
SQLServer:Exec Statistics               	DTC calls                                                   	Execs in progress                                                               
SQLServer:Exec Statistics               	DTC calls                                                   	Execs started per second                                                        
SQLServer:Exec Statistics               	OLEDB calls                                                 	Average execution time (ms)                                                     
SQLServer:Exec Statistics               	OLEDB calls                                                 	Cumulative execution time (ms) per second                                       
SQLServer:Exec Statistics               	OLEDB calls                                                 	Execs in progress                                                               
SQLServer:Exec Statistics               	OLEDB calls                                                 	Execs started per second                                                        



Medium Frequency
-------------------------------------------------------------------------
SQLServer:Batch Resp Statistics				all of them. Every 5 minutes? See below for the full list
SQLServer:Transactions                  	Free Space in tempdb (KB)                                   	                                                                                
SQLServer:Transactions                  	Longest Transaction Running Time                            	                                                                                
SQLServer:Transactions                  	Version Store Size (KB)                                     	                                                                                
SQLServer:Transactions                  	NonSnapshot Version Transactions                            	                                                                                
SQLServer:Transactions                  	Snapshot Transactions                                       	                                                                                
SQLServer:Transactions                  	Update Snapshot Transactions                                	                                                                                
SQLServer:Transactions                  	Version Store unit count                                    	                                                                                
SQLServer:Transactions                  	Version Store unit creation                                 	                                                                                
SQLServer:Transactions                  	Version Store unit truncation                               	                                                                                
SQLServer:Resource Pool Stats           	Active memory grant amount (KB)                             	default                                                                         
SQLServer:Resource Pool Stats           	Active memory grant amount (KB)                             	internal                                                                        
SQLServer:Resource Pool Stats           	Active memory grants count                                  	default                                                                         
SQLServer:Resource Pool Stats           	Active memory grants count                                  	internal                                                                        
SQLServer:Resource Pool Stats           	Cache memory target (KB)                                    	default                                                                         
SQLServer:Resource Pool Stats           	Cache memory target (KB)                                    	internal                                                                        
SQLServer:Resource Pool Stats           	Compile memory target (KB)                                  	default                                                                         
SQLServer:Resource Pool Stats           	Compile memory target (KB)                                  	internal                                                                        
SQLServer:Resource Pool Stats           	Max memory (KB)                                             	default                                                                         
SQLServer:Resource Pool Stats           	Max memory (KB)                                             	internal                                                                        
SQLServer:Exec Statistics               	Distributed Query                                           	Average execution time (ms)                                                     
SQLServer:Exec Statistics               	Distributed Query                                           	Cumulative execution time (ms) per second                                       
SQLServer:Exec Statistics               	Distributed Query                                           	Execs in progress                                                               
SQLServer:Exec Statistics               	Distributed Query                                           	Execs started per second                                                        
SQLServer:Memory Broker Clerks          	Internal benefit                                            	Buffer Pool                                                                     
SQLServer:Memory Broker Clerks          	Internal benefit                                            	Column store object pool                                                        
SQLServer:Memory Broker Clerks          	Memory broker clerk size                                    	Buffer Pool                                                                     
SQLServer:Memory Broker Clerks          	Memory broker clerk size                                    	Column store object pool                                                        
SQLServer:Memory Broker Clerks          	Simulation benefit                                          	Buffer Pool                                                                     
SQLServer:Memory Broker Clerks          	Simulation benefit                                          	Column store object pool                                                        
SQLServer:Memory Broker Clerks          	Simulation size                                             	Buffer Pool                                                                     
SQLServer:Memory Broker Clerks          	Simulation size                                             	Column store object pool     
SQLServer:Memory Manager                	Connection Memory (KB)                                      	                                                                                
SQLServer:Memory Manager                	Database Cache Memory (KB)                                  	                                                                                
SQLServer:Memory Manager                	External benefit of memory                                  	                                                                                
SQLServer:Memory Manager                	Free Memory (KB)                                            	                                                                                
SQLServer:Memory Manager                	Granted Workspace Memory (KB)                               	                                                                                
SQLServer:Memory Manager                	Lock Blocks                                                 	                                                                                
SQLServer:Memory Manager                	Lock Blocks Allocated                                       	                                                                                
SQLServer:Memory Manager                	Lock Memory (KB)                                            	                                                                                
SQLServer:Memory Manager                	Lock Owner Blocks                                           	                                                                                
SQLServer:Memory Manager                	Lock Owner Blocks Allocated                                 	                                                                                
SQLServer:Memory Manager                	Log Pool Memory (KB)                                        	                                                                                
SQLServer:Memory Manager                	Maximum Workspace Memory (KB)                               	                                                                                
SQLServer:Resource Pool Stats           	Query exec memory target (KB)                               	default                                                                         
SQLServer:Resource Pool Stats           	Query exec memory target (KB)                               	internal                                                                        
SQLServer:Resource Pool Stats           	Target memory (KB)                                          	default                                                                         
SQLServer:Resource Pool Stats           	Target memory (KB)                                          	internal                                                                        
SQLServer:Resource Pool Stats           	Used memory (KB)                                            	default                                                                         
SQLServer:Resource Pool Stats           	Used memory (KB)                                            	internal                                                                        
SQLServer:Memory Manager                	Optimizer Memory (KB)                                       	                                                                                
SQLServer:Memory Manager                	Reserved Server Memory (KB)                                 	                                                                                
SQLServer:Memory Manager                	SQL Cache Memory (KB)                                       	                                                                                
SQLServer:Memory Manager                	Stolen Server Memory (KB)                                   	                                                                                
SQLServer:Memory Manager                	Target Server Memory (KB)                                   	                                                                                
SQLServer:Memory Manager                	Total Server Memory (KB)                                    	                                                                                
SQLServer:Memory Node                   	Database Node Memory (KB)                                   	000                                                                             
SQLServer:Memory Node                   	Foreign Node Memory (KB)                                    	000                                                                             
SQLServer:Memory Node                   	Free Node Memory (KB)                                       	000                                                                             
SQLServer:Memory Node                   	Stolen Node Memory (KB)                                     	000                                                                             
SQLServer:Memory Node                   	Target Node Memory (KB)                                     	000                                                                             
SQLServer:Memory Node                   	Total Node Memory (KB)                                      	000                                                                             
SQLServer:Plan Cache                    	Cache Object Counts                                         	_Total                                                                          
SQLServer:Plan Cache                    	Cache Object Counts                                         	Bound Trees                                                                     
SQLServer:Plan Cache                    	Cache Object Counts                                         	Extended Stored Procedures                                                      
SQLServer:Plan Cache                    	Cache Object Counts                                         	Object Plans                                                                    
SQLServer:Plan Cache                    	Cache Object Counts                                         	SQL Plans                                                                       
SQLServer:Plan Cache                    	Cache Object Counts                                         	Temporary Tables & Table Variables                                              
SQLServer:Plan Cache                    	Cache Pages                                                 	_Total                                                                          
SQLServer:Plan Cache                    	Cache Pages                                                 	Bound Trees                                                                     
SQLServer:Plan Cache                    	Cache Pages                                                 	Extended Stored Procedures                                                      
SQLServer:Plan Cache                    	Cache Pages                                                 	Object Plans                                                                    
SQLServer:Plan Cache                    	Cache Pages                                                 	SQL Plans                                                                       
SQLServer:Plan Cache                    	Cache Pages                                                 	Temporary Tables & Table Variables      
SQLServer:Workload Group Stats          	Max request cpu time (ms)                                   	default                                                                         
SQLServer:Workload Group Stats          	Max request cpu time (ms)                                   	internal                                                                        
SQLServer:Workload Group Stats          	Max request memory grant (KB)                               	default                                                                         
SQLServer:Workload Group Stats          	Max request memory grant (KB)                               	internal                                                                        



Low Frequency
-------------------------------------------------------------------------



Batch Frequency
-------------------------------------------------------------------------







--Very detailed or obscure info. Better for focused traces on specific, hard problems
-----------------------------------------------------------------------------------------
object_name									counter_name												instance_name
SQLServer:Access Methods                	AU cleanup batches/sec                                      	                                                                                
SQLServer:Access Methods                	AU cleanups/sec                                             	                                                                                
SQLServer:Access Methods                	By-reference Lob Create Count                               	                                                                                
SQLServer:Access Methods                	By-reference Lob Use Count                                  	                                                                                
SQLServer:Access Methods                	Count Lob Readahead                                         	                                                                                
SQLServer:Access Methods                	Count Pull In Row                                           	                                                                                
SQLServer:Access Methods                	Count Push Off Row                                          	                                                                                
SQLServer:Access Methods                	Deferred dropped AUs                                        	                                                                                
SQLServer:Access Methods                	Deferred Dropped rowsets                                    	                                                                                
SQLServer:Access Methods                	Dropped rowset cleanups/sec                                 	                                                                                
SQLServer:Access Methods                	Dropped rowsets skipped/sec                                 	                                                                                
SQLServer:Access Methods                	Failed AU cleanup batches/sec                               	                                                                                
SQLServer:Access Methods                	Failed leaf page cookie                                     	                                                                                
SQLServer:Access Methods                	Failed tree page cookie                                     	                                                                                
SQLServer:Access Methods                	FreeSpace Page Fetches/sec                                  	                                                                                
SQLServer:Access Methods                	FreeSpace Scans/sec                                         	                                                                                
SQLServer:Access Methods                	InSysXact waits/sec                                         	                                                                                
SQLServer:Access Methods                	LobHandle Create Count                                      	                                                                                
SQLServer:Access Methods                	LobHandle Destroy Count                                     	                                                                                
SQLServer:Access Methods                	LobSS Provider Create Count                                 	                                                                                
SQLServer:Access Methods                	LobSS Provider Destroy Count                                	                                                                                
SQLServer:Access Methods                	LobSS Provider Truncation Count                             	                                                                                
SQLServer:Access Methods                	Page Splits/sec                                             	                                                                                
SQLServer:Access Methods                	Scan Point Revalidations/sec                                	                                                                                
SQLServer:Access Methods                	Table Lock Escalations/sec                                  	                                                                                
SQLServer:Access Methods                	Used leaf page cookie                                       	                                                                                
SQLServer:Access Methods                	Used tree page cookie                                       	                                                                                

SQLServer:Buffer Manager                	Extension allocated pages                                   	                                                                                
SQLServer:Buffer Manager                	Extension free pages                                        	                                                                                
SQLServer:Buffer Manager                	Extension in use as percentage                              	                                                                                
SQLServer:Buffer Manager                	Extension outstanding IO counter                            	                                                                                
SQLServer:Buffer Manager                	Extension page evictions/sec                                	                                                                                
SQLServer:Buffer Manager                	Extension page reads/sec                                    	                                                                                
SQLServer:Buffer Manager                	Extension page unreferenced time                            	                                                                                
SQLServer:Buffer Manager                	Extension page writes/sec                                   	                                                                                
SQLServer:Buffer Manager                	Integral Controller Slope                                   	                                                                                
SQLServer:Catalog Metadata              	Cache Entries Count                                         	_Total                                                                          
SQLServer:Catalog Metadata              	Cache Entries Count                                         	<dbname>
SQLServer:Catalog Metadata              	Cache Entries Count                                         	tempdb                                                                          
SQLServer:Catalog Metadata              	Cache Entries Pinned Count                                  	_Total                                                                          
SQLServer:Catalog Metadata              	Cache Entries Pinned Count                                  	<dbname>
SQLServer:Catalog Metadata              	Cache Entries Pinned Count                                  	tempdb                                                                          
SQLServer:Catalog Metadata              	Cache Hit Ratio                                             	_Total                                                                          
SQLServer:Catalog Metadata              	Cache Hit Ratio                                             	<dbname>
SQLServer:Catalog Metadata              	Cache Hit Ratio                                             	tempdb                                                                          
SQLServer:Catalog Metadata              	Cache Hit Ratio Base                                        	_Total                                                                          
SQLServer:Catalog Metadata              	Cache Hit Ratio Base                                        	<dbname>                                                                    
SQLServer:Catalog Metadata              	Cache Hit Ratio Base                                        	tempdb                                                                          
                                                               
SQLServer:Cursor Manager by Type        	Active cursors                                              	_Total                                                                          
SQLServer:Cursor Manager by Type        	Active cursors                                              	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Active cursors                                              	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Active cursors                                              	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cache Hit Ratio                                             	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cache Hit Ratio                                             	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cache Hit Ratio                                             	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cache Hit Ratio                                             	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cache Hit Ratio Base                                        	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cache Hit Ratio Base                                        	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cache Hit Ratio Base                                        	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cache Hit Ratio Base                                        	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cached Cursor Counts                                        	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cached Cursor Counts                                        	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cached Cursor Counts                                        	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cached Cursor Counts                                        	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cursor Cache Use Counts/sec                                 	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cursor Cache Use Counts/sec                                 	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cursor Cache Use Counts/sec                                 	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cursor Cache Use Counts/sec                                 	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cursor memory usage                                         	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cursor memory usage                                         	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cursor memory usage                                         	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cursor memory usage                                         	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cursor Requests/sec                                         	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cursor Requests/sec                                         	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cursor Requests/sec                                         	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cursor Requests/sec                                         	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Cursor worktable usage                                      	_Total                                                                          
SQLServer:Cursor Manager by Type        	Cursor worktable usage                                      	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Cursor worktable usage                                      	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Cursor worktable usage                                      	TSQL Local Cursor                                                               
SQLServer:Cursor Manager by Type        	Number of active cursor plans                               	_Total                                                                          
SQLServer:Cursor Manager by Type        	Number of active cursor plans                               	API Cursor                                                                      
SQLServer:Cursor Manager by Type        	Number of active cursor plans                               	TSQL Global Cursor                                                              
SQLServer:Cursor Manager by Type        	Number of active cursor plans                               	TSQL Local Cursor                                                               
SQLServer:Cursor Manager Total          	Async population count                                      	                                                                                
SQLServer:Cursor Manager Total          	Cursor conversion rate                                      	                                                                                
SQLServer:Cursor Manager Total          	Cursor flushes                                              	                                                                                
                                    
SQLServer:Exec Statistics               	Extended Procedures                                         	Average execution time (ms)                                                     
SQLServer:Exec Statistics               	Extended Procedures                                         	Cumulative execution time (ms) per second                                       
SQLServer:Exec Statistics               	Extended Procedures                                         	Execs in progress                                                               
SQLServer:Exec Statistics               	Extended Procedures                                         	Execs started per second                                                        
SQLServer:General Statistics            	Event Notifications Delayed Drop                            	                                                                                
SQLServer:General Statistics            	HTTP Authenticated Requests                                 	                                                                                
SQLServer:General Statistics            	Mars Deadlocks                                              	                                                                                
SQLServer:General Statistics            	Non-atomic yield rate                                       	                                                                                
SQLServer:General Statistics            	SOAP Empty Requests                                         	                                                                                
SQLServer:General Statistics            	SOAP Method Invocations                                     	                                                                                
SQLServer:General Statistics            	SOAP Session Initiate Requests                              	                                                                                
SQLServer:General Statistics            	SOAP Session Terminate Requests                             	                                                                                
SQLServer:General Statistics            	SOAP SQL Requests                                           	                                                                                
SQLServer:General Statistics            	SOAP WSDL Requests                                          	                                                                                
SQLServer:General Statistics            	SQL Trace IO Provider Lock Waits                            	                                                                                
SQLServer:General Statistics            	Tempdb recovery unit id                                     	                                                                                
SQLServer:General Statistics            	Tempdb rowset id                                            	                                                                                
SQLServer:General Statistics            	Trace Event Notification Queue                              	                                                                                

                                                   
                                        





                   
				   


These are higher priority but I just put a single placeholder up above
-------------------------------------------------------------------------------------------------------------------------------------
The buckets are
0-1ms	1-2ms	2-5ms	5-10ms	10-20ms	20-50ms	50-100ms	100-200ms	200-500ms	500-1000ms	1000-2000ms	2000-5000ms	5000-10000ms	10000-20000ms	20000-50000ms	50000ms-100000ms	>=100000ms

SQLServer:Batch Resp Statistics         	Batches >=000000ms & <000001ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000000ms & <000001ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000000ms & <000001ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000000ms & <000001ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000001ms & <000002ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000001ms & <000002ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000001ms & <000002ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000001ms & <000002ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000002ms & <000005ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000002ms & <000005ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000002ms & <000005ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000002ms & <000005ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000005ms & <000010ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000005ms & <000010ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000005ms & <000010ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000005ms & <000010ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000010ms & <000020ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000010ms & <000020ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000010ms & <000020ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000010ms & <000020ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000020ms & <000050ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000020ms & <000050ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000020ms & <000050ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000020ms & <000050ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000050ms & <000100ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000050ms & <000100ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000050ms & <000100ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000050ms & <000100ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000100ms & <000200ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000100ms & <000200ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000100ms & <000200ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000100ms & <000200ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000200ms & <000500ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000200ms & <000500ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000200ms & <000500ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000200ms & <000500ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=000500ms & <001000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=000500ms & <001000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=000500ms & <001000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=000500ms & <001000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=001000ms & <002000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=001000ms & <002000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=001000ms & <002000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=001000ms & <002000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=002000ms & <005000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=002000ms & <005000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=002000ms & <005000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=002000ms & <005000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=005000ms & <010000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=005000ms & <010000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=005000ms & <010000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=005000ms & <010000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=010000ms & <020000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=010000ms & <020000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=010000ms & <020000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=010000ms & <020000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=020000ms & <050000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=020000ms & <050000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=020000ms & <050000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=020000ms & <050000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=050000ms & <100000ms                              	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=050000ms & <100000ms                              	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=050000ms & <100000ms                              	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=050000ms & <100000ms                              	Elapsed Time:Total(ms)                                                          
SQLServer:Batch Resp Statistics         	Batches >=100000ms                                          	CPU Time:Requests                                                               
SQLServer:Batch Resp Statistics         	Batches >=100000ms                                          	CPU Time:Total(ms)                                                              
SQLServer:Batch Resp Statistics         	Batches >=100000ms                                          	Elapsed Time:Requests                                                           
SQLServer:Batch Resp Statistics         	Batches >=100000ms                                          	Elapsed Time:Total(ms)                                                          



				   
--For the rest of these, the value is harder to see.   
--------------------------------------------------------------------------------
SQLServer:Locks                         	Average Wait Time (ms)                                      	_Total                                                                          
SQLServer:Locks                         	Average Wait Time (ms)                                      	AllocUnit                                                                       
SQLServer:Locks                         	Average Wait Time (ms)                                      	Application                                                                     
SQLServer:Locks                         	Average Wait Time (ms)                                      	Database                                                                        
SQLServer:Locks                         	Average Wait Time (ms)                                      	Extent                                                                          
SQLServer:Locks                         	Average Wait Time (ms)                                      	File                                                                            
SQLServer:Locks                         	Average Wait Time (ms)                                      	HoBT                                                                            
SQLServer:Locks                         	Average Wait Time (ms)                                      	Key                                                                             
SQLServer:Locks                         	Average Wait Time (ms)                                      	Metadata                                                                        
SQLServer:Locks                         	Average Wait Time (ms)                                      	Object                                                                          
SQLServer:Locks                         	Average Wait Time (ms)                                      	OIB                                                                             
SQLServer:Locks                         	Average Wait Time (ms)                                      	Page                                                                            
SQLServer:Locks                         	Average Wait Time (ms)                                      	RID                                                                             
SQLServer:Locks                         	Average Wait Time (ms)                                      	RowGroup                                                                        
SQLServer:Locks                         	Average Wait Time Base                                      	_Total                                                                          
SQLServer:Locks                         	Average Wait Time Base                                      	AllocUnit                                                                       
SQLServer:Locks                         	Average Wait Time Base                                      	Application                                                                     
SQLServer:Locks                         	Average Wait Time Base                                      	Database                                                                        
SQLServer:Locks                         	Average Wait Time Base                                      	Extent                                                                          
SQLServer:Locks                         	Average Wait Time Base                                      	File                                                                            
SQLServer:Locks                         	Average Wait Time Base                                      	HoBT                                                                            
SQLServer:Locks                         	Average Wait Time Base                                      	Key                                                                             
SQLServer:Locks                         	Average Wait Time Base                                      	Metadata                                                                        
SQLServer:Locks                         	Average Wait Time Base                                      	Object                                                                          
SQLServer:Locks                         	Average Wait Time Base                                      	OIB                                                                             
SQLServer:Locks                         	Average Wait Time Base                                      	Page                                                                            
SQLServer:Locks                         	Average Wait Time Base                                      	RID                                                                             
SQLServer:Locks                         	Average Wait Time Base                                      	RowGroup                                                                        
SQLServer:Locks                         	Lock Requests/sec                                           	AllocUnit                                                                       
SQLServer:Locks                         	Lock Requests/sec                                           	Application                                                                     
SQLServer:Locks                         	Lock Requests/sec                                           	Database                                                                        
SQLServer:Locks                         	Lock Requests/sec                                           	Extent                                                                          
SQLServer:Locks                         	Lock Requests/sec                                           	File                                                                            
SQLServer:Locks                         	Lock Requests/sec                                           	HoBT                                                                            
SQLServer:Locks                         	Lock Requests/sec                                           	Key                                                                             
SQLServer:Locks                         	Lock Requests/sec                                           	Metadata                                                                        
SQLServer:Locks                         	Lock Requests/sec                                           	Object                                                                          
SQLServer:Locks                         	Lock Requests/sec                                           	OIB                                                                             
SQLServer:Locks                         	Lock Requests/sec                                           	Page                                                                            
SQLServer:Locks                         	Lock Requests/sec                                           	RID                                                                             
SQLServer:Locks                         	Lock Requests/sec                                           	RowGroup                                                                        
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	AllocUnit                                                                       
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Application                                                                     
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Database                                                                        
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Extent                                                                          
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	File                                                                            
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	HoBT                                                                            
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Key                                                                             
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Metadata                                                                        
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Object                                                                          
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	OIB                                                                             
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	Page                                                                            
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	RID                                                                             
SQLServer:Locks                         	Lock Timeouts (timeout > 0)/sec                             	RowGroup                                                                        
SQLServer:Locks                         	Lock Timeouts/sec                                           	AllocUnit                                                                       
SQLServer:Locks                         	Lock Timeouts/sec                                           	Application                                                                     
SQLServer:Locks                         	Lock Timeouts/sec                                           	Database                                                                        
SQLServer:Locks                         	Lock Timeouts/sec                                           	Extent                                                                          
SQLServer:Locks                         	Lock Timeouts/sec                                           	File                                                                            
SQLServer:Locks                         	Lock Timeouts/sec                                           	HoBT                                                                            
SQLServer:Locks                         	Lock Timeouts/sec                                           	Key                                                                             
SQLServer:Locks                         	Lock Timeouts/sec                                           	Metadata                                                                        
SQLServer:Locks                         	Lock Timeouts/sec                                           	Object                                                                          
SQLServer:Locks                         	Lock Timeouts/sec                                           	OIB                                                                             
SQLServer:Locks                         	Lock Timeouts/sec                                           	Page                                                                            
SQLServer:Locks                         	Lock Timeouts/sec                                           	RID                                                                             
SQLServer:Locks                         	Lock Timeouts/sec                                           	RowGroup                                                                        
SQLServer:Locks                         	Lock Wait Time (ms)                                         	_Total                                                                          
SQLServer:Locks                         	Lock Wait Time (ms)                                         	AllocUnit                                                                       
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Application                                                                     
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Database                                                                        
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Extent                                                                          
SQLServer:Locks                         	Lock Wait Time (ms)                                         	File                                                                            
SQLServer:Locks                         	Lock Wait Time (ms)                                         	HoBT                                                                            
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Key                                                                             
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Metadata                                                                        
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Object                                                                          
SQLServer:Locks                         	Lock Wait Time (ms)                                         	OIB                                                                             
SQLServer:Locks                         	Lock Wait Time (ms)                                         	Page                                                                            
SQLServer:Locks                         	Lock Wait Time (ms)                                         	RID                                                                             
SQLServer:Locks                         	Lock Wait Time (ms)                                         	RowGroup                                                                        
SQLServer:Locks                         	Lock Waits/sec                                              	AllocUnit                                                                       
SQLServer:Locks                         	Lock Waits/sec                                              	Application                                                                     
SQLServer:Locks                         	Lock Waits/sec                                              	Database                                                                        
SQLServer:Locks                         	Lock Waits/sec                                              	Extent                                                                          
SQLServer:Locks                         	Lock Waits/sec                                              	File                                                                            
SQLServer:Locks                         	Lock Waits/sec                                              	HoBT                                                                            
SQLServer:Locks                         	Lock Waits/sec                                              	Key                                                                             
SQLServer:Locks                         	Lock Waits/sec                                              	Metadata                                                                        
SQLServer:Locks                         	Lock Waits/sec                                              	Object                                                                          
SQLServer:Locks                         	Lock Waits/sec                                              	OIB                                                                             
SQLServer:Locks                         	Lock Waits/sec                                              	Page                                                                            
SQLServer:Locks                         	Lock Waits/sec                                              	RID                                                                             
SQLServer:Locks                         	Lock Waits/sec                                              	RowGroup                                                                        
SQLServer:Locks                         	Number of Deadlocks/sec                                     	AllocUnit                                                                       
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Application                                                                     
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Database                                                                        
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Extent                                                                          
SQLServer:Locks                         	Number of Deadlocks/sec                                     	File                                                                            
SQLServer:Locks                         	Number of Deadlocks/sec                                     	HoBT                                                                            
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Key                                                                             
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Metadata                                                                        
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Object                                                                          
SQLServer:Locks                         	Number of Deadlocks/sec                                     	OIB                                                                             
SQLServer:Locks                         	Number of Deadlocks/sec                                     	Page                                                                            
SQLServer:Locks                         	Number of Deadlocks/sec                                     	RID                                                                             
SQLServer:Locks                         	Number of Deadlocks/sec                                     	RowGroup                                                                                                                  
SQLServer:Wait Statistics               	Lock waits                                                  	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Lock waits                                                  	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Lock waits                                                  	Waits in progress                                                               
SQLServer:Wait Statistics               	Lock waits                                                  	Waits started per second                                                        
SQLServer:Wait Statistics               	Log buffer waits                                            	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Log buffer waits                                            	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Log buffer waits                                            	Waits in progress                                                               
SQLServer:Wait Statistics               	Log buffer waits                                            	Waits started per second                                                        
SQLServer:Wait Statistics               	Log write waits                                             	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Log write waits                                             	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Log write waits                                             	Waits in progress                                                               
SQLServer:Wait Statistics               	Log write waits                                             	Waits started per second                                                        
SQLServer:Wait Statistics               	Memory grant queue waits                                    	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Memory grant queue waits                                    	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Memory grant queue waits                                    	Waits in progress                                                               
SQLServer:Wait Statistics               	Memory grant queue waits                                    	Waits started per second                                                        
SQLServer:Wait Statistics               	Network IO waits                                            	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Network IO waits                                            	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Network IO waits                                            	Waits in progress                                                               
SQLServer:Wait Statistics               	Network IO waits                                            	Waits started per second                                                        
SQLServer:Wait Statistics               	Non-Page latch waits                                        	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Non-Page latch waits                                        	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Non-Page latch waits                                        	Waits in progress                                                               
SQLServer:Wait Statistics               	Non-Page latch waits                                        	Waits started per second                                                        
SQLServer:Wait Statistics               	Page IO latch waits                                         	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Page IO latch waits                                         	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Page IO latch waits                                         	Waits in progress                                                               
SQLServer:Wait Statistics               	Page IO latch waits                                         	Waits started per second                                                        
SQLServer:Wait Statistics               	Page latch waits                                            	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Page latch waits                                            	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Page latch waits                                            	Waits in progress                                                               
SQLServer:Wait Statistics               	Page latch waits                                            	Waits started per second                                                        
SQLServer:Wait Statistics               	Thread-safe memory objects waits                            	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Thread-safe memory objects waits                            	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Thread-safe memory objects waits                            	Waits in progress                                                               
SQLServer:Wait Statistics               	Thread-safe memory objects waits                            	Waits started per second                                                        
SQLServer:Wait Statistics               	Transaction ownership waits                                 	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Transaction ownership waits                                 	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Transaction ownership waits                                 	Waits in progress                                                               
SQLServer:Wait Statistics               	Transaction ownership waits                                 	Waits started per second                                                        
SQLServer:Wait Statistics               	Wait for the worker                                         	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Wait for the worker                                         	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Wait for the worker                                         	Waits in progress                                                               
SQLServer:Wait Statistics               	Wait for the worker                                         	Waits started per second                                                        
SQLServer:Wait Statistics               	Workspace synchronization waits                             	Average wait time (ms)                                                          
SQLServer:Wait Statistics               	Workspace synchronization waits                             	Cumulative wait time (ms) per second                                            
SQLServer:Wait Statistics               	Workspace synchronization waits                             	Waits in progress                                                               
SQLServer:Wait Statistics               	Workspace synchronization waits                             	Waits started per second                                                        
SQLServer:Plan Cache                    	Cache Hit Ratio                                             	_Total                                                                          
SQLServer:Plan Cache                    	Cache Hit Ratio                                             	Bound Trees                                                                     
SQLServer:Plan Cache                    	Cache Hit Ratio                                             	Extended Stored Procedures                                                      
SQLServer:Plan Cache                    	Cache Hit Ratio                                             	Object Plans                                                                    
SQLServer:Plan Cache                    	Cache Hit Ratio                                             	SQL Plans                                                                       
SQLServer:Plan Cache                    	Cache Hit Ratio                                             	Temporary Tables & Table Variables                                              
SQLServer:Plan Cache                    	Cache Hit Ratio Base                                        	_Total                                                                          
SQLServer:Plan Cache                    	Cache Hit Ratio Base                                        	Bound Trees                                                                     
SQLServer:Plan Cache                    	Cache Hit Ratio Base                                        	Extended Stored Procedures                                                      
SQLServer:Plan Cache                    	Cache Hit Ratio Base                                        	Object Plans                                                                    
SQLServer:Plan Cache                    	Cache Hit Ratio Base                                        	SQL Plans                                                                       
SQLServer:Plan Cache                    	Cache Hit Ratio Base                                        	Temporary Tables & Table Variables                                              
SQLServer:Plan Cache                    	Cache Objects in use                                        	_Total                                                                          
SQLServer:Plan Cache                    	Cache Objects in use                                        	Bound Trees                                                                     
SQLServer:Plan Cache                    	Cache Objects in use                                        	Extended Stored Procedures                                                      
SQLServer:Plan Cache                    	Cache Objects in use                                        	Object Plans                                                                    
SQLServer:Plan Cache                    	Cache Objects in use                                        	SQL Plans                                                                       
SQLServer:Plan Cache                    	Cache Objects in use                                        	Temporary Tables & Table Variables                                              

*/