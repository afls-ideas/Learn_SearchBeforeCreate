# SBC Troubleshooter

<a href="https://githubsfdeploy.herokuapp.com?owner=afls-ideas&repo=Learn_SearchBeforeCreate&ref=main">
  <img alt="Deploy to Salesforce" src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

LWC + Apex tool to diagnose why a user cannot find an account in Life Sciences Cloud's Search Before Create feature.

## What It Does

Select a **User** and an **Account**, click **Diagnose**, and the tool checks every prerequisite for searchability:

| Check | What it verifies |
|-------|-----------------|
| Account Exists | Account record and record type |
| IsPrimaryProvider | HealthcareProvider.IsPrimaryProvider = true (required for SOSL). Inline **fix button** to set it to true. |
| ContactPointAddress | Address exists with valid CountryCode |
| User Active | User is active with profile info |
| Search Preferences Level | Whether org-default or profile-specific settings apply |
| UserAdditionalInfo | AvailableCountries and PreferredCountry |
| In-Territory Search | Account country matches user's PreferredCountry |
| Out-of-Territory Search | Account country is in user's AvailableCountries |
| Account in User Territory | Territory alignment between account and user |
| Settings | EnableCountryBasedSearch, EnableSearchOutsideTerritory, etc. |

## Key Findings

### How Search Uses Countries

| Search Type | Country Filter |
|---|---|
| **In-territory** (basic search) | `UserAdditionalInfo.PreferredCountry` in WHERE clause |
| **Outside territory** (online search) | `UserAdditionalInfo.AvailableCountries` in SOSL |

### Data Model

Account Search Preferences are stored in standard objects (accessible via REST API, not direct Apex types):

| Object | Purpose |
|--------|---------|
| `LifeSciMetadataCategory` | Category = `AccountSearchPreferences` |
| `LifeSciMetadataRecord` | Config record (org-level or profile-level) |
| `LifeSciMetadataFieldValue` | Individual field settings |
| `LifeSciMetadataAssignment` | Profile/User-level assignment overrides |

### Profile-Level Overrides

Settings can be applied at org-level or per-profile. The tool detects which level applies to the selected user by checking `LifeSciMetadataAssignment` for a record matching the user's profile.

### Field Mapping (Account Search Preferences Page)

| UI Label | FieldName | DataType |
|----------|-----------|----------|
| Enable search outside territory | `EnableSearchOutsideTerritory` | BOOLEAN |
| Show only active accounts | `OnlyActiveAccountsInOutOfTerrSearch` | BOOLEAN |
| Add the country filter | `EnableSearchCountrySelector` | BOOLEAN |
| Enable country-specific search | `EnableCountryBasedSearch` | BOOLEAN |
| Search Outside Territory Record Types | `SearchOutsideTerritoryRecordTypes` | MULTIPICKLIST |
| Restrict to user's countries | `RestrictToUserAvailableCountry` | BOOLEAN |
| Search business licenses | `AccountIdentifierSearch` | BOOLEAN |
| Show accounts in map view | `EnableMaps` | BOOLEAN |
| Auto-align affiliations | `AccountsSearchAlignHardAffiliations` | BOOLEAN |
| Default Customer Filter | `CustomerFilterByDefault` | PICKLIST |
| Additional Provider Territory Field | `AdditionalPrvdAcctTerrAccountSearchField` | PICKLIST |
| Default Account Type Filters | `AccountRecordTypeAPIName` | MULTIPICKLIST |

## Architecture

```
LWC (demoSearchDiagnostic)
  └─► Apex Controller (DemoSearchDiagnosticController)
        ├─► VF Page (DemoSessionId) — provides valid REST API session
        ├─► REST API: LifeSciMetadataCategory/Record/FieldValue/Assignment
        ├─► REST API: HealthcareProvider, ContactPointAddress, UserAdditionalInfo
        ├─► REST API: ProviderAcctTerritoryInfo, UserTerritory2Association
        └─► Standard SOQL: User, Account, RecordType
```

## Deploy

```bash
sf project deploy start --source-dir force-app --target-org <your-org-alias>
```

The tool deploys as a tab called **SBC Troubleshooter** in the **AFLS Powertool** app.

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `DemoSearchDiagnosticController` | Apex Class | Diagnostic logic via REST API |
| `DemoSearchBeforeCreateConfigController` | Apex Class | Read/write Account Search Preferences (hidden, available for future use) |
| `DemoSearchDiagnosticControllerTest` | Apex Test | 7 tests covering diagnostic, fix, territories, visualization |
| `DemoSBCConfigControllerTest` | Apex Test | 6 tests covering config read/write |
| `demoSearchDiagnostic` | LWC | Diagnostic UI |
| `demoSearchBeforeCreateConfig` | LWC | Config editor UI (hidden, available for future use) |
| `DemoSessionId` | VF Page | Provides valid API session token |
| `SBC_Troubleshooter` | Tab + FlexiPage | App page in AFLS Powertool |
