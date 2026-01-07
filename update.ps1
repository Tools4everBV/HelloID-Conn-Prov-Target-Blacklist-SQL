#####################################################
# HelloID-Conn-Prov-Target-Blacklist-SQL-Update
# Use data from dependent system
#####################################################

$table = $actionContext.configuration.table
$retentionPeriod = $actionContext.configuration.retentionPeriod

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
        $SqlConnection.ConnectionString = $actionContext.configuration.connectionString
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
    # Verify account reference
    $actionMessage = "verifying account reference"
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw "The account reference could not be found"
    }

    foreach ($attributeName in $attributeNames) {
        # Check if attribute is in table
        $actionMessage = "querying row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)]"

        $attributeValue = $actionContext.Data.$attributeName -Replace "'", "''"

        $querySelect = "SELECT * FROM [$table] WHERE [attributeName] = '$attributeName' AND [attributeValue] = '$attributeValue'"

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
        Write-Verbose "Queried data FROM [$table] WHERE [attributeName] = '$attributeName' AND [attributeValue] = '$attributeValue'. Result count: $selectRowCount"

        # Calculate action
        $actionMessage = "calculating action"

        # If multiple rows are found, filter additionally for employeeId
        if ($selectRowCount -gt 1) {
            $correlatedAccount = $querySelectResult | Where-Object { $_.employeeId -eq $actionContext.References.Account }
            $selectRowCount = ($correlatedAccount | Measure-Object).count
        
            Write-Information "Multiple rows found where [$($attributeName)] = [$($actionContext.Data.$attributeName)]. Filtered additionally for employeeId. Result count: $selectRowCount"
        }

        if ($selectRowCount -eq 1) {
            $correlatedAccount = $querySelectResult
                
            # Check if value belongs to someone else
            if ($correlatedAccount.employeeId -ne $actionContext.References.Account) {
                # Check retention period if value is deleted
                if (-NOT [string]::IsNullOrEmpty($correlatedAccount.whenDeleted)) {
                    $whenDeletedDate = [datetime]($correlatedAccount.whenDeleted)
                    $daysDiff = (New-TimeSpan -Start $whenDeletedDate -End (Get-Date)).Days
                        
                    if ($daysDiff -lt $retentionPeriod) {
                        $action = "OtherEmployeeId"
                    }
                    else {
                        # Retention period expired, can reuse
                        $action = "Update"
                    }
                }
                else {
                    # Value belongs to someone else and not deleted
                    $action = "OtherEmployeeId"
                }
            }
            else {
                # Value belongs to current employee
                if (-not([string]::IsNullOrEmpty($correlatedAccount.whenDeleted))) {
                    # Clear whenDeleted to reactivate
                    $action = "Update"
                }
                else {
                    $action = "NoChanges" 
                }
            }
        }
        elseif ($selectRowCount -eq 0) {
            $action = "Create"
        }
        elseif ($selectRowCount -gt 1) {
            $action = "MultipleFound"
        }

        # Update blacklist database
        switch ($action) {
            "Create" {
                # Create row
                $actionMessage = "creating row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)] AND [employeeID] = [$($actionContext.References.Account)]"

                # Create new object for insert
                $insertObject = [PSCustomObject]@{
                    employeeId     = $actionContext.References.Account
                    attributeName  = $attributeName
                    attributeValue = $attributeValue
                    whenCreated    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff")
                    whenUpdated    = $null
                    whenDeleted    = $null
                }

                # Enclose Property Names with brackets [] & Enclose Property Values with single quotes ''
                $queryInsertProperties = $("[" + (($insertObject.PSObject.Properties.Name) -join "],[") + "]")
                $queryInsertValues = $(($insertObject.PSObject.Properties.Value | ForEach-Object { if ($_ -ne 'null' -and $null -ne $_) { "'$_'" } else { 'null' } }) -join ',')
                $queryInsert = "INSERT INTO $table ($($queryInsertProperties)) VALUES ($($queryInsertValues))"

                $queryInsertSplatParams = @{
                    ConnectionString = $actionContext.configuration.connectionString
                    Username         = $actionContext.configuration.username
                    Password         = $actionContext.configuration.password
                    SqlQuery         = $queryInsert
                    ErrorAction      = "Stop"
                }

                # Always set previousData to $null as the entire object isn't stored in HelloId, but previousData and data need to differ to log the change
                $outputContext.PreviousData | Add-Member -NotePropertyName $attributeName -NotePropertyValue $null -Force
                $outputContext.Data | Add-Member -NotePropertyName $attributeName -NotePropertyValue $attributeValue -Force

                
                if (-not($actioncontext.dryRun -eq $true)) {
                    $queryInsertResult = [System.Collections.ArrayList]::new()
                    Invoke-SQLQuery @queryInsertSplatParams -Data ([ref]$queryInsertResult)

                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Created row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)] AND [employeeID] = [$($actionContext.References.Account)]."
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would create row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)] AND [employeeID] = [$($actionContext.References.Account)]."
                }

                break
            }
            
            "Update" {
                # Update row - clear whenDeleted and update employeeId (either for current employee or reusing expired row)
                $actionMessage = "updating [employeeId] to [$($updateObject.employeeId)] and [whenDeleted] to [$($updateObject.whenDeleted)] for row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)]"

                # Create new object for update
                $updateObject = [PSCustomObject]@{
                    employeeId  = $actionContext.References.Account
                    whenDeleted = $null
                    whenUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff")
                }

                # Build SET clause from updateObject properties
                $queryUpdateSet = "SET " + (($updateObject.PSObject.Properties | ForEach-Object { 
                            if ($_.Value -eq $null) { 
                                "[$($_.Name)]=null" 
                            }
                            else { 
                                "[$($_.Name)]='$($_.Value)'" 
                            } 
                        }) -join ', ')
                $queryUpdate = "UPDATE [$table] $queryUpdateSet WHERE [attributeValue] = '$attributeValue' AND [attributeName] = '$attributeName'"

                $queryUpdateSplatParams = @{
                    ConnectionString = $actionContext.configuration.connectionString
                    Username         = $actionContext.configuration.username
                    Password         = $actionContext.configuration.password
                    SqlQuery         = $queryUpdate
                    ErrorAction      = "Stop"
                }

                # Always set previousData to $null as the entire object isn't stored in HelloId, but previousData and data need to differ to log the change
                $outputContext.PreviousData | Add-Member -NotePropertyName $attributeName -NotePropertyValue $null -Force
                $outputContext.Data | Add-Member -NotePropertyName $attributeName -NotePropertyValue $attributeValue -Force

                if (-not($actioncontext.dryRun -eq $true)) {
                    $queryUpdateResult = [System.Collections.ArrayList]::new()
                    Invoke-SQLQuery @queryUpdateSplatParams -Data ([ref]$queryUpdateResult)

                    $outputContext.auditlogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Updated [employeeId] to [$($updateObject.employeeId)] and [whenDeleted] to [$($updateObject.whenDeleted)] for row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)]."
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would update [employeeId] to [$($updateObject.employeeId)] and [whenDeleted] to [$($updateObject.whenDeleted)] for row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)]."
                }

                break
            }
            
            "NoChanges" {
                $actionMessage = "skipping updating row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)] AND [employeeID] = [$($actionContext.References.Account)]"

                # Set both previousData and data to the correlatedAccount object to show no changes
                $outputContext.PreviousData | Add-Member -NotePropertyName $attributeName -NotePropertyValue $correlatedAccount.attributeValue -Force
                $outputContext.Data | Add-Member -NotePropertyName $attributeName -NotePropertyValue $correlatedAccount.attributeValue -Force

                $outputContext.auditlogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Skipped updating row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)] AND [employeeID] = [$($actionContext.References.Account)]. reason: No changes."
                        IsError = $false
                    })

                break
            }

            "OtherEmployeeId" {
                $actionMessage = "updating row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)]"

                # Throw terminal error
                throw "A row was found where [$($attributeName)] = [$($actionContext.Data.$attributeName)]. However the EmployeeID [$($correlatedAccount.employeeId)] doesn't match the current person (expected: [$($actionContext.References.Account)]). Additionally, [whenDeleted] = [$($correlatedAccount.whenDeleted)] is still within the allowed threshold [$retentionPeriod days]. This should not be possible. Please check the database for inconsistencies."
                
                break
            }

            "MultipleFound" {
                $actionMessage = "updating row in table [$table] where [$($attributeName)] = [$($actionContext.Data.$attributeName)]"

                # Throw terminal error
                throw "Multiple rows were found in the database where [$($attributeName)] = [$($actionContext.Data.$attributeName)] AND [employeeID] = [$($actionContext.References.Account)]. This should not be possible. Please check the database for inconsistencies."
                
                break
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