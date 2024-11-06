#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Delete-SQL
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
        $SqlConnection.ConnectionString = "$ConnectionString"
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
            $attributeValue = $actionContext.Data.$attributeName
            $account = $actionContext.Data | Select-Object * -ExcludeProperty $attributeNames
            $account | Add-Member -NotePropertyName 'attributeName' -NotePropertyValue $attributeName
            $account | Add-Member -NotePropertyName 'attributeValue' -NotePropertyValue $attributeValue

            # Enclose Property Names with brackets []
            $querySelectProperties = $("[" + ($($account.PSObject.Properties.Name) -join "],[") + "]")
            if ([string]::IsNullOrEmpty($attributeValue)) {
                $querySelect = "SELECT $($querySelectProperties) FROM $table WHERE [attributeName] = '$attributeName' AND [employeeId] = '$($actionContext.References.Account)'"
            }
            else {
                $querySelect = "SELECT $($querySelectProperties) FROM $table WHERE [attributeName] = '$attributeName' AND [attributeValue] = '$attributeValue'"
            }
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
            Write-Information "Successfully queried data from table [$table]. Query: $($querySelect). Returned rows: $selectRowCount"

            if ($selectRowCount -eq 1) {
                $action = "UpdateAccount"
            }
            elseif ($selectRowCount -eq 0) {
                $action = "Skip"
            }
            else {
                throw "multiple ($selectRowCount) rows found with attribute [$attributeName]" # IS this a problem?
            }

            # Update blacklist database
            switch ($action) {
                "Skip" {
                    Write-Information "Skipping action query select returned 0 results for table [$table]. Query: $($querySelect)"

                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            Message = "No row found in blacklist for attribute [$table] and employeeId [$($actionContext.References.Account)]"
                            IsError = $false
                        })
                    break
                }
                "UpdateAccount" {
                    if ([string]::IsNullOrEmpty($attributeValue)) {
                        $queryUpdateSet = "[whenDeleted]='$($account.whenDeleted)'"
                        #$queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [employeeId] = '$($actionContext.References.Account)'"
                        $queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [attributeName] = '$attributeName' AND [employeeId] = '$($actionContext.References.Account)'"
                        $auditMessage = "Successfully updated [whenDeleted] for rows with attribute [$attributeName] and employeeId [$($actionContext.References.Account)]"
                    }
                    else {
                        $queryUpdateSet = "[EmployeeId]='$($account.employeeId)', [whenDeleted]='$($account.whenDeleted)'"
                        $queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [attributeName] = '$attributeName' AND [attributeValue] = '$attributeValue'"
                        $auditMessage = "Successfully updated [employeeId, whenDeleted] for rows with attribute [$attributeName] and value [$attributeValue]"
                    }

                    $queryUpdateSplatParams = @{
                        ConnectionString = $actionContext.configuration.connectionString
                        Username         = $actionContext.configuration.username
                        Password         = $actionContext.configuration.password
                        SqlQuery         = $queryUpdate
                        ErrorAction      = "Stop"
                    }

                    if (-not($actioncontext.dryRun -eq $true)) {
                        Write-Information "Updating row from table [$table]. Query: $($queryUpdate)"
                        $queryUpdateResult = [System.Collections.ArrayList]::new()
                        Invoke-SQLQuery @queryUpdateSplatParams -Data ([ref]$queryUpdateResult)
                    }
                    else {
                        Write-Warning "DryRun: Would update row from table [$table]. Query: $($queryUpdate)"
                    }

                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            Message = $auditMessage
                            IsError = $false
                        })

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