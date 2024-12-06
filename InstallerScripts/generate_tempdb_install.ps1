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
#	FILE NAME: generate_tempdb_install.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Create .sql scripts that enable installing the ChiRho database objects (tables, procedures, and so forth) into 
#   TempDB (by using global temp tables and global stored procedures).
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

$core_parent = $curScriptLocation + "CoreXR\"
# $core_config = $core_parent + "CoreXRConfig.sql"
# $core_schemas = $core_parent + "CreateSchemas.sql"
$core_tables = $core_parent + "01_Tables"

$output_dir = $curScriptLocation + "InstallerScripts\TempDB_Install\"
$table_ddl_file = $output_dir + "01_Table_DDL.sql"

# truncate the contents of our output files:
Set-Content -Path $table_ddl_file -Value ""


# Core tables
try {
    Get-ChildItem -Path $core_tables -File | ForEach-Object {
        $curScript = $_.FullName
        $curFileName = $_.Name

        # Read the content of the file into a string variable
        # $current_file_content = Get-Content -Path $_.FullName -Raw -Encoding Unicode
        $current_file_content = Get-Content -Path $_.FullName -Raw

        # Perform the find-and-replace operation
        $new_file_content = $current_file_content -replace [regex]::Escape("@@CHIRHO_SCHEMA@@."), "##"

        # Append the processed content to the output file
        Add-Content -Path $table_ddl_file -Value $new_file_content

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

Write-Host "" -foregroundcolor cyan -backgroundcolor black