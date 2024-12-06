#####
#   Copyright 2016 Aaron Morelli
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
#	PROJECT NAME: ChiRho https://github.com/AaronMorelli/ChiRho
#
#	PROJECT DESCRIPTION: A T-SQL toolkit for troubleshooting performance and stability problems on SQL Server instances
#
#	FILE NAME: uninstall_database_objects.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Uninstall the ChiRho database (if requested), its schema and T-SQL objects, and SQL Agent jobs
#   from a SQL Server instance.
#
#	OUTSTANDING ISSUES: Change the logic so that after all ChiRho objects have been removed,
#   a check is done for any other objects and if any exist refuse to delete the database
#   and raise an error.
#####

param ( 
[Parameter(Mandatory=$true)][string]$Server, 
[Parameter(Mandatory=$true)][string]$Database,
[Parameter(Mandatory=$true)][string]$ServerObjectsOnly,
[Parameter(Mandatory=$true)][string]$DropDatabase,
[Parameter(Mandatory=$true)][string]$curScriptLocation
) 

$ErrorActionPreference = "Stop"

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Parameter Validation complete. Proceeding with uninstall on server " + $Server + ", Database " + $Database + ", ServerObjectsOnly " + $ServerObjectsOnly + ", DropDatabase " + $DropDatabase
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

# Installation scripts
$xrdbexistcheck = $curScriptLocation + "InstallerScripts\DBExistenceCheck.sql"
$deletedbobj = $curScriptLocation + "InstallerScripts\DeleteDatabaseObjects.sql"
$deleteservobj = $curScriptLocation + "InstallerScripts\DeleteServerObjects.sql"
$dropxrdatabase = $curScriptLocation + "InstallerScripts\DropXRDatabase.sql"

if ($ServerObjectsOnly -eq "N") {
    # we are deleting objects from a DB. We need to check that it exists first.
    $DBExists = "Y"

    # Check for the existence of the DB. We pass in $DBExists, and it will RAISERROR if the actual state of the DB's existence
    # doesn't match what $DBExists says
    try {
	   $MyVariableArray = "DBName=$Database", "DBExists=$DBExists"
	
	   invoke-sqlcmd -inputfile $xrdbexistcheck -serverinstance $Server -database master -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
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
	   Write-Host "Aborting uninstall, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
       throw "Uninstall failed"
	   break
    }

    # if we get this far, the DB exists. Scrub it of any existing XR objects
    if ($DropDatabase -eq "Y") {
        try {
	       $MyVariableArray = "DBName=$Database"
           $curtime = Get-Date -format s
           $outmsg = $curtime + "------> Dropping XR database: " + $Database + "."
	
	       invoke-sqlcmd -inputfile $dropxrdatabase -serverinstance $Server -database master -Variable $MyVariableArray -QueryTimeout 65534 -AbortOnError -Verbose -outputsqlerrors $true
	       #In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
	       CD $curScriptLocation

            $curtime = Get-Date -format s
            $outmsg = $curtime + "------> Finished drop for database " + $Database
            Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan
        }
        catch [system.exception] {
	       Write-Host "Error occurred in InstallerScripts\DropXRDatabase.sql: " -foregroundcolor red -backgroundcolor black
	       Write-Host "$_" -foregroundcolor red -backgroundcolor black
            $curtime = Get-Date -format s
	       Write-Host "Aborting uninstall, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
           throw "Uninstall failed"
	       break
        }
    } #if DB exists and we're to drop it
    else {
        $curtime = Get-Date -format s
        $outmsg = $curtime + "------> Scrubbing XR database: " + $Database + " of any installed XR objects."
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
        	Write-Host "Aborting uninstall, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
            throw "Uninstall failed"
        	break
        }
    } #DB exists and we're not to drop it.
} # end of DB object cleanup logic



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
    Write-Host "Error occurred in InstallerScripts\DeleteServerObjects.sql: " -foregroundcolor red -backgroundcolor black
    Write-Host "$_" -foregroundcolor red -backgroundcolor black
    $curtime = Get-Date -format s
    Write-Host "Aborting uninstall, abort time: " + $curtime -foregroundcolor red -backgroundcolor black
    throw "Uninstall failed"
    break
}

Write-Host "" -foregroundcolor cyan -backgroundcolor black