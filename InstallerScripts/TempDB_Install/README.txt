This folder contains the .sql scripts that will be generated when the Powershell installation scripts are run with certain parameters,
that indicate that the install should not be "normal" but rather should generate scripts that use global temp tables instead of
traditional database objects. These scripts serve use cases where a normal database install is not allowed, or not desired for some reason,
and instead a short-lived "install" into TempDB using global temp tables and global temp procs is sufficient instead.

The scripts that are generated in this folder should be run in numeric order, and care must be taken to keep the sessions open
for the windows that create the temp objects.

