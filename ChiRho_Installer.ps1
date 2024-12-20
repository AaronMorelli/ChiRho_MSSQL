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
#	FILE NAME: ChiRho_Installer.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Install the ChiRho toolkit
# To Execute
# ------------------------
# ps prompt>.\ChiRho_Installer.ps1 -Server . -Database ChiRho -SessionDataHoursToKeep 336 -ServerDataDaysToKeep 30 -DBExists N
# or accept the defaults ("ChiRho", "336", "30", "N" as shown above)
# ps prompt>.\ChiRho_Installer.ps1 -Server .
# or prepare for a TempDB-only install:
# ps prompt>.\ChiRho_Installer.ps1 -Server . -GenerateTempDBInstall Y

# the Database name can be any alphanumeric string. SessionDataHoursToKeep defines how much
# time the session-related DMV data is kept. ServerDataDaysToKeep defines how much time the 
# server-related DMV data is kept. Session DMV data is generally much larger than server-level
# data, hence the difference in granularity.
#####

param ( 
[Parameter(Mandatory=$true)][string]$Server, 
[Parameter(Mandatory=$false)][string]$GenerateTempDBInstall,
[Parameter(Mandatory=$false)][string]$Database,
[Parameter(Mandatory=$false)][string]$SessionDataHoursToKeep,
[Parameter(Mandatory=$false)][string]$ServerDataDaysToKeep,
[Parameter(Mandatory=$false)][string]$DBExists
) 

$ErrorActionPreference = "Stop"

Write-Host "ChiRho version 1.0" -backgroundcolor black -foregroundcolor cyan
Write-Host "Apache 2.0 license" -backgroundcolor black -foregroundcolor cyan
Write-Host "Copyright (c) 2024 Aaron Morelli" -backgroundcolor black -foregroundcolor cyan

## basic parameter checking 
if ($Server -eq $null) {
	Write-Host "Parameter -Server must be specified." -foregroundcolor red -backgroundcolor black
	Break
}

if ($Server -eq "") {
	Write-Host "Parameter -Server cannot be blank." -foregroundcolor red -backgroundcolor black
	Break
}

$GenerateTempDBInstall = $GenerateTempDBInstall.TrimStart().TrimEnd()
$Database = $Database.TrimStart().TrimEnd()
$DBExists = $DBExists.ToUpper().TrimStart().TrimEnd()

# TempDB installs determine the values of most of our other parameters, so check this right after the server.
if ( ($null -eq $GenerateTempDBInstall) -or ($GenerateTempDBInstall -eq "") )  {
	$GenerateTempDBInstall = "N"
}

if ( ($GenerateTempDBInstall -ne "N") -and ($GenerateTempDBInstall -ne "Y") ) {
    Write-Host "Parameter -GenerateTempDBInstall must be Y or N if specified" -foregroundcolor red -backgroundcolor black
	Break
}

if ($GenerateTempDBInstall -eq "Y") {
    $Database = "TempDB"
    $DBExists = "Y"
	$SessionDataHoursToKeep = "8"
	$ServerDataDaysToKeep = "3"
}

if ( ($null -eq $Database) -or ($Database -eq "") )  {
	$Database = "ChiRho"
}

if ( ($null -eq $SessionDataHoursToKeep) -or ($SessionDataHoursToKeep -eq "") ) {
	$SessionDataHoursToKeep = "336"
    # 14 days
}

[int]$SessionDataHoursToKeep_num = [convert]::ToInt32($SessionDataHoursToKeep, 10)

if ( ($SessionDataHoursToKeep_num -le 0) -or ($SessionDataHoursToKeep_num -gt 4320) ) {
    Write-Host "Parameter -SessionDataHoursToKeep cannot be <= 0 or > 4320 (180 days)" -foregroundcolor red -backgroundcolor black
	Break
}

if ( ($null -eq $ServerDataDaysToKeep) -or ($ServerDataDaysToKeep -eq "") ) {
	$ServerDataDaysToKeep = "30"
}

[int]$ServerDataDaysToKeep_num = [convert]::ToInt32($ServerDataDaysToKeep, 10)

if ( ($ServerDataDaysToKeep_num -lt 3) -or ($ServerDataDaysToKeep_num -gt 30) ) {
    Write-Host "Parameter -ServerDataDaysToKeep cannot be < 3 or > 30 days" -foregroundcolor red -backgroundcolor black
	Break
}


if ( ( $null -eq $DBExists) -or ($DBExists -eq "") ) {
    $DBExists = "N"
}

if ( ($DBExists -ne "N") -and ($DBExists -ne "Y") ) {
    Write-Host "Parameter -DBExists must be Y or N if specified" -foregroundcolor red -backgroundcolor black
	Break
}

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

Write-Host "Parameter -Server value: $Server"
Write-Host "Parameter -GenerateTempDBInstall value: $GenerateTempDBInstall"
Write-Host "Parameter -Database value: $Database"
Write-Host "Parameter -SessionDataHoursToKeep value: $SessionDataHoursToKeep"
Write-Host "Parameter -ServerDataDaysToKeep value: $ServerDataDaysToKeep"
Write-Host "Parameter -DBExists value: $DBExists"
Write-Host "Variable curScriptLoc value: $curScriptLoc"

$installerlogsloc = $curScriptLoc + "InstallationLogs\"

$installerLogFile = $installerlogsloc + "ChiRho_installation" + "_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date)

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Beginning installation..." 
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Parameter Validation complete. Proceeding with installation on server " + $Server + ", Database " + $Database + ", SessionDataHoursToKeep " + $SessionDataHoursToKeep + ", ServerDataDaysToKeep " + $ServerDataDaysToKeep + ", DBExists " + $DBExists
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

$curtime = Get-Date -format s
$outmsg = $curtime + "------> Installation operations will be logged to " + $installerLogFile
Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

CD $curScriptLoc 

# omit the output redirect during dev since it is faster:
# powershell.exe -noprofile -command .\InstallerScripts\generate_tempdb_install.ps1 -Server $Server -Database $Database -SessionDataHoursToKeep $SessionDataHoursToKeep -ServerDataDaysToKeep $ServerDataDaysToKeep -DBExists $DBExists -curScriptLocation $curScriptLoc > $installerLogFile
powershell.exe -noprofile -command .\InstallerScripts\generate_tempdb_install.ps1 -Server $Server -Database $Database -SessionDataHoursToKeep $SessionDataHoursToKeep -ServerDataDaysToKeep $ServerDataDaysToKeep -DBExists $DBExists -curScriptLocation $curScriptLoc
