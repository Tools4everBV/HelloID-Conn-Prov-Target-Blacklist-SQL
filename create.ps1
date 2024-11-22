#####################################################
# HelloID-Conn-Prov-Target-Blacklist-SQL-Create
# Use data from dependent system
#####################################################

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
        $SqlConnection.ConnectionString = $actionContext.configuration.connectionString
        if (-not[String]::IsNullOrEmpty($sqlCredential)) {
            $SqlConnection.Credential = $sqlCredential
        }
        $SqlConnection.Open()
        Write-Information "Successfully connected to SQL database"

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
            Write-Information "Successfully disconnected from SQL database"
        }
    }
}

try {
    $table = $actionContext.configuration.table

    $attributeNames = $($actionContext.Data | Select-Object * -ExcludeProperty employeeId, whenDeleted).PSObject.Properties.Name

    foreach ($attributeName in $attributeNames) {
        try {

            $attributeValue = $actionContext.Data.$attributeName -Replace "'", "''"
            $account = $actionContext.Data | Select-Object * -ExcludeProperty $attributeNames
            $account | Add-Member -NotePropertyName 'attributeName' -NotePropertyValue $attributeName
            $account | Add-Member -NotePropertyName 'attributeValue' -NotePropertyValue $attributeValue

            # Enclose Property Names with brackets []
            $querySelectProperties = $("[" + ($($account.PSObject.Properties.Name) -join "],[") + "]")
            $querySelect = "SELECT $($querySelectProperties) FROM [$table] WHERE [attributeName] = '$attributeName' AND [attributeValue] = '$attributeValue'"
            Write-Information "Querying data from table [$table]. Query: $($querySelect)"

            $querySelectSplatParams = @{
                ConnectionString = $actionContext.configuration.connectionString
                Username         = $actionContext.configuration.username
                Password         = $actionContext.configuration.password
                SqlQuery         = $querySelect
                ErrorAction      = "Stop"
            }
            $querySelectResult = [System.Collections.ArrayList]::new()
            Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult) -verbose:$false

            $selectRowCount = ($querySelectResult | measure-object).count
            Write-Information "Successfully queried data from table [$table] for attribute [$attributeName]. Query: $($querySelect). Returned rows: $selectRowCount"

            if ($selectRowCount -eq 1) {
                $correlatedAccount = $querySelectResult

                $action = "UpdateAccount"

            }
            elseif ($selectRowCount -eq 0) {
                $action = "CreateAccount"
            }
            else {
                Throw "multiple ($selectRowCount) rows found with attribute [$attributeName]"
            }

            # Update blacklist database
            switch ($action) {
                "CreateAccount" {

                    # Enclose Property Names with brackets [] & Enclose Property Values with single quotes ''
                    $queryInsertProperties = $("[" + ($account.PSObject.Properties.Name -join "],[") + "]")
                    $queryInsertValues = $("'" + ($account.PSObject.Properties.Value -join "','") + "'")
                    $queryInsert = "INSERT INTO $table ($($queryInsertProperties)) VALUES ($($queryInsertValues))"

                    $queryInsertSplatParams = @{
                        ConnectionString = $actionContext.configuration.connectionString
                        Username         = $actionContext.configuration.username
                        Password         = $actionContext.configuration.password
                        SqlQuery         = $queryInsert
                        ErrorAction      = "Stop"
                    }

                    $queryInsertResult = [System.Collections.ArrayList]::new()
                    if (-not($actioncontext.dryRun -eq $true)) {
                        Write-Information "Inserting row in table [$table] for attribute [$attributeName] and value [$attributeValue]. Query: $($queryInsert)"
                        Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)
                    }
                    else {
                        Write-Warning "DryRun: Would insert row in table [$table] for attribute [$attributeName] and value [$attributeValue]. Query: $($queryInsert)"
                    }
                    $outputContext.AccountReference = $account.employeeId
                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            Message = "Successfully inserted row in table [$table] for attribute [$attributeName] and value [$attributeValue]"
                            IsError = $false
                        })
                    break
                }
                "UpdateAccount" {
                    if ($correlatedAccount.employeeId -ne $account.employeeId -or $correlatedAccount.whenDeleted -ne '') {
                        $queryUpdateSet = "SET [employeeId]='$($account.employeeId)', [whenDeleted]=null"
                        $queryUpdate = "UPDATE [$table] $queryUpdateSet WHERE [attributeValue] = '$attributeValue'"

                        $queryUpdateSplatParams = @{
                            ConnectionString = $actionContext.configuration.connectionString
                            Username         = $actionContext.configuration.username
                            Password         = $actionContext.configuration.password
                            SqlQuery         = $queryUpdate
                            ErrorAction      = "Stop"
                        }

                        $queryUpdateResult = [System.Collections.ArrayList]::new()
                        if (-not($actioncontext.dryRun -eq $true)) {
                            Write-Information "Updating row from table [$table]. Query: $($queryUpdate)"
                            Invoke-SQLQuery @queryUpdateSplatParams -Data ([ref]$queryUpdateResult)
                        }
                        else {
                            Write-Warning "DryRun: Would update updated row in table [$table] for attribute [$attributeName] and value [$attributeValue]. Query: $($queryUpdate)"
                        }
                        $outputContext.AccountReference = $account.employeeId

                        $outputContext.auditlogs.Add([PSCustomObject]@{
                                Message = "Successfully updated row in table [$table] for attribute [$attributeName] and value [$attributeValue]"
                                IsError = $false
                            })
                    }
                    else {
                        Write-Information "Nothing to update for person"
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
                    Message = "Failed to insert data into table [$table] for attribute [$attributeName] with value [$attributeValue]: $($auditErrorMessage)"
                    IsError = $true
                })
        }
    }
}
catch {
    $ex = $PSItem
    $auditErrorMessage = $ex.Exception.Message
    Write-Information "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($auditErrorMessage)"

    $outputContext.auditlogs.Add([PSCustomObject]@{
        Message = "Generic error: $($auditErrorMessage)"
        IsError = $true
    })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-not($outputContext.auditlogs.IsError -contains $true)) {
        $outputContext.success = $true
    }
}