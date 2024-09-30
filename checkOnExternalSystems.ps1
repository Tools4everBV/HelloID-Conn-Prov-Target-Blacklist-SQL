#####################################################
# HelloID-Conn-Prov-Target-Blacklist-Check-On-External-Systems-SQL
#####################################################

# Initialize default values
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

#region Change mapping here; make sure the tables exist, see the readme on github for more info
$attributeNames = @('SamAccountName', 'UserPrincipalName')

# Raise iteration of all configured fields when one is not unique
$syncIterations = $true
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

    $valuesToCheck = [PSCustomObject]@{}
    foreach ($attributeName in $attributeNames) {
        if ($a.PsObject.Properties.Name -contains $attributeName) {
            $valuesToCheck | Add-Member -MemberType NoteProperty -Name $attributeName -Value $a.$attributeName
        }
    }
    if (-not[String]::IsNullOrEmpty($valuesToCheck)) {

        # Query current data in database
        foreach ($attribute in $valuesToCheck.PSObject.Properties) {
            try {
                $querySelect = "SELECT * FROM $($attribute.Name) WHERE [AttributeValue] = '$($attribute.Value)'"

                $querySelectSplatParams = @{
                    ConnectionString = $connectionString
                    Username         = $username
                    Password         = $password
                    SqlQuery         = $querySelect
                    ErrorAction      = "Stop"
                }

                $querySelectResult = [System.Collections.ArrayList]::new()
                Invoke-SQLQuery @querySelectSplatParams -Data ([ref]$querySelectResult)
                $selectRowCount = ($querySelectResult | measure-object).count
                Write-Verbose "Successfully queried data from table [$($attribute.Name)]. Query: $($querySelect). Returned rows: $selectRowCount)"

                if ($selectRowCount -ne 0) {
                    Write-Warning "$($attribute.Name) value [$($attribute.Value)] is NOT unique in table [$($attribute.Name)]"
                    [void]$NonUniqueFields.Add($attribute.Name)
                }
                else {
                    Write-Verbose "$($attribute.Name) value [$($attribute.Value)] is unique in table [$($attribute.Name)]"
                }
            } catch {
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
    if (-not($auditLogs.IsError -contains $true)) {
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