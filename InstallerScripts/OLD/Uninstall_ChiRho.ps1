#####
#   Copyright 2016, 2024 Aaron Morelli
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
#	FILE NAME: Uninstall_ChiRho.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Uninstall the ChiRho toolkit
#
# To Execute
# ------------------------
# this only gets rid of server objects. (Even if a DB exists, it is not touched). A default DB tag of "ChiRho" is used to find the SQL Agent jobs
# ps prompt>.\Uninstall_ChiRho.ps1 -Server . 

# this only gets rid of server objects. The DB name has been specified as it is a non-default name, and is used to find the SQL Agent jobs to delete.
# ps prompt>.\Uninstall_ChiRho.ps1 -Server . -Database XR1 -ServerObjectsOnly Y

# this gets rid of everything for the specified DB, including the database. If the DB is a general-purpose utility database (i.e. holds other DBA-related objects)
# then specifying -DropDatabase N will only remove the ChiRho-related objects
# ps prompt>.\Uninstall_ChiRho.ps1 -Server . -Database ChiRho1 -ServerObjectsOnly N -DropDatabase Y
#####

param ( 
[Parameter(Mandatory=$true)][string]$Server, 
[Parameter(Mandatory=$false)][string]$Database,
[Parameter(Mandatory=$false)][string]$ServerObjectsOnly,
[Parameter(Mandatory=$false)][string]$DropDatabase
) 

$ErrorActionPreference = "Stop"

Write-Host "ChiRho version 2008R2.1" -backgroundcolor black -foregroundcolor cyan
Write-Host "Apache 2.0 License" -backgroundcolor black -foregroundcolor cyan
Write-Host "Copyright (c) 2016 Aaron Morelli" -backgroundcolor black -foregroundcolor cyan

## basic parameter checking 
if ($Server -eq $null) {
	Write-Host "Parameter -Server must be specified." -foregroundcolor red -backgroundcolor black
	Break
}

if ($Server -eq "") {
	Write-Host "Parameter -Server cannot be blank." -foregroundcolor red -backgroundcolor black
	Break
}

if ($Database -eq $null) {
    $Database = ""
}
else {
    $Database = $Database.TrimStart().TrimEnd()
}

if ( $DropDatabase -eq $null) {
    $DropDatabase = ""
}
else {
    $DropDatabase = $DropDatabase.TrimStart().TrimEnd()
}

#ServerObjectsOnly parm handling
$ServerObjectsOnly = $ServerObjectsOnly.TrimStart().TrimEnd().ToUpper()


if ( ( $ServerObjectsOnly -eq $null) -or ($ServerObjectsOnly -eq "") ) {
    if ($Database -eq "" ) {
        # a DB name wasn't specified, so we default ServerObjectsOnly to Y. This is sort of a safety measure... we want the user
        # to intentionally enter the DB name before blowing away all of the data that may have been collected. Recreating the procs
        # and jobs isn't as big of a loss, since it's just code.
        Write-Host "No DB name specified, so defaulting -ServerObjectsOnly parameter to Y. Only server objects will be deleted." -backgroundcolor black -foregroundcolor yellow
        Write-Host "SQL Agent jobs will be searched for with the prefix 'ChiRho'" -backgroundcolor black -foregroundcolor yellow
        $ServerObjectsOnly = "Y"
    }
    else {
        # we've been given a DB to target, so default to N
        $ServerObjectsOnly = "N"
    }
}
else {
    if ( ($ServerObjectsOnly -ne "N") -and ($ServerObjectsOnly -ne "Y") ) {
        Write-Host "Parameter -ServerObjectsOnly must be Y or N if specified" -foregroundcolor red -backgroundcolor black
	   Break
    }
}

if ($ServerObjectsOnly -eq "Y") {
    if ($Database -eq "") {
        # no DB specified, default to ChiRho (We need a DB for the SQL Agent prefix tag search)
        $Database = "ChiRho"
    }

    if ($DropDatabase -eq "Y") {
        Write-Host "Parameter -DropDatabase cannot be Y if -ServerObjectsOnly is Y" -foregroundcolor red -backgroundcolor black
	    Break    
    }
} 
else {
    # we're deleting DB objects, too. DB name and DropDatabase are required
    if ($Database -eq "") {
        Write-Host "Parameter -Database must be specified if -ServerObjectsOnly is N" -foregroundcolor red -backgroundcolor black
	    Break    
    }
    
    if ( ($DropDatabase -ne "N") -and ($DropDatabase -ne "Y") ) {
        Write-Host "Parameter -DropDatabase must be Y or N if -ServerObjectsOnly is N" -foregroundcolor red -backgroundcolor black
	    Break
    }
} #parm handling for DropDatabase & Database based on value of $ServerObjectsOnly

# avoid sql injection by limiting $Database to alphanumeric. (Yeah, this is cheap and dirty. Will revisit)
if ($Database -notmatch '^[a-z0-9]+$') { 
    Write-Host "Parameter -Database can only contain alphanumeric characters." -foregroundcolor red -backgroundcolor black
	Break
}

$CurScriptName = $MyInvocation.MyCommand.Name
$CurDur = $MyInvocation.MyCommand.Path
$CurDur = $CurDur.Replace($CurScriptName,"")
$curScriptLoc = $CurDur.TrimStart().TrimEnd()

if ( !($curScriptLoc.EndsWith("\")) ) {
	$curScriptLoc = $curScriptLoc + "\"
}

$installerlogsloc = $curScriptLoc + "InstallationLogs\"

$installerLogFile = $installerlogsloc + "ChiRho_uninstall" + "_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date)

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Beginning uninstall..." 
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Parameter Validation complete. Proceeding with uninstall on server " + $Server + ", Database " + $Database + ", ServerObjectsOnly " + $ServerObjectsOnly
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan


$curtime = Get-Date -format s
$outmsg = $curtime + "------> Uninstall operations will be logged to " + $installerLogFile
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

CD $curScriptLoc 

powershell.exe -noprofile -command .\InstallerScripts\uninstall_database_objects.ps1 -Server $Server -Database $Database -ServerObjectsOnly $ServerObjectsOnly -DropDatabase $DropDatabase -curScriptLocation $curScriptLoc > $installerLogFile
$scriptresult = $?

$curtime = Get-Date -format s

if ($scriptresult -eq $true) {
    Write-Host "Uninstall completed successfully" -backgroundcolor black -foregroundcolor green
}
else {
    Write-Host "Uninstall failed. Please consult $installerLogFile for more details." -backgroundcolor black -foregroundcolor red
    Write-Host "Uninstall aborted at: " + $curtime -foregroundcolor red -backgroundcolor black
}