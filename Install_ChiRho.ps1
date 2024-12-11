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
#	FILE NAME: Install_ChiRho.ps1
#
#	AUTHOR:			Aaron Morelli
#					aaronmorelli@zoho.com
#					@sqlcrossjoin
#					sqlcrossjoin.wordpress.com
#
#	PURPOSE: Install the ChiRho toolkit
#
#   INSTRUCTIONS:
#       First, install this module from PSGallery:
#           Install-Module -Name SqlServer -RequiredVersion 22.2.0 -AllowClobber -Scope CurrentUser
#               (I had problems with the most recent version, 22.3, so reverted to the prev version)

param ( 
[Parameter(Mandatory=$true)][string]$SQLServer, 
) 



# Check if SMO assemblies are available (they should be, if the above "Install-Module SqlServer" command was run successfully)
try {
    [void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    [void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc")
    Write-Host "SQL Server Management Objects (SMO) is installed."
} catch {
    Write-Host "SQL Server Management Objects (SMO) is not installed."
}



.EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2014

        Creates an SMO Server object that connects using Windows Authentication

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $wincred

        Creates an SMO Server object that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $sqlcred

        Login to sql2014 as SQL login sqladmin.
    
        .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD / Azure Active Directory, then performs a sample query.
    
        .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database dbatools -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD Integrated Auth, then performs a sample query.
    
         .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance "myserver.public.cust123.database.windows.net,3342" -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL Managed instance using AAD / Azure Active Directory, then performs a sample query.
    
        .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -SqlCredential $cred -Tenant guidheremaybename
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        When connecting from a non-Azure workstation, logs into Azure using Universal with MFA Support with a username and password, then performs a sample query.

        Note that generating access tokens is not supported on Core, so when using Tenant on Core, we rewrite the connection string with Active Directory Service Principal authentication instead.