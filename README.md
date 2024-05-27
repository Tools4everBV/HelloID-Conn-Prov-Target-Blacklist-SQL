# HelloID-Conn-Prov-Target-Blacklist-SQL
Repository for HelloID Provisioning Target Connector to SQL Blacklist

<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/network/members"><img src="https://img.shields.io/github/forks/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL" alt="Forks Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/pulls"><img src="https://img.shields.io/github/issues-pr/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL" alt="Pull Requests Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/issues"><img src="https://img.shields.io/github/issues/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL" alt="Issues Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL?color=2b9348"></a>

| :information_source: Information |
| :------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.  |

<p align="center">
  <img src="https://cdn-icons-png.flaticon.com/128/4443/4443857.png">
</p>

## Table of Contents
- [HelloID-Conn-Prov-Target-Blacklist-SQL](#helloid-conn-prov-target-blacklist-sql)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
  - [Introduction](#introduction)
    - [Connection settings](#connection-settings)
  - [Remarks](#remarks)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Requirements
- SQL database

## Introduction
With this connector we have the option to write unique values, e.g. SamAccountName and/or UserPrincipalName to a blacklist database.

The HelloID connector consists of the template scripts shown in the following table.

| Action                            | Action(s) Performed                             | Comment                                                                                                                                                                   |
| --------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| create.useDataFromOthersystem.ps1 | Write account data to SQL DB table              | Uses account data from another system like AD or Azure AD                                                                                                                 |
| create.generateUniqueData.ps1     | Generate unique value and write to SQL DB table | Checks the current data in SQL and generates a value that doesn't exist yet. Use this when generating a random number and use this as input for you AD or Azure AD system  |
| checkOnExternalSystems.ps1        | Check mapped fields against SQL DB              | This is configured in the built-in AD connector                                                                                                                           |

> [!IMPORTANT]
> create.generateUniqueData.ps1 is not converted to PS v2 connector yet.

### Connection settings
The following settings are required to connect to SQL DB.

| Setting           | Description                                                                  | Mandatory |
| ----------------- | ---------------------------------------------------------------------------- | --------- |
| Connection string | String value of the connection string used to connect to the SQL database    | Yes       |
| Username          | String value of the username of the SQL user to use in the connection string | No        |
| Password          | String value of the password of the SQL user to use in the connection string | No        |
| Table             | String value of the table name in which the blacklist values reside          | Yes       |


## Provisioning PowerShell V2 connector

### Correlation configuration
The correlation configuration is used to specify which properties will be used to match an existing account within {connectorName} to a person in HelloID.

Specify the following configuration:

    | Setting                   | Value        |
    | ------------------------- | ------------ |
    | Enable correlation        | `True`       |
    | Person correlation field  | `[externalID(default)]` |
    | Account correlation field | `[Account correlation Field]` |


### Mappings
A basic mapping ([_fieldMapping.json_](./fieldMapping.json)) is provided. Make sure to further customize these accordingly.

### Prerequisites

- [ ] HelloID Provisioning agent (cloud or on-prem).
- [ ] Available MSSQL database (External server or Local (express) instance)
- [ ] Rights to database for the Agent's service account or use a SQL-authenticated account.

## Remarks
- This connector is designed to connect to an MS-SQL DB. Optionally you can also configure this to use another DB, such as SQLite or Oracle. However, the connector currently isn't desgined for this and needs additional configuration.
- Will generate a SELECT and INSERT-query with all the configured fields from the mapping.
- Keeps the mapping names the same as the column names in the database.
- The configured correlation will be used in the WHERE condition to filter out the same person.


## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
