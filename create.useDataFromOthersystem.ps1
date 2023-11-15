#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Create-SQL
#
# Version: 1.0.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

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
$account = [PSCustomObject]@{
    "SamAccountName"    = $p.Accounts.MicrosoftActiveDirectory.samaccountname # Property Name has to match the DB column name
    "UserPrincipalName" = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName # Property Name has to match the DB column name
    "Mail"              = $p.Accounts.MicrosoftActiveDirectory.mail # Property Name has to match the DB column name
}
#endregion Change mapping here

# Define aRef
$aRef = $account.UserPrincipalName # Use most unique propertie, e.g. SamAccountName or UserPrincipalName

# Define account properties to store in account data
$storeAccountFields = @("SamAccountName", "UserPrincipalName", "Mail")

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
    # Update blacklist database
    try {
        # Enclose Property Names with brackets []
        $queryInsertProperties = $("[" + ($account.PSObject.Properties.Name -join "],[") + "]")
        # Enclose Property Values with single quotes ''
        $queryInsertValues = $("'" + ($account.PSObject.Properties.Value -join "','") + "'")

        $queryInsert = "
        INSERT INTO $table
            ($($queryInsertProperties))
        VALUES
            ($($queryInsertValues))"
            
        if (-not($dryRun -eq $true)) {
            Write-Verbose "Inserting data into table [$($table)]. Query: $($queryInsert)"

            $queryInsertSplatParams = @{
                ConnectionString = $connectionString
                Username         = $username
                Password         = $password
                SqlQuery         = $queryInsert
                ErrorAction      = "Stop"
            }

            $queryInsertResult = [System.Collections.ArrayList]::new()
            Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)

            $auditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Successfully inserted data into table [$($table)]. Query: $($queryInsert)"
                    IsError = $false;
                });   
        }
        else {
            Write-Warning "DryRun: Would insert data into table [$($table)]. Query: $($queryInsert)"
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
                Message = "Error inserting data into table [$($table)]. Query: $($queryInsert). Error Message: $($auditErrorMessage)"
                IsError = $True
            })
    }

    # Define ExportData with account fields and correlation property 
    $exportData = $account.PsObject.Copy() | Select-Object $storeAccountFields
    # Add aRef to exportdata
    $exportData | Add-Member -MemberType NoteProperty -Name "AccountReference" -Value $aRef -Force
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
            Message = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
            IsError = $True
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }

    # Send results
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $aRef
        AuditLogs        = $auditLogs
        Account          = $account

        # Optionally return data for use in other systems
        ExportData       = $exportData
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)
}