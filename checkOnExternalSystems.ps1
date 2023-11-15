#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Check-On-External-Systems-SQL
#
# Version: 1.0.0
#####################################################
# Initialize default values
$p = $person | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$NonUniqueFields = [System.Collections.Generic.List[PSCustomObject]]::new()

# The entitlementContext contains the configuration
# - configuration: The configuration that is set in the Custom PowerShell configuration
$eRef = $entitlementContext | ConvertFrom-Json
$c = $eRef.configuration

# The account object contains the account mapping that is configured
$a = $account | ConvertFrom-Json

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to SQL server.
$connectionString = $c.connectionString
$username = $c.username
$password = $c.password
$table = $c.table

#region Change mapping here
$valuesToCheck = [PSCustomObject]@{
    "SamAccountName"                     = [PSCustomObject]@{ # This is the value that is returned to HelloID in NonUniqueFields
        accountValue   = $a.samaccountname
        databaseColumn = "SamAccountName"
    }
    "AdditionalFields.UserPrincipalName" = [PSCustomObject]@{ # This is the value that is returned to HelloID in NonUniqueFields
        accountValue   = $a.AdditionalFields.userPrincipalName
        databaseColumn = "UserPrincipalName"
    }
    "AdditionalFields.Mail"              = [PSCustomObject]@{ # This is the value that is returned to HelloID in NonUniqueFields
        accountValue   = $a.AdditionalFields.mail
        databaseColumn = "Mail"
    }
}

# Raise iteration of all configured fields when one is not unique
$syncIterations = $false
#endregion Change mapping here

#region functions
function Invoke-SQLQuery {
    param(
        [parameter(Mandatory = $true)]
        $ConnectionString,

        [parameter(Mandatory = $false)]
        $Username,

        [parameter(Mandatory = $false)]
        $Password,

        [parameter(Mandatory = $true)]
        $SqlQuery,

        [parameter(Mandatory = $true)]
        [ref]$Data
    )
    try {
        $Data.value = $null

        # Initialize connection and execute query
        if (-not[String]::IsNullOrEmpty($Username) -and -not[String]::IsNullOrEmpty($Password)) {
            # First create the PSCredential object
            $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new($Username, $securePassword)
 
            # Set the password as read only
            $credential.Password.MakeReadOnly()
 
            # Create the SqlCredential object
            $sqlCredential = [System.Data.SqlClient.SqlCredential]::new($credential.username, $credential.password)
        }
        # Connect to the SQL server
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new()
        $SqlConnection.ConnectionString = "$ConnectionString"
        if (-not[String]::IsNullOrEmpty($sqlCredential)) {
            $SqlConnection.Credential = $sqlCredential
        }
        $SqlConnection.Open()
        Write-Verbose "Successfully connected to SQL database" 

        # Set the query
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new()
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery

        # Set the data adapter
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new()
        $SqlAdapter.SelectCommand = $SqlCmd

        # Set the output with returned data
        $DataSet = [System.Data.DataSet]::new()
        $null = $SqlAdapter.Fill($DataSet)

        # Set the output with returned data
        $Data.value = $DataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
    }
    catch {
        $Data.Value = $null
        throw $_
    }
    finally {
        if ($SqlConnection.State -eq "Open") {
            $SqlConnection.close()
            Write-Verbose "Successfully disconnected from SQL database"
        }
    }
}
#endregion functions

try {
    # Query current data in database
    try {
        # Enclose Property Names with brackets []
        $querySelectProperties = $("[" + ($valuesToCheck.PsObject.Properties.Value.databaseColumn -join "],[") + "]")
        $querySelect = "
        SELECT
            $($querySelectProperties)
        FROM
            $table"

        Write-Verbose "Querying data from table [$($table)]. Query: $($querySelect)"

        $querySelectSplatParams = @{
            ConnectionString = $connectionString
            Username         = $username
            Password         = $password
            SqlQuery         = $querySelect
            ErrorAction      = "Stop"
        }
        $querySelectResult = [System.Collections.ArrayList]::new()
        Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult)

        Write-Verbose "Successfully queried data from table [$($table)]. Query: $($querySelect). Returned rows: $(($querySelectResult | Measure-Object).Count)"
    }
    catch {
        $ex = $PSItem
        # Set Verbose error message
        $verboseErrorMessage = $ex.Exception.Message
        # Set Audit error message
        $auditErrorMessage = $ex.Exception.Message

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error querying data from table [$($table)]. Query: $($querySelect). Error Message: $($auditErrorMessage)"
                IsError = $True
            })

        # Use throw, as auditLogs are not available in check on external system
        throw "Error querying data from table '[$($table)]. Query: $($querySelect). Error Message: $($auditErrorMessage)"
    }

    # Check values against database data
    Try {
        foreach ($valueToCheck in $valuesToCheck.PsObject.Properties) {
            if ($valueToCheck.Value.accountValue -in $querySelectResult."$($valueToCheck.Value.databaseColumn)") {
                Write-Warning "$($valueToCheck.Name) value [$($valueToCheck.Value.accountValue)] is NOT unique in database column [$($valueToCheck.Value.databaseColumn)]"
                [void]$NonUniqueFields.Add("$($valueToCheck.Name)")
            }
            else {
                Write-Verbose "$($valueToCheck.Name) value [$($valueToCheck.Value.accountValue)] is unique in database column '$($valueToCheck.Value.databaseColumn)]"
            }
        }
    }
    catch {
        $ex = $PSItem
        # Set Verbose error message
        $verboseErrorMessage = $ex.Exception.Message
        # Set Audit error message
        $auditErrorMessage = $ex.Exception.Message

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error checking mapped values against database data. Error Message: $($auditErrorMessage)"
                IsError = $True
            })

        # Use throw, as auditLogs are not available in check on external system
        throw "Error checking mapped values against database data. Error Message: $($auditErrorMessage)"
    }
}
catch {
    $ex = $PSItem
    # Set Verbose error message
    $verboseErrorMessage = $ex.Exception.Message
    # Set Audit error message
    $auditErrorMessage = $ex.Exception.Message

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    # Use throw, as auditLogs are not available in check on external system
    throw "Error performing uniqueness check on external systems. Error Message: $($auditErrorMessage)"
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }

    # When syncIterations is set to true, set NonUniqueFields to all configured fields
    if (($NonUniqueFields | Measure-Object).Count -ge 1 -and $syncIterations -eq $true) {
        $NonUniqueFields = $valuesToCheck.PsObject.Properties.Name
    }

    # Send results
    $result = [PSCustomObject]@{
        Success         = $success

        # Add field name as string when field is not unique
        NonUniqueFields = $NonUniqueFields
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)
}