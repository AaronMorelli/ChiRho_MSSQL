use master 
go
select count_big(*)
from master.dbo.spt_values t0
	cross join master.dbo.spt_values t1
	cross join master.dbo.spt_values t2
	cross join master.dbo.spt_values t3
	cross join master.dbo.spt_values t4
option (maxdop 1)
