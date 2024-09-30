#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Delete-SQL
# Use data from dependent system
# 
# 1. if attribute value is empty, query on employeeId
# 2. do not insert row on delete (only update)
# 3. 
#####################################################
$actionContext.DryRun = $false
# Initialize default values
$c = $actionContext.configuration

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

    $tables = $($actionContext.Data | Select-Object * -ExcludeProperty EmployeeId, LastModified).PSObject.Properties.Name 

    foreach ($table in $tables) {
        try {
            $attributeValue = $actionContext.Data.$table
            $account = $actionContext.Data | Select-Object * -ExcludeProperty $tables
            $account | Add-Member -NotePropertyName 'AttributeValue' -NotePropertyValue $attributeValue

            # Enclose Property Names with brackets []
            $querySelectProperties = $("[" + ($($account.PSObject.Properties.Name) -join "],[") + "]")
            if ([string]::IsNullOrEmpty($attributeValue)) {
                $querySelect = "SELECT $($querySelectProperties) FROM $table WHERE [EmployeeId] = '$($actionContext.References.Account)'"
            } else {
                $querySelect = "SELECT $($querySelectProperties) FROM $table WHERE [AttributeValue] = '$attributeValue'"
            }
            
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
                $action = "Skip" #"CreateAccount" # skip action
            }
            else {
                Throw "multiple ($selectRowCount) rows found with attribute [$table]" # IS this a problem?
            }


            # Update blacklist database
            switch ($action) {
                "Skip" {
                        Write-Verbose "Skipping action query select returned 0 results for table [$table]. Query: $($querySelect)"
                    
                        $outputContext.auditlogs.Add([PSCustomObject]@{
                                Message = "No row found in blacklist for attribute [$table] and employeeId [$($actionContext.References.Account)]"
                                IsError = $false
                            })
                    break
                }
                "UpdateAccount" {
                    if ([string]::IsNullOrEmpty($attributeValue)) {                          
                        $queryUpdateSet = "[LastModified]='$($account.LastModified)'"
                        $queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [EmployeeId] = '$($actionContext.References.Account)'"
                        $auditMessage = "Successfully updated [lastModified] in table [$table] on rows with employeeId [$($actionContext.References.Account)]"
                    } else {
                        $queryUpdateSet = "SET [EmployeeId]='$($account.EmployeeId)', [LastModified]='$($account.LastModified)'"
                        $queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [attributeValue] = '$attributeValue'"
                        $auditMessage = "Successfully updated [EmployeeId, LastModified] on table [$table] on rows with attributeValue [$attributeValue]"
                    }

                    $queryUpdateSplatParams = @{
                        ConnectionString = $connectionString
                        Username         = $username
                        Password         = $password
                        SqlQuery         = $queryUpdate
                        ErrorAction      = "Stop"
                    }

                    if (-not($actioncontext.dryRun -eq $true)) {
                        Write-Verbose "Updating row from table [$table]. Query: $($queryUpdate)"
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