# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2025-12-24

This is a major release of HelloID-Conn-Prov-Target-Blacklist-SQL with significant enhancements to match the CSV blacklist connector functionality and Tools4ever V2 connector standards.

### Added

- **Retention period support**: Configurable retention period for deleted values with automatic expiration logic
- **Cross-check validation**: Support for `crossCheckOn` configuration to validate uniqueness across different attribute types (e.g., checking if an email exists as a proxy address)
- **keepInSyncWith functionality**: Automatic cascading of non-unique status across related fields
- **Skip optimization**: Redundant database queries are automatically skipped once a field is marked non-unique
- **Multiple records handling**: Improved logic to filter by employeeId when multiple rows are found
- **Enhanced error handling**: New action types `OtherEmployeeId` and `MultipleFound` with detailed error messages
- **Timestamp tracking**: Added `whenCreated`, `whenUpdated`, and `whenDeleted` columns with proper datetime2(7) precision
- **Comprehensive documentation**: Restructured README with use cases, supported features table, and V2 template compliance
- **Credential support**: Full SQL authentication support with secure credential initialization

### Changed

- **Create script**: Restructured to match CSV connector format with improved action calculation logic
- **Update script**: Aligned with create script logic including retention period validation
- **Delete script**: Rewritten to process per-attribute instead of bulk updates, matching CSV structure
- **checkOnExternalSystemsAd.ps1**: Complete rewrite with advanced field checking configuration and retention period awareness
- **fieldMapping.json**: Updated to match CSV structure exactly (employeeId only for Create, attributes for Create/Update/Delete)
- **Logging**: Changed from Write-Information intentions to result-based logging; adjusted log levels (unique=Information, non-unique=Warning)
- **Audit logs**: Moved inside non-dryRun blocks to prevent audit entries during preview mode
- **SQL queries**: Simplified UPDATE queries to only modify `whenDeleted` and `whenUpdated` fields
- **Account reference**: Moved to absolute top of create script for consistency

### Fixed

- **SQL syntax errors**: Fixed bracket joining in SELECT queries that caused "missing or empty column name" errors
- **UPDATE query logic**: Removed employeeId from SET clause and added to WHERE clause for proper record targeting
- **Credential initialization**: Fixed missing credential code in checkOnExternalSystemsAd.ps1's Invoke-SQLQuery function
- **Configuration**: Removed invalid type field from retentionPeriod configuration

### Deprecated

- Legacy syncIterations and syncIterationsAttributeNames approach replaced by keepInSyncWith configuration

### Removed

- `whenDeleted` field from fieldMapping.json (managed internally by scripts)
- Unnecessary Write-Information statements for action intentions
