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
#	FILE NAME: generate_installation_artifacts.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Takes the template DDL (that contains tokens like @@CHIRHO_SCHEMA@@) and creates a set of installation
#       scripts based on the settings for Database Name, Schema Name, and the type of SQL Server being installed
# .\generate_installation_artifacts.ps1 -InstanceType "blah" -DatabaseName "ChiRho" -DBExists "N" -SchemaName "dbo" -curScriptLocation "C:\aa\anots\ChiRho_MSSQL\"
#####

param ( 
# Do not need the -Server parameter b/c this script just generates the .sql files that will be run.
# We *do* need the database name and schema name, and the type of SQL Server that we will be installing into.
[Parameter(Mandatory=$true)][string]$InstanceType, 
[Parameter(Mandatory=$true)][string]$DatabaseName,
[Parameter(Mandatory=$true)][string]$DBExists,
[Parameter(Mandatory=$true)][string]$SchemaName,
# [Parameter(Mandatory=$true)][string]$SessionDataHoursToKeep,
# [Parameter(Mandatory=$true)][string]$ServerDataDaysToKeep,
[Parameter(Mandatory=$true)][string]$curScriptLocation
) 

$ErrorActionPreference = "Stop"

$target_script_file_01 = $curScriptLocation + "InstallationArtifacts\01_CoreXR_and_AutoWho.sql"

# truncate the contents of our output files:
Set-Content -Path $target_script_file_01 -Value ""

$source_folder_tables = $curScriptLocation + "Code\Tables\"

$curScript = ""
$curFileName = ""

# Read all CoreXR files in, modify their contents accordingly, and append to the output script.
try {
    Get-ChildItem -Path $source_folder_tables -File -Filter "CoreXR*" | Sort-Object Name | ForEach-Object {
        $curScript = $_.FullName
        $curFileName = $_.Name

        # Read the content of the file into a string variable
        # $current_file_content = Get-Content -Path $_.FullName -Raw -Encoding Unicode
        $current_file_content = Get-Content -Path $_.FullName -Raw

        # Our token replacement logic depends on whether we are installing into tempdb (global temp objects)
        # or into a regular database.
        if ( $DatabaseName -eq "tempdb")  {
            # Note the extra "." character that is present in this replace, as opposed to the "else" case
            $new_file_content = $current_file_content -replace [regex]::Escape("@@CHIRHO_SCHEMA@@."), "##"
        }
        else {
            $new_file_content = $current_file_content -replace [regex]::Escape("@@CHIRHO_SCHEMA@@"), $SchemaName
        }

        # Append the processed content to the output file
        Add-Content -Path $target_script_file_01 -Value $new_file_content

        #In Windows 2012 R2, we are ending up in the SQLSERVER:\ prompt, when really we want to be in the file system provider. Doing a simple "CD" command gets us back there
        # CD $curScriptLocation
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


# TODO: For the tempdb case, we may want the final step of an artifact file to actually to start a trace.
# It would not be the installer that runs the artifact file, but rather a human that opens that .sql file
# in a new query window on the instance. Making the final step the starting of a trace has the benefit of
# keeping that session active/open so that the global temp tables do not go away. 
# Since there is both an AutoWho trace and a ServerEye trace, we want 2 separate scripts.

# For the "normal" install, we are still generating artifact files, but I think we would want them to be installed
# by the Powershell installer

