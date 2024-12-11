    param (
        [Parameter(Mandatory=$true)]
        [string]$ServerInstance,

        [Parameter(Mandatory=$false)]
        [bool]$TrustServerCertificate = $false,

        [Parameter(Mandatory=$false)]
        [string]$Database,

        [Parameter(Mandatory=$false)]
        [string]$Username,

        [Parameter(Mandatory=$false)]
        [bool]$InstallInTempDB = $false
    )

    try {
        Write-Host "ChiRho version 1.0" -backgroundcolor black -foregroundcolor cyan
        Write-Host "Apache 2.0 license" -backgroundcolor black -foregroundcolor cyan
        Write-Host "Copyright (c) 2024 Aaron Morelli" -backgroundcolor black -foregroundcolor cyan

        $CurScriptName = $MyInvocation.MyCommand.Name
        $CurDur = $MyInvocation.MyCommand.Path
        $CurDur = $CurDur.Replace($CurScriptName,"")
        $curScriptLoc = $CurDur.TrimStart().TrimEnd()

        if ( !($curScriptLoc.EndsWith("\")) ) {
            $curScriptLoc = $curScriptLoc + "\"
        }

        # Do I need this?
        # CD $curScriptLoc 



        # Use the SqlServer module's Invoke-Sqlcmd cmdlet for running our scripts.
        if (-not (Get-Module -Name SqlServer -ListAvailable)) {
            Write-Error "The SqlServer module is not installed. Please install it using 'Install-Module -Name SqlServer -RequiredVersion 22.2.0 -Scope CurrentUser'."
            return
        } else {
            Import-Module -Name SqlServer -ErrorAction Stop
        }

        $InstanceType = ""
        $EditionType = ""
        $IsAWSRDS = ""
        $ProductMajorVersion = ""
        $ProductMinorVersion = ""
        $XRDatabaseExists = ""

        # Build up the connection string that we will be using.
        $ConnString_Base = "Server=$ServerInstance;"


        if ($TrustServerCertificate) {
            # Needed if the server instance value doesn't match the name on the server's certificate, which is true
            # when you do things like "."
            $ConnString_Base = $ConnString_Base + "TrustServerCertificate=True;"
        }

        # Are we using Windows auth or SQL auth?
        # TODO: we prob want to add a check that happens right above this, where we check the $ServerInstance value for an
        # Azure SQL path or something like that, to see if we are in a situation where we need to authenticate via Azure AD
        if ($Username) {
            # Prompt for password securely
            $Password = Read-Host -Prompt "Enter password for user $Username" -AsSecureString
            $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            )

            # Use SQL authentication
            $ConnString_Base = $ConnString_Base + "User Id=$Username;Password=$PlainPassword;"
        } else {
            # Build the connection string for Windows Authentication
            $ConnString_Base = $ConnString_Base + "Integrated Security=True;"
        }

        # We support "installing" into tempdb, for cases where we need to troubleshoot an issue but do not have sign-off on
        # installing the objects longer-term.
        if ($InstallInTempDB) {
            if ($Database) {
                throw [System.Exception] "If parameter -InstallInTempDB is set to true, a name should not be specified for the -Database parameter."
            } else {
                $EffectiveDatabase = "tempdb"
            }
        } else {
            if ($Database) {
                $EffectiveDatabase = $Database
            } else {
                throw [System.Exception] "Either a value must be supplied for parameter -Database, or -InstallInTempDB must be specified. A suitable value for -Database is 'ChiRho'."
            }
        }

        # We are going to connect (without specifying a database so that we get the default DB for our login) and run the below query to learn
        # about our target SQL instance environment.
        # TODO: this will fail if we try to connect to an Azure SQL DB (or Synapse, Fabric, etc) because connecting w/o specifying a DB is not
        # supported. So again, we'll need to detect via the $ServerInstance value if we are connecting to an Azure SQL path and then connect
        # to the DB name that is explicitly supplied.
        $Query = "
SELECT 
	CASE SERVERPROPERTY('EngineEdition')
		WHEN 1 THEN 'Desktop'  --never available from SQL 2005 forward
		WHEN 2 THEN 'Standard' --or Web, or Business Intelligence
		WHEN 3 THEN 'Enterprise_Evaluation_Developer'
		WHEN 4 THEN 'Express'
		WHEN 5 THEN 'Azure_SQL_DB'
		WHEN 6 THEN 'Azure_Synapse'
		WHEN 8 THEN 'Azure_SQL_Managed_Instance'
		WHEN 9 THEN 'Azure_SQL_Edge'
		WHEN 11 THEN 'Azure_Synapse_Serverless'
		ELSE '?'
	END as InstanceType,
	CASE WHEN DB_ID('rdsadmin') IS NOT NULL
		AND SERVERPROPERTY('EngineEdition') IN (2, 3)
		THEN 'Y'
		ELSE 'N'
	END as IsAWSRDS,
    CASE WHEN DB_ID('$EffectiveDatabase') IS NOT NULL
        THEN 'Y'
        ELSE 'N'
    END as XRDatabaseExists,
	CASE 
		WHEN LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%enterprise%' 
			OR LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%evaluation%' 
			OR LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%developer%' 
			THEN 'Enterprise_Evaluation_Developer'
		WHEN LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%standard%' 
			OR LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%business intelligence%' 
			THEN 'standard'
		WHEN LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%express%' 
			THEN 'express'
		WHEN LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%web%' 
			THEN 'web'
		WHEN LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) = 'sql azure' THEN 'sql azure'  --SQL Database or Azure Synapse Analytics
		WHEN LOWER(CONVERT(NVARCHAR(500), SERVERPROPERTY('Edition'))) LIKE '%sql edge%' THEN 'edge'
		ELSE '?'
	END as EditionType,

	CONVERT(INT, SERVERPROPERTY('ProductMajorVersion')) as ProductMajorVersion,
	CONVERT(INT, SERVERPROPERTY('ProductMinorVersion')) as ProductMinorVersion
        "

        # Now connect, and run the query
        $Result = Invoke-Sqlcmd -Query $Query -ConnectionString $ConnString_Base

        if ($Result) {
            $InstanceType = $Result.InstanceType
            $EditionType = $Result.EditionType
            $IsAWSRDS = $Result.IsAWSRDS
            $ProductMajorVersion = $Result.ProductMajorVersion
            $ProductMinorVersion = $Result.ProductMinorVersion
            $XRDatabaseExists = $Result.XRDatabaseExists
            Write-Host "Successfully connected to server '$ServerInstance' and database '$Database'."
            Write-Host "Instance Type: $InstanceType"
            Write-Host "Edition Type: $EditionType"
            Write-Host "Is AWS RDS?: $IsAWSRDS"
            Write-Host "ProductMajorVersion Type: $ProductMajorVersion"
            Write-Host "ProductMinorVersion Type: $ProductMinorVersion"
            Write-Host "$EffectiveDatabase Database Exists: $XRDatabaseExists"
        } else {
            throw [System.Exception] "Was not able to run the initial test query against -ServerInstance $ServerInstance."
        }

        # TODO: more checks:
        #  If -Database was specified, but $XRDatabaseExists is "N", then we need to fail
        #  If Instance Type and Edition Type are not supported, need to explain and then fail.


        # Once I am done validating, then we can get to work:
        $curtime = Get-Date -format s
        $outmsg = $curtime + "------> Beginning installation..." 
        Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

        $curtime = Get-Date -format s
        $outmsg = $curtime + "------> Parameter Validation complete. Proceeding with installation on server " + $Server + ", Database " + $Database + ", SessionDataHoursToKeep " + $SessionDataHoursToKeep + ", ServerDataDaysToKeep " + $ServerDataDaysToKeep + ", DBExists " + $DBExists
        Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan

        $curtime = Get-Date -format s
        $outmsg = $curtime + "------> Installation operations will be logged to " + $installerLogFile
        Write-Host $outmsg -backgroundcolor black -foregroundcolor cyan


    } catch {
        # re-raise our exception (for now...)
        throw
    }

# Example usage:
# For Windows Authentication:
# $connectionString = Connect-SQLServer -ServerInstance "localhost" -Database "TestDB"

# For SQL Authentication:
# $connectionString = Connect-SQLServer -ServerInstance "localhost" -Database "TestDB" -Username "sa"



# When I need to add a Database to the connection string:
# $ConnString_InitialQuery = "Server=$ServerInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True;"