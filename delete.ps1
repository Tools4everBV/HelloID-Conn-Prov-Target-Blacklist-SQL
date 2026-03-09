#####################################################
# HelloID-Conn-Prov-Target-Blacklist-SQL-Delete
# Use data from dependent system
#####################################################

$table = $actionContext.configuration.table

$attributeNames = $($actionContext.Data | Select-Object * -ExcludeProperty employeeId, whenDeleted, whenCreated, whenUpdated).PSObject.Properties.Name

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
#endregion functions

try {
    # Verify account reference
    $actionMessage = "verifying account reference"
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw "The account reference could not be found"
    }

    # Import data from table
    $actionMessage = "importing data from table [$table]"

    Write-Information "Imported data from table [$table]"

    foreach ($attributeName in $attributeNames) {
        # Check if attribute is in table
        $actionMessage = "querying row in table [$table] where [attributeName] = [$($attributeName)] AND [employeeID] = [$($actionContext.References.Account)]"

        $querySelect = "SELECT * FROM [$table] WHERE [attributeName] = '$attributeName' AND [employeeId] = '$($actionContext.References.Account)'"

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
        Write-Information "Queried row in table [$table] where [attributeName] = [$($attributeName)] AND [employeeID] = [$($actionContext.References.Account)]. Result count: $selectRowCount"

        foreach ($dbCurrentRow in $querySelectResult) {
            if ([string]::IsNullOrEmpty($dbCurrentRow.whenDeleted)) {
                $action = "Update"
            }
            else {
                $action = "WhenDeletedAlreadySet"
            }
        
            switch ($action) {
                "Update" {
                    # Update row
                    $actionMessage = "updating [whenDeleted] and [whenUpdated] for row in table [$table] where [$($attributeName)] = [$($dbCurrentRow.attributeValue)] AND [employeeID] = [$($actionContext.References.Account)]"
                    
                    # Create new object for update
                    $updateObject = [PSCustomObject]@{
                        whenDeleted = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff")
                        whenUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff")
                    }

                    # Build SET clause from updateObject properties
                    $queryUpdateSet = (($updateObject.PSObject.Properties | ForEach-Object { 
                                if ($_.Value -eq $null) { 
                                    "[$($_.Name)]=null" 
                                }
                                else { 
                                    "[$($_.Name)]='$($_.Value)'" 
                                } 
                            }) -join ', ')
                    $queryUpdate = "UPDATE [$table] SET $queryUpdateSet WHERE [attributeName] = '$attributeName' AND [attributeValue] = '$($dbCurrentRow.attributeValue)' AND [employeeId] = '$($actionContext.References.Account)'"

                    $queryUpdateSplatParams = @{
                        ConnectionString = $actionContext.configuration.connectionString
                        Username         = $actionContext.configuration.username
                        Password         = $actionContext.configuration.password
                        SqlQuery         = $queryUpdate
                        ErrorAction      = "Stop"
                    }

                    if (-not($actioncontext.dryRun -eq $true)) {
                        $queryUpdateResult = [System.Collections.ArrayList]::new()
                        Invoke-SQLQuery @queryUpdateSplatParams -Data ([ref]$queryUpdateResult)

                        $outputContext.auditlogs.Add([PSCustomObject]@{
                                # Action  = "" # Optional
                                Message = "Updated [whenDeleted] to [$($updateObject.whenDeleted)] for row in table [$table] where [$($attributeName)] = [$($dbCurrentRow.attributeValue)] AND [employeeID] = [$($actionContext.References.Account)]."
                                IsError = $false
                            })
                    }
                    else {
                        Write-Warning "DryRun: Would update [whenDeleted] to [$($updateObject.whenDeleted)] for row in table [$table] where [$($attributeName)] = [$($dbCurrentRow.attributeValue)] AND [employeeID] = [$($actionContext.References.Account)]."
                    }

                    break
                }

                "WhenDeletedAlreadySet" {
                    $actionMessage = "skipping updating row in table [$table] where [$($attributeName)] = [$($dbCurrentRow.attributeValue)] AND [employeeID] = [$($actionContext.References.Account)]"

                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Skipped updating row in table [$table] where [$($attributeName)] = [$($dbCurrentRow.attributeValue)] AND [employeeID] = [$($actionContext.References.Account)]. reason: [whenDeleted] is already set."
                            IsError = $false
                        })

                    break
                }
            }
        }
    }
}
catch {
    $ex = $PSItem

    $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"

    Write-Warning $warningMessage

    $outputContext.auditlogs.Add([PSCustomObject]@{
            # Action  = "" # Optional
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-not($outputContext.auditlogs.IsError -contains $true)) {
        $outputContext.success = $true
    }
}