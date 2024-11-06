# HelloID-Conn-Prov-Target-Blacklist-SQL

Repository for HelloID Provisioning Target Connector to SQL Blacklist

<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/network/members"><img src="https://img.shields.io/github/forks/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL" alt="Forks Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/pulls"><img src="https://img.shields.io/github/issues-pr/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL" alt="Pull Requests Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/issues"><img src="https://img.shields.io/github/issues/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL" alt="Issues Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Tools4everBV/HelloID-Conn-Prov-Target-Blacklist-SQL?color=2b9348"></a>

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://cdn-icons-png.flaticon.com/128/4443/4443857.png">
</p>

## Table of Contents

- [HelloID-Conn-Prov-Target-Blacklist-SQL](#helloid-conn-prov-target-blacklist-sql)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Requirements](#requirements)
  - [Repository contents](#repository-contents)
  - [Connection settings](#connection-settings)
  - [Remarks](#remarks)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

This connector allows for the storage of attribute values that must remain unique, such as SamAccountName and/or UserPrincipalName, in a blacklist database. When a new account is created, this database is checked alongside the primary target system to verify the uniqueness of these account attributes.

## Requirements

- HelloID Provisioning agent (cloud or on-prem).
- Available MSSQL database (External server or local SQL(express) instance).
- SQL database setup containing a table created with the query in the createTableBlacklist.sql file.
- Rights to database for the agent's service account or use a SQL-authenticated account.
- (Optional) Database table is filled with the current AD data.

## Repository contents

The HelloID connector consists of the template scripts shown in the following table.

| Action                            | Action(s) Performed                             | Comment                                                                                                                                                                   |
| --------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| create.ps1 | Write account data to SQL DB table             | Uses account data from another system. Can also be used as an update script |
| delete.ps1 | Write whenDeleted date to SQL DB table             | Uses account data from another system. Can also be used as an update script |
| configuration.json | Default configuration file             ||
| fieldMapping.json | Default field mapping file             ||
| checkOnExternalSystemsAd.ps1        | Check mapped fields against the SQL database              | This is configured in the built-in Active Directory connector |
| createTableBlacklist.sql        | Script to create the SQL table in the SQL database              |Run this within the SQL Management Studio|
| /GenerateUniqueData/example.create.ps1     | Generate unique value and write to SQL DB table | Checks the current data in SQL and generates a value that doesn't exist yet. Use this when generating a random number and use this as input for your AD or Azure AD system. Please be aware this is an example build for the legacy PowerShell connector.  |

## Connection settings

The following settings are required to connect to SQL DB.

| Setting           | Description                                                                  | Mandatory |
| ----------------- | ---------------------------------------------------------------------------- | --------- |
| Connection string | String value of the connection string used to connect to the SQL database    | Yes       |
| Table             | String value of the table name in which the blacklist values reside          | Yes       |
| Username          | String value of the username of the SQL user to use in the connection string | No        |
| Password          | String value of the password of the SQL user to use in the connection string | No        |
| isDebug           | Toggle debug logging                                                         | No        |

## Correlation configuration

The correlation configuration is not used or required in this connector

## Remarks

- This connector is designed to connect to an MS-SQL DB. Optionally you can also configure this to use another DB, such as SQLite or Oracle. However, the connector currently isn't desgined for this and requires additional configuration.
- Make sure the attribute names in the mapping correspond with the attribute names in the primary source system.
- If you need to update the values as well, you can use the account creation script as an update script without modification. Just remember to update the mapping, too.

## Getting help
> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.
> [!TIP]
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/.
