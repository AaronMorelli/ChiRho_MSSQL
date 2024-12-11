# Strategy

Ok, here's what I'm going to do re: which SQL Server versions to support:
    v1.0 is going to be focused on supportability for "old" stuff, like the columns that were in the DMVs when I originally wrote all this.
    Then, once I think I have a good "product", I'll call it v1.0, create a release .zip for it in GitHub,
    then create a branch to track the release in case I need to patch it.
        So to be clear, this DOES mean implementing ServerEye in v1.0

    Then, in the "main" branch, I'll go ahead and make the changes to move up to the earliest supported version, 
    which is likely to be SQL Server 2016 (depending on how long it takes me to do all this! :-) )

So the focus now is on just getting what I already had working effectively for both "normal" installs and "TempDB-only" installs.

By definition, v1.0 does NOT need to support Azure SQL DB. I suppose I may need to have a separate branch for it at some point?
But anyways, that is something that I don't need to think about for a while.

*So the order of operations:*
1. Get what I already had working, for both regular install and TempDB install
    - (I do not have an older version of SQL Server to test on, so this will be best effort)
    - CoreXR 1.0
    - AutoWho 1.0
    - XR master procs 1.0
        - including things like the jobs proc and the file usage proc
    - ServerEye 1.0
        - do not yet have "XR master procs" defined for this, so for now the focus will be on just collecting data.
2. Create v1.0 ZIP and branch
3. Modify code to take advantage of new features up to/including SQL 2016 (such as STRING_SPLIT, db_id in dm_exec_sessions, Query Store, etc)
    - I may actually try to support some more modern features, but have them hidden behind comments in the source files.
    - I could even program the installer to support a "pause", where the installation artifacts are generated, but then the person installing can go in and modify those artifacts so that they can select the SQL 2017/2019/2022/etc features that they want installed.
4. Create v2.0 ZIP
5. Create new branch for Azure SQL DB that will represent a point-of-departure for the 2 code-bases, since there will prob be a fair amount that needs to change.


**THOUGHT**: maybe I should just rely on sp_WhoIsActive for Azure SQL DB... sure seems to have a ton of limitations on the DMVs.






