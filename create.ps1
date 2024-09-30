#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Create-Update-SQL
# Use data from dependent system
# Script can be used as a create and update script
#####################################################

# Initialize default values
$c = $actionContext.configuration

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}

$actionContext.DryRun = $false
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

    $tables = $($actionContext.Data | Select-Object * -ExcludeProperty EmployeeId, LastModified).PSObject.Properties.Name 

    foreach ($table in $tables) {
        try {
            $attributeValue = $actionContext.Data.$table
            $account = $actionContext.Data | Select-Object * -ExcludeProperty $tables
            $account | Add-Member -NotePropertyName 'AttributeValue' -NotePropertyValue $attributeValue

            # Enclose Property Names with brackets []
            $querySelectProperties = $("[" + ($($account.PSObject.Properties.Name) -join "],[") + "]")
            $querySelect = "SELECT $($querySelectProperties) FROM $table WHERE [AttributeValue] = '$attributeValue'"
            Write-verbose "Querying data from table [$table]. Query: $($querySelect)"

            $querySelectSplatParams = @{
                ConnectionString = $connectionString
                Username         = $username
                Password         = $password
                SqlQuery         = $querySelect
                ErrorAction      = "Stop"
            }
            $querySelectResult = [System.Collections.ArrayList]::new()
            Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult) -verbose:$false

            $selectRowCount = ($querySelectResult | measure-object).count
            Write-Verbose "Successfully queried data from table [$table]. Query: $($querySelect). Returned rows: $selectRowCount"

            if ($selectRowCount -eq 1) {
                $correlatedAccount = $querySelectResult

                $action = "UpdateAccount"

            }
            elseif ($selectRowCount -eq 0) {
                $action = "CreateAccount"
            }
            else {
                Throw "multiple ($selectRowCount) rows found with attribute [$table]"
            }


            # Update blacklist database
            switch ($action) {
                "CreateAccount" {

                    # Enclose Property Names with brackets [] & Enclose Property Values with single quotes ''
                    $queryInsertProperties = $("[" + ($account.PSObject.Properties.Name -join "],[") + "]")
                    $queryInsertValues = $("'" + ($account.PSObject.Properties.Value -join "','") + "'")
                    $queryInsert = "INSERT INTO $table ($($queryInsertProperties)) VALUES ($($queryInsertValues))"

                    $queryInsertSplatParams = @{
                        ConnectionString = $connectionString
                        Username         = $username
                        Password         = $password
                        SqlQuery         = $queryInsert
                        ErrorAction      = "Stop"
                    }

                    $queryInsertResult = [System.Collections.ArrayList]::new()
                    if (-not($actioncontext.dryRun -eq $true)) {
                        Write-Verbose "Inserting row into table [$table]. Query: $($queryInsert)"
                        Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)
                    }
                    else {
                        Write-Warning "DryRun: Would insert row into table [$table]. Query: $($queryInsert)"
                    }
                    $outputContext.AccountReference = $account.employeeId
                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            Message = "Successfully inserted row into table [$table] with attributeValue [$attributeValue]"
                            IsError = $false
                        })
                    break
                }
                "UpdateAccount" {
                    if ($correlatedAccount.EmployeeId -ne $account.EmployeeId) {
                        $queryUpdateSet = "SET [EmployeeId]=$($account.EmployeeId), [LastModified]='$($account.LastModified)'"
                        $queryUpdate = "UPDATE [$table] $queryUpdateSet WHERE [attributeValue] = '$attributeValue'"

                        $queryUpdateSplatParams = @{
                            ConnectionString = $connectionString
                            Username         = $username
                            Password         = $password
                            SqlQuery         = $queryUpdate
                            ErrorAction      = "Stop"
                        }

                        $queryUpdateResult = [System.Collections.ArrayList]::new()
                        if (-not($actioncontext.dryRun -eq $true)) {
                            Write-Verbose "Updating row from table [$table]. Query: $($queryUpdate)"
                            Invoke-SQLQuery @queryUpdateSplatParams -Data ([ref]$queryUpdateResult)
                        }
                        else {
                            Write-Warning "DryRun: Would update row from table [$table]. Query: $($queryUpdate)"
                        }
                        $outputContext.AccountReference = $account.employeeId

                        $outputContext.auditlogs.Add([PSCustomObject]@{
                                Message = "Successfully updated row with attributeValue [$attributeValue]."
                                IsError = $false
                            })
                    }
                    else {
                        Write-Verbose "Nothing to update for person"
                    }
                    break
                }
            }
        }
        catch {
            $ex = $PSItem
            $auditErrorMessage = $ex.Exception.Message
            Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($auditErrorMessage)"
            $outputContext.auditlogs.Add([PSCustomObject]@{
                    Message = "Failed to inserte data into table [$table] with attributeValue [$attributeValue]: $($auditErrorMessage)"
                    IsError = $true
                })
        }
    }
}
catch {
    $ex = $PSItem
    $auditErrorMessage = $ex.Exception.Message
    #Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($auditErrorMessage)"
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-not($outputContext.auditlogs.IsError -contains $true)) {
        $outputContext.success = $true
    }
}