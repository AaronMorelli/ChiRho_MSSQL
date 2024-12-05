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

# the Database name can be any alphanumeric string. SessionDataHoursToKeep defines how much
# time the session-related DMV data is kept. ServerDataDaysToKeep defines how much time the 
# server-related DMV data is kept. Session DMV data is generally much larger than server-level
# data, hence the difference in granularity.
#####

param ( 
[Parameter(Mandatory=$true)][string]$Server, 
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

$Database = $Database.TrimStart().TrimEnd()

if ( ($Database -eq $null) -or ($Database -eq "") )  {
	$Database = "ChiRho"
}

if ( ($SessionDataHoursToKeep -eq $null) -or ($SessionDataHoursToKeep -eq "") ) {
	$SessionDataHoursToKeep = "336"
    # 14 days
}

[int]$SessionDataHoursToKeep_num = [convert]::ToInt32($SessionDataHoursToKeep, 10)

if ( ($SessionDataHoursToKeep_num -le 0) -or ($SessionDataHoursToKeep_num -gt 4320) ) {
    Write-Host "Parameter -SessionDataHoursToKeep cannot be <= 0 or > 4320 (180 days)" -foregroundcolor red -backgroundcolor black
	Break
}

if ( ($ServerDataDaysToKeep -eq $null) -or ($ServerDataDaysToKeep -eq "") ) {
	$ServerDataDaysToKeep = "30"
}

[int]$ServerDataDaysToKeep_num = [convert]::ToInt32($ServerDataDaysToKeep, 10)

if ( ($ServerDataDaysToKeep_num -lt 3) -or ($ServerDataDaysToKeep_num -gt 30) ) {
    Write-Host "Parameter -ServerDataDaysToKeep cannot be < 3 or > 30 days" -foregroundcolor red -backgroundcolor black
	Break
}

$DBExists = $DBExists.ToUpper().TrimStart().TrimEnd()

if ( ( $DBExists -eq $null) -or ($DBExists -eq "") ) {
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

powershell.exe -noprofile -command .\InstallerScripts\install_database_objects.ps1 -Server $Server -Database $Database -SessionDataHoursToKeep $SessionDataHoursToKeep -ServerDataDaysToKeep $ServerDataDaysToKeep -DBExists $DBExists -curScriptLocation $curScriptLoc > $installerLogFile
$scriptresult = $?

$curtime = Get-Date -format s

if ($scriptresult -eq $true) {
    Write-Host "Installation completed successfully" -backgroundcolor black -foregroundcolor green
}
else {
    Write-Host "Installation failed. Please consult $installerLogFile for more details." -backgroundcolor black -foregroundcolor red
    Write-Host "Installation aborted at: " + $curtime -foregroundcolor red -backgroundcolor black
}

