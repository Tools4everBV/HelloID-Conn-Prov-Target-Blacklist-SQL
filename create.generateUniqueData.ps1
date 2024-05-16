#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Create-SQL
#
# Version: 2.0.0
#####################################################
# Initialize default values
$c = $actionContext.configuration

$outputContext.Success = $false 

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}

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


try {
    # Used to connect to SQL server.
    $connectionString = $c.connectionString
    $username = $c.username
    $password = $c.password
    $table = $c.table

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationPersonField = $actionContext.CorrelationConfiguration.PersonField
        $correlationAccountField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue


        if ([string]::IsNullOrEmpty($($correlationAccountField)) -OR [string]::IsNullOrEmpty($($correlationPersonField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }
    }
    else {
        throw 'Enabling correlation is mandatory'
    }

    $account = $actionContext.Data

    try {
        # Enclose Property Names with brackets []
        $querySelectProperties = $("[" + ($account.PSObject.Properties.Name -join "],[") + "]")
        
        $querySelect = "
        SELECT
            $($querySelectProperties)
        FROM
            $table
        WHERE [$correlationAccountField] = '$correlationValue'
            "

        Write-verbose "Querying data from table [$($table)]. Query: $($querySelect)"

        $querySelectSplatParams = @{
            ConnectionString = $connectionString
            Username         = $username
            Password         = $password
            SqlQuery         = $querySelect
            ErrorAction      = "Stop"
        }
        $querySelectResult = [System.Collections.ArrayList]::new()
        Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult) -verbose:$false

        Write-Verbose "Successfully queried data from table [$($table)]. Query: $($querySelect). Returned rows: $(($querySelectResult | Measure-Object).Count)"

        $selectRowCount = ($querySelectResult | measure-object).count

        if ($selectRowCount -eq 1) {
            $correlatedAccount = $querySelectResult
            $action = "CorrelateAccount"
            
        }
        elseif ($selectRowCount -eq 0) {
            $action = "createAccount"
        }
        else {
            Throw "multiple ($selectRowCount) rows found with correlationAccountField [$correlationValue]"
        }

    }
    catch {
        $ex = $PSItem
        # Set Audit error message
        $auditErrorMessage = $ex.Exception.Message

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($auditErrorMessage)"
        Throw "$auditErrorMessage"
    }

    # Update blacklist database
    try {
        switch ($action) {
            "CorrelateAccount" {
                Write-Verbose "correlated Account data: $($correlatedAccount | convertto-json)"

                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.($correlationAccountField)
                $outputContext.AccountCorrelated = $true

                $outputContext.auditlogs.Add([PSCustomObject]@{
                        Action  = $action # Optional
                        Message = "Successfully $action with $correlationAccountField [$correlationValue]."
                        IsError = $false;
                    });

                break
            }
            "createAccount" {

                # Enclose Property Names with brackets []
                $queryInsertProperties = $("[" + ($account.PSObject.Properties.Name -join "],[") + "]")
                # Enclose Property Values with single quotes ''
                $queryInsertValues = $("'" + ($account.PSObject.Properties.Value -join "','") + "'")
            
                $queryInsert = "
            INSERT INTO $table
                ($($queryInsertProperties))
            VALUES
                ($($queryInsertValues))"

                $queryInsertSplatParams = @{
                    ConnectionString = $connectionString
                    Username         = $username
                    Password         = $password
                    SqlQuery         = $queryInsert
                    ErrorAction      = "Stop"
                }

                $queryInsertResult = [System.Collections.ArrayList]::new()
                if (-not($actioncontext.dryRun -eq $true)) {
                    Write-Verbose "Inserting data into table [$($table)]. Query: $($queryInsert)"
                    Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)
                }
                else {
                    Write-Warning "DryRun: Would insert data into table [$($table)]. Query: $($queryInsert)"
                }
                $outputContext.AccountReference = $correlationValue
                $outputContext.auditlogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Successfully inserted data into table [$($table)] with $correlationAccountField [$correlationValue]"
                        IsError = $false;
                    });   
            }
        } 
    }
    catch {
        $ex = $PSItem
        $auditErrorMessage = $ex.Exception.Message
        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($auditErrorMessage)"

        Throw "Error processing data. Error Message: $($auditErrorMessage)"
    }
  
}
catch {
    $ex = $PSItem
    $auditErrorMessage = $ex.Exception.Message

    $outputContext.auditlogs.Add([PSCustomObject]@{
            # Action  = $action
            Message = "Executing script failed: $($auditErrorMessage)"
            IsError = $True
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($outputContext.auditlogs.IsError -contains $true)) {
        $outputContext.success = $true
    }

}