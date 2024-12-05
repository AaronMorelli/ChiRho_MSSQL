#####
#   Copyright 2024 Aaron Morelli
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#	------------------------------------------------------------------------
#
#	PROJECT NAME: ChiRho for SQL Server https://github.com/AaronMorelli/ChiRho_MSSQL
#
#	PROJECT DESCRIPTION: A T-SQL toolkit for troubleshooting performance and stability problems on SQL Server instances
#
#	FILE NAME: install_database_objects.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Install the ChiRho database (if requested), its schema and T-SQL objects, and SQL Agent jobs
#   on a SQL Server instance.
#####

param ( 
[Parameter(Mandatory=$true)][string]$Server, 
[Parameter(Mandatory=$true)][string]$Database,
[Parameter(Mandatory=$true)][string]$SessionDataHoursToKeep,
[Parameter(Mandatory=$true)][string]$ServerDataDaysToKeep,
[Parameter(Mandatory=$true)][string]$DBExists,
[Parameter(Mandatory=$true)][string]$curScriptLocation
) 

$ErrorActionPreference = "Stop"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Parameter Validation complete. Proceeding with installation on server " + $Server + ", Database " + $Database + ", SessionDataHoursToKeep " + $SessionDataHoursToKeep + ", ServerDataDaysToKeep " + $ServerDataDaysToKeep
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Loading SQL Powershell module or snapin"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

if (Get-Module -Name SQLPS -ListAvailable) {
		Import-Module SqlPs
		
	$curtime = Get-Date -format s
	$outmsg = $curtime + "------> SQL Powershell module loaded successfully"
	Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
}
else {
	Add-PSSnapin -Name SqlServerCmdletSnapin100, SqlServerProviderSnapin100
	
	$curtime = Get-Date -format s
	$outmsg = $curtime + "------> SQL Powershell snapins loaded successfully"
	Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$core_parent = $curScriptLocation + "CoreXR\"
$core_config = $core_parent + "CoreXRConfig.sql"
$core_schemas = $core_parent + "CreateSchemas.sql"
$core_tables = $core_parent + "01_Tables"
$core_triggerstypes = $core_parent + "02_TriggersAndTypes"
$core_functions = $core_parent + "03_Functions"
$core_views = $core_parent + "04_Views"
$core_procedures = $core_parent + "05_Procs"


$autowho_parent = $curScriptLocation + "AutoWho\"
$autowho_config = $autowho_parent + "AutoWhoConfig.sql"
$autowho_tables = $autowho_parent + "01_Tables"
$autowho_triggers = $autowho_parent + "02_Triggers"
$autowho_views = $autowho_parent + "03_Views"
$autowho_procedures = $autowho_parent + "04_Procs"

## this is not implemented yet
$servereye_parent = $curScriptLocation + "ServerEye\"
$servereye_config = $servereye_parent + "ServerEyeConfig.sql"
$servereye_tables = $servereye_parent + "01_Tables"
$servereye_triggers = $servereye_parent + "02_Triggers"
$servereye_views = $servereye_parent + "03_Views"
$servereye_procedures = $servereye_parent + "04_Procs"


$job_core = $curScriptLocation + "Jobs\ChiRhoMaster.sql"
$job_autowho = $curScriptLocation + "Jobs\AutoWhoTrace.sql"
$job_servereye = $curScriptLocation + "Jobs\ServerEyeTrace.sql"

$masterprocs_parent = $curScriptLocation + "master\"


# Installation scripts
$createpedb = $curScriptLocation + "InstallerScripts\CreateXRDatabase.sql"
$pedbexistcheck = $curScriptLocation + "InstallerScripts\DBExistenceCheck.sql"
$deletedbobj = $curScriptLocation + "InstallerScripts\DeleteDatabaseObjects.sql"
$deleteservobj = $curScriptLocation + "InstallerScripts\DeleteServerObjects.sql"

# Check for the existence of the DB. We pass in $DBExists, and it will RAISERROR if the actual state of the DB's existence
# doesn't match what $DBExists says
try {
	$MyVariableArray = "DBName=$Database", "DBExists=$DBExists"
	
	invoke-sqlcmd -inputfile $pedbexistcheck -serverinstance $Server -database master -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

    $curtime = Get-Date -format s
    $outmsg = $curtime + "------> Finished if-exists check for database " + $Database
    Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
}
catch [system.exception] {
	Write-Host "Error occurred in InstallerScripts\DBExistenceCheck.sql: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}


if ( $DBExists -eq "N" ) {
    #Create it!
    $curtime = Get-Date -format s
    $outmsg = $curtime + "------> Creating XR database: " + $Database
    Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

    try {
	   $MyVariableArray = "DBName=$Database"
	
	   invoke-sqlcmd -inputfile $createpedb -serverinstance $Server -database master -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	   #In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	   CD $curScriptLocation

        $curtime = Get-Date -format s
        $outmsg = $curtime + "------> Finished create for database " + $Database
        Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
    }
    catch [system.exception] {
    	Write-Host "Error occurred in InstallerScripts\CreateXRDatabase.sql: " -foregroundcolor red -backgroundcolor black
    	Write-Host "$_" -foregroundcolor red -backgroundcolor black
        $curtime = Get-Date -format s
    	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
        throw "Installation failed"
    	break
    }
}
else {
    # scrub it of any existing XR objects. (Other objects aren't touched, so that XR can safely exist in an already-existing utility database)
    $curtime = Get-Date -format s
    $outmsg = $curtime + "------> Scrubbing XR database: " + $Database + " of any previously-installed PE objects."
    Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

    try {
	   invoke-sqlcmd -inputfile $deletedbobj -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	   #In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	   CD $curScriptLocation

        $curtime = Get-Date -format s
        $outmsg = $curtime + "------> Finished scrubbing XR objects for database " + $Database
        Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
    }
    catch [system.exception] {
    	Write-Host "Error occurred in InstallerScripts\DeleteDatabaseObjects.sql: " -foregroundcolor red -backgroundcolor black
    	Write-Host "$_" -foregroundcolor red -backgroundcolor black
        $curtime = Get-Date -format s
    	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
        throw "Installation failed"
    	break
    }

}  # end of if $DBExists -eq "N" block

Write-Host "" -foregroundcolor cyan -backgroundcolor black


# clean up any server objects (SQL Agent jobs, master procs)
try {
    # we still pass DB name b/c even though these are all instance-level objects, the DB name is used to construct the name for the jobs
	$MyVariableArray = "DBName=$Database"
	
	invoke-sqlcmd -inputfile $deleteservobj -serverinstance $Server -database master -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

    $curtime = Get-Date -format s
    $outmsg = $curtime + "------> Finished server object cleanup (DB tag used: " + $Database + ")"
    Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
}
catch [system.exception] {
	Write-Host "Error occurred in DeleteServerObjects.sql: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating schemas"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# Schemas  
try {
	invoke-sqlcmd -inputfile $core_schemas -serverinstance $Server -database $Database -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating schemas" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred when creating schemas: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # Schemas

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating core tables"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# Core tables
try {
	(dir $core_tables) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation

		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating core tables, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of Core Tables block

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating core triggers and types"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# Core triggers and types
try {
	(dir $core_triggerstypes) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation

		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating core triggers and types, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of Core triggers and types block

Write-Host "" -foregroundcolor cyan -backgroundcolor black


### NOTE: skipping "03_Functions" until we have a function.

# Core views is down below after AW and SE since one of the views references AW tables. May rethink this later.



$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating core procedures"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# Core procedures
try {
	(dir $core_procedures) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating core procedures, in file " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of Core procedures

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Configuring core objects"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho config
try {
	invoke-sqlcmd -inputfile $core_config -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished core configuration" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred during core configuration: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # core config

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating AutoWho tables"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho tables
try {
	(dir $autowho_tables) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating AutoWho tables, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of AutoWho tables block

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating AutoWho triggers"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho triggers
try {
	(dir $autowho_triggers) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating AutoWho triggers, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of AutoWho functions

Write-Host "" -foregroundcolor cyan -backgroundcolor black

<#
$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating AutoWho views"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho Views
try {
	(dir $autowho_views) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating AutoWho views, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of AutoWho views

Write-Host "" -foregroundcolor cyan -backgroundcolor black
#>

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating AutoWho procedures"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho procedures
try {
	(dir $autowho_procedures) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating AutoWho procedures, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of AutoWho procedures

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Configuring AutoWho"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho config
try {
	$MyVariableArray = "HoursToKeep=$SessionDataHoursToKeep"
	
	invoke-sqlcmd -inputfile $autowho_config -serverinstance $Server -database $Database -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished AutoWho configuration" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred during AutoWho configuration, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # AutoWho config

Write-Host "" -foregroundcolor cyan -backgroundcolor black





# ###################################################
# ServerEye
$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating ServerEye tables"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# ServerEye tables
try {
	(dir $servereye_tables) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating ServerEye tables, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of ServerEye tables block

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating ServerEye triggers"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# ServerEye triggers
try {
	(dir $servereye_triggers) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating ServerEye triggers, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of ServerEye triggers

Write-Host "" -foregroundcolor cyan -backgroundcolor black

<#
$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating ServerEye views"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# ServerEye Views
try {
	(dir $servereye_views) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating ServerEye views, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of ServerEye views

Write-Host "" -foregroundcolor cyan -backgroundcolor black
#>

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating ServerEye procedures"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho procedures
try {
	(dir $servereye_procedures) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation
		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating ServerEye procedures, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of ServerEye procedures

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Configuring ServerEye"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# ServerEye config
try {
	$MyVariableArray = "DaysToKeep=$ServerDataDaysToKeep"
	
	invoke-sqlcmd -inputfile $servereye_config -serverinstance $Server -database $Database -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished ServerEye configuration" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred during ServerEye configuration, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # ServerEye config

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating core views"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# Core views
try {
	(dir $core_views) |  
		ForEach-Object {  
			$curScript = $_.FullName
			$curFileName = $_.Name

			invoke-sqlcmd -inputfile $curScript -serverinstance $Server -database $Database -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
			#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
			CD $curScriptLocation

		}
}
catch [system.exception] {
	Write-Host "Error occurred when creating core views, in file: " + $curScript -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}  # end of Core views block

Write-Host "" -foregroundcolor cyan -backgroundcolor black








# we take our __TEMPLATE versions of the master procs and create versions with $Database substituted for @@XRDATABASENAME@@
# Note: currently sp_XR_JobMatrix and sp_XR_FileUsage do not have any references to the XR database
$masterproc_JM = $masterprocs_parent + "sp_XR_JobMatrix.sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_JobMatrix"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

try {
	invoke-sqlcmd -inputfile $masterproc_JM -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
#	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_JobMatrix" -foregroundcolor cyan -backgroundcolor black

}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_JobMatrix: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$masterproc_MDF = $masterprocs_parent + "sp_XR_FileUsage.sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_FileUsage"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

try {
	invoke-sqlcmd -inputfile $masterproc_MDF -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
#	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_FileUsage" -foregroundcolor cyan -backgroundcolor black

}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_FileUsage: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$masterproc_LR = $masterprocs_parent + "sp_XR_LongRequests__TEMPLATE.sql"
$masterproc_LR_Replace = $masterprocs_parent + "sp_XR_LongRequests__" + $Database + ".sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_LongRequests"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

if (Test-Path $masterproc_LR_Replace) {
	Remove-Item $masterproc_LR_Replace
}

(Get-Content $masterproc_LR) | Foreach-Object { $_ -replace '@@XRDATABASENAME@@', $Database } | Set-Content $masterproc_LR_Replace

try {
	invoke-sqlcmd -inputfile $masterproc_LR_Replace -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_LongRequests" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_LongRequests: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$masterproc_FQ = $masterprocs_parent + "sp_XR_FrequentQueries__TEMPLATE.sql"
$masterproc_FQ_Replace = $masterprocs_parent + "sp_XR_FrequentQueries__" + $Database + ".sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_FrequentQueries"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

if (Test-Path $masterproc_FQ_Replace) {
	Remove-Item $masterproc_FQ_Replace
}

(Get-Content $masterproc_FQ) | Foreach-Object { $_ -replace '@@XRDATABASENAME@@', $Database } | Set-Content $masterproc_FQ_Replace

try {
	invoke-sqlcmd -inputfile $masterproc_FQ_Replace -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_FrequentQueries" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_FrequentQueries: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black


#$masterproc_QC = $masterprocs_parent + "sp_XR_QueryCamera__TEMPLATE.sql"
#$masterproc_QC_Replace = $masterprocs_parent + "sp_XR_QueryCamera__" + $Database + ".sql"

#$curtime = Get-Date -format s
#$outmsg = $curtime + "------> Creating sp_XR_QueryCamera"
#Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

#if (Test-Path $masterproc_QC_Replace) {
#	Remove-Item $masterproc_QC_Replace
#}

#(Get-Content $masterproc_QC) | Foreach-Object { $_ -replace '@@XRDATABASENAME@@', $Database } | Set-Content $masterproc_QC_Replace

#try {
#	invoke-sqlcmd -inputfile $masterproc_QC_Replace -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
#	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
#	CD $curScriptLocation

#	Write-Host "Finished creating sp_XR_QueryCamera" -foregroundcolor cyan -backgroundcolor black

#}
#catch [system.exception] {
#	Write-Host "Error occurred while creating sp_XR_QueryCamera: " -foregroundcolor red -backgroundcolor black
#	Write-Host "$_" -foregroundcolor red -backgroundcolor black
#    $curtime = Get-Date -format s
#	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
#    throw "Installation failed"
#	break
#}

#Write-Host "" -foregroundcolor cyan -backgroundcolor black
<#
$masterproc_QP = $masterprocs_parent + "sp_XR_QueryProgress__TEMPLATE.sql"
$masterproc_QP_Replace = $masterprocs_parent + "sp_XR_QueryProgress__" + $Database + ".sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_QueryProgress"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

if (Test-Path $masterproc_QP_Replace) {
	Remove-Item $masterproc_QP_Replace
}

(Get-Content $masterproc_QP) | Foreach-Object { $_ -replace '@@XRDATABASENAME@@', $Database } | Set-Content $masterproc_QP_Replace

try {
	invoke-sqlcmd -inputfile $masterproc_QP_Replace -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_QueryProgress" -foregroundcolor cyan -backgroundcolor black

}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_QueryProgress: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black
#>

$masterproc_SS = $masterprocs_parent + "sp_XR_SessionSummary__TEMPLATE.sql"
$masterproc_SS_Replace = $masterprocs_parent + "sp_XR_SessionSummary__" + $Database + ".sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_SessionSummary"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

if (Test-Path $masterproc_SS_Replace) {
	Remove-Item $masterproc_SS_Replace
}

(Get-Content $masterproc_SS) | Foreach-Object { $_ -replace '@@XRDATABASENAME@@', $Database } | Set-Content $masterproc_SS_Replace

try {
	invoke-sqlcmd -inputfile $masterproc_SS_Replace -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_SessionSummary" -foregroundcolor cyan -backgroundcolor black

}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_SessionSummary: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black


$masterproc_SV = $masterprocs_parent + "sp_XR_SessionViewer__TEMPLATE.sql"
$masterproc_SV_Replace = $masterprocs_parent + "sp_XR_SessionViewer__" + $Database + ".sql"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating sp_XR_SessionViewer"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

if (Test-Path $masterproc_SV_Replace) {
	Remove-Item $masterproc_SV_Replace
}

(Get-Content $masterproc_SV) | Foreach-Object { $_ -replace '@@XRDATABASENAME@@', $Database } | Set-Content $masterproc_SV_Replace

try {
	invoke-sqlcmd -inputfile $masterproc_SV_Replace -serverinstance $Server -database master -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating sp_XR_SessionViewer" -foregroundcolor cyan -backgroundcolor black

}
catch [system.exception] {
	Write-Host "Error occurred while creating sp_XR_SessionViewer: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black



$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating ChiRho master job"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# ChiRho Master job
try {
	$MyVariableArray = "DBName=$Database"
	
	invoke-sqlcmd -inputfile $job_core -serverinstance $Server -database msdb -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating ChiRho Master job" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred when creating ChiRho Master job: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # Trace Master job

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating AutoWho trace job"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho job
try {
	$MyVariableArray = "DBName=$Database"
	
	invoke-sqlcmd -inputfile $job_autowho -serverinstance $Server -database msdb -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating AutoWho trace job" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred when creating AutoWho trace job: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # AutoWho job

Write-Host "" -foregroundcolor cyan -backgroundcolor black

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Creating ServerEye trace job"
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

# AutoWho job
try {
	$MyVariableArray = "DBName=$Database"
	
	invoke-sqlcmd -inputfile $job_servereye -serverinstance $Server -database msdb -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	#In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	CD $curScriptLocation

	Write-Host "Finished creating ServerEye trace job" -foregroundcolor cyan -backgroundcolor black
}
catch [system.exception] {
	Write-Host "Error occurred when creating ServerEye trace job: " -foregroundcolor red -backgroundcolor black
	Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
	Write-Host "Aborting installation, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Installation failed"
	break
} # ServerEye job

Write-Host "" -foregroundcolor cyan -backgroundcolor black