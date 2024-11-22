#####################################################
# HelloID-Conn-Prov-Target-Blacklist-SQL-Delete
# Use data from dependent system
# Only set whenDeleted on all records where column employeeId = externalId
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
        $SqlConnection.ConnectionString = $ConnectionString
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
    $querySelect = "SELECT * FROM $table WHERE [employeeId] = '$($actionContext.References.Account)' AND [WhenDeleted] IS NULL"

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

    if ($selectRowCount -gt 0) {
        $action = "UpdateAccount"
    }
    else {
        $action = "Skip"
    }

    # Update blacklist database
    switch ($action) {
        "Skip" {
            Write-Information "Skipping action query select returned 0 results for table [$table]. Query: $($querySelect)"

            $outputContext.auditlogs.Add([PSCustomObject]@{
                    Message = "No row without a WhenDeleted date found in blacklist for attribute [$table] and employeeId [$($actionContext.References.Account)]"
                    IsError = $false
                })
            break
        }
        "UpdateAccount" {
            $queryUpdateSet = "[whenDeleted]='$($actionContext.data.whenDeleted)'"
            $queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [employeeId] = '$($actionContext.References.Account)' AND [WhenDeleted] IS NULL"
            $auditMessage = "Successfully set [whenDeleted] for rows with employeeId [$($actionContext.References.Account)]"

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
    Write-Warning "QuerySelect: $querySelect"
    Write-Warning "QueryUpdate: $queryUpdate"
    $outputContext.auditlogs.Add([PSCustomObject]@{
            Message = "Failed to update data in table [$table] : $($auditErrorMessage)"
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-not($outputContext.auditlogs.IsError -contains $true)) {
        $outputContext.success = $true
    }
}