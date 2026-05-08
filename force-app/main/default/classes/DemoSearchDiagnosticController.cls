public with sharing class DemoSearchDiagnosticController {

    @TestVisible private static String testSessionId;

    private static String getSessionId() {
        if (Test.isRunningTest() && testSessionId != null) {
            return testSessionId;
        }
        String vfContent = Page.SessionId.getContent().toString();
        return vfContent.trim();
    }

    private static String restQuery(String soql) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String endpoint = baseUrl + '/services/data/v66.0/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + getSessionId());
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);
        return res.getBody();
    }

    @AuraEnabled
    public static List<Map<String, String>> getUserTerritories(Id userId) {
        List<Map<String, String>> territories = new List<Map<String, String>>();
        String response = restQuery(
            'SELECT Id, Territory2Id, Territory2.Name FROM UserTerritory2Association WHERE UserId = \'' + userId + '\''
        );
        Object parsed = JSON.deserializeUntyped(response);
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> result = (Map<String, Object>) parsed;
            List<Object> records = (List<Object>) result.get('records');
            if (records != null) {
                for (Object obj : records) {
                    Map<String, Object> rec = (Map<String, Object>) obj;
                    Map<String, Object> t2 = (Map<String, Object>) rec.get('Territory2');
                    Map<String, String> terrMap = new Map<String, String>();
                    terrMap.put('id', (String) rec.get('Territory2Id'));
                    terrMap.put('name', t2 != null ? (String) t2.get('Name') : 'Unknown');
                    territories.add(terrMap);
                }
            }
        }
        return territories;
    }

    @AuraEnabled
    public static Map<String, Object> diagnoseSearch(Id userId, Id accountId) {
        Map<String, Object> result = new Map<String, Object>();
        List<Map<String, Object>> checks = new List<Map<String, Object>>();

        // 1. Check if account exists and get basic info
        Account acct;
        try {
            acct = [
                SELECT Id, Name, IsPersonAccount, RecordType.Name, RecordType.DeveloperName,
                       PersonContactId, LastName, FirstName
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
        } catch (Exception e) {
            checks.add(buildCheck('Account Exists', 'FAIL', 'Account not found: ' + e.getMessage()));
            result.put('checks', checks);
            return result;
        }
        checks.add(buildCheck('Account Exists', 'PASS', acct.Name + ' (' + acct.RecordType.Name + ')'));

        // 2. Check HealthcareProvider record via REST
        String hpResponse = restQuery(
            'SELECT Id, IsPrimaryProvider, Status, AccountId FROM HealthcareProvider WHERE AccountId = \'' + accountId + '\' LIMIT 1'
        );
        Object hpParsed = JSON.deserializeUntyped(hpResponse);
        if (hpParsed instanceof Map<String, Object>) {
            Map<String, Object> hpResult = (Map<String, Object>) hpParsed;
            List<Object> hpRecords = (List<Object>) hpResult.get('records');
            if (hpRecords == null || hpRecords.isEmpty()) {
                checks.add(buildCheck('HealthcareProvider Record', 'FAIL', 'No HealthcareProvider record linked to this account'));
            } else {
                Map<String, Object> hp = (Map<String, Object>) hpRecords[0];
                Boolean isPrimary = (Boolean) hp.get('IsPrimaryProvider');
                if (isPrimary == true) {
                    checks.add(buildCheck('IsPrimaryProvider', 'PASS', 'true — account is searchable'));
                } else {
                    String hpId = (String) hp.get('Id');
                    Map<String, Object> hpCheck = buildCheck('IsPrimaryProvider', 'FAIL', 'false — search query filters on IsPrimaryProvider = true');
                    hpCheck.put('fixHpId', hpId);
                    checks.add(hpCheck);
                }
            }
        } else {
            checks.add(buildCheck('HealthcareProvider Record', 'WARN', 'Could not query HealthcareProvider'));
        }

        // 3. Check ContactPointAddress
        String cpaResponse = restQuery(
            'SELECT Id, Street, City, StateCode, CountryCode, IsPrimary FROM ContactPointAddress WHERE ParentId = \'' + accountId + '\' ORDER BY IsPrimary DESC LIMIT 5'
        );
        String accountCountry = '';
        Object cpaParsed = JSON.deserializeUntyped(cpaResponse);
        if (cpaParsed instanceof Map<String, Object>) {
            Map<String, Object> cpaResult = (Map<String, Object>) cpaParsed;
            List<Object> cpaRecords = (List<Object>) cpaResult.get('records');
            if (cpaRecords == null || cpaRecords.isEmpty()) {
                checks.add(buildCheck('ContactPointAddress', 'FAIL', 'No address records found for this account'));
            } else {
                Map<String, Object> primaryCpa = (Map<String, Object>) cpaRecords[0];
                accountCountry = (String) primaryCpa.get('CountryCode');
                String city = (String) primaryCpa.get('City');
                String street = (String) primaryCpa.get('Street');
                String cpaDetail = (accountCountry != null ? accountCountry : '') + ', ' + (city != null ? city : '');
                if (street != null) cpaDetail += ', ' + street;
                checks.add(buildCheck('ContactPointAddress', 'PASS', cpaRecords.size() + ' address(es). Primary: ' + cpaDetail));
            }
        }

        // 4. Check User info
        User usr;
        try {
            usr = [
                SELECT Id, Name, Username, ProfileId, Profile.Name, IsActive
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];
        } catch (Exception e) {
            checks.add(buildCheck('User Exists', 'FAIL', 'User not found'));
            result.put('checks', checks);
            return result;
        }

        if (!usr.IsActive) {
            checks.add(buildCheck('User Active', 'FAIL', 'User is inactive'));
        } else {
            checks.add(buildCheck('User Active', 'PASS', usr.Name + ' (' + usr.Profile.Name + ')'));
        }

        // 5. Determine which Account Search Preferences apply (org-level vs profile-specific)
        String effectiveRecordId = '';
        String effectiveRecordLabel = '';
        try {
            // Get the category ID first
            String catResponse = restQuery(
                'SELECT Id FROM LifeSciMetadataCategory WHERE Category = \'AccountSearchPreferences\' LIMIT 1'
            );
            String categoryId = '';
            Object catParsed = JSON.deserializeUntyped(catResponse);
            if (catParsed instanceof Map<String, Object>) {
                List<Object> catRecords = (List<Object>) ((Map<String, Object>) catParsed).get('records');
                if (catRecords != null && !catRecords.isEmpty()) {
                    categoryId = (String) ((Map<String, Object>) catRecords[0]).get('Id');
                }
            }

            if (String.isNotBlank(categoryId)) {
                // Get all metadata records for this category
                String recsResponse = restQuery(
                    'SELECT Id, Name, IsOrgLevel, IsActive FROM LifeSciMetadataRecord ' +
                    'WHERE LifeScienceMetadataCategoryId = \'' + categoryId + '\' AND IsActive = true'
                );
                Object recsParsed = JSON.deserializeUntyped(recsResponse);
                List<String> allRecordIds = new List<String>();
                String orgLevelRecordId = '';

                if (recsParsed instanceof Map<String, Object>) {
                    List<Object> recsRecords = (List<Object>) ((Map<String, Object>) recsParsed).get('records');
                    if (recsRecords != null) {
                        for (Object rObj : recsRecords) {
                            Map<String, Object> r = (Map<String, Object>) rObj;
                            String rId = (String) r.get('Id');
                            allRecordIds.add(rId);
                            Boolean isOrg = (Boolean) r.get('IsOrgLevel');
                            if (isOrg == true) {
                                orgLevelRecordId = rId;
                            }
                        }
                    }
                }

                // Check if user's profile has a specific assignment
                if (!allRecordIds.isEmpty()) {
                    String assignResponse = restQuery(
                        'SELECT Id, AssignedToId, LifeSciMetadataRecordId FROM LifeSciMetadataAssignment ' +
                        'WHERE AssignedToId = \'' + usr.ProfileId + '\' LIMIT 10'
                    );
                    Object assignParsed = JSON.deserializeUntyped(assignResponse);
                    if (assignParsed instanceof Map<String, Object>) {
                        List<Object> assignRecords = (List<Object>) ((Map<String, Object>) assignParsed).get('records');
                        if (assignRecords != null) {
                            for (Object aObj : assignRecords) {
                                Map<String, Object> a = (Map<String, Object>) aObj;
                                String aRecId = (String) a.get('LifeSciMetadataRecordId');
                                if (allRecordIds.contains(aRecId)) {
                                    effectiveRecordId = aRecId;
                                    break;
                                }
                            }
                        }
                    }
                }

                if (String.isNotBlank(effectiveRecordId)) {
                    effectiveRecordLabel = 'Profile-specific (' + usr.Profile.Name + ')';
                    checks.add(buildCheck('Search Preferences Level', 'INFO',
                        'Using PROFILE-LEVEL settings for "' + usr.Profile.Name + '" (overrides org defaults)'));
                } else {
                    effectiveRecordId = orgLevelRecordId;
                    effectiveRecordLabel = 'Org Default';
                    checks.add(buildCheck('Search Preferences Level', 'INFO',
                        'Using ORG-LEVEL settings (no profile-specific override for "' + usr.Profile.Name + '")'));
                }
            }
        } catch (Exception e) {
            checks.add(buildCheck('Search Preferences Level', 'WARN', 'Could not determine: ' + e.getMessage()));
        }
        result.put('effectiveRecordId', effectiveRecordId);
        result.put('effectiveRecordLabel', effectiveRecordLabel);

        // 6. Check UserAdditionalInfo
        String uaiResponse = restQuery(
            'SELECT Id, AvailableCountries, PreferredCountry FROM UserAdditionalInfo WHERE UserId = \'' + userId + '\' LIMIT 1'
        );
        String userCountries = '';
        String preferredCountry = '';
        Object uaiParsed = JSON.deserializeUntyped(uaiResponse);
        if (uaiParsed instanceof Map<String, Object>) {
            Map<String, Object> uaiResult = (Map<String, Object>) uaiParsed;
            List<Object> uaiRecords = (List<Object>) uaiResult.get('records');
            if (uaiRecords == null || uaiRecords.isEmpty()) {
                checks.add(buildCheck('UserAdditionalInfo', 'WARN', 'No UserAdditionalInfo record — country filtering may not work'));
            } else {
                Map<String, Object> uai = (Map<String, Object>) uaiRecords[0];
                userCountries = (String) uai.get('AvailableCountries');
                preferredCountry = (String) uai.get('PreferredCountry');
                String uaiDetail = 'AvailableCountries: ' + (userCountries != null ? userCountries : '(none)') +
                                 ' | PreferredCountry: ' + (preferredCountry != null ? preferredCountry : '(none)');
                checks.add(buildCheck('UserAdditionalInfo', 'PASS', uaiDetail));
            }
        }

        // 6. Country checks
        if (String.isNotBlank(accountCountry) && String.isNotBlank(preferredCountry)) {
            if (accountCountry.equalsIgnoreCase(preferredCountry)) {
                checks.add(buildCheck('In-Territory Search (PreferredCountry)', 'PASS',
                    'Account country ' + accountCountry + ' matches user\'s PreferredCountry — will appear in basic/in-territory search'));
            } else {
                checks.add(buildCheck('In-Territory Search (PreferredCountry)', 'FAIL',
                    'Account country ' + accountCountry + ' differs from user\'s PreferredCountry (' + preferredCountry + ') — will NOT appear in basic search'));
            }
        }

        if (String.isNotBlank(accountCountry) && String.isNotBlank(userCountries)) {
            Set<String> userCountrySet = new Set<String>(userCountries.split(';'));
            String uaiId = '';
            if (uaiParsed instanceof Map<String, Object>) {
                Map<String, Object> uaiResult3 = (Map<String, Object>) uaiParsed;
                List<Object> uaiRecords3 = (List<Object>) uaiResult3.get('records');
                if (uaiRecords3 != null && !uaiRecords3.isEmpty()) {
                    Map<String, Object> uai3 = (Map<String, Object>) uaiRecords3[0];
                    uaiId = (String) uai3.get('Id');
                }
            }
            if (userCountrySet.contains(accountCountry)) {
                checks.add(buildCheck('Out-of-Territory Search (AvailableCountries)', 'PASS',
                    'Account country ' + accountCountry + ' is in AvailableCountries (' + userCountries + ') — will appear in out-of-territory search'));
            } else {
                String detail = 'Account country ' + accountCountry + ' is NOT in AvailableCountries (' + userCountries + ')';
                if (String.isNotBlank(uaiId)) {
                    detail += '||LINK||' + uaiId;
                }
                checks.add(buildCheck('Out-of-Territory Search (AvailableCountries)', 'FAIL', detail));
            }
        }

        // 7. Check territory alignment
        String terrResponse = restQuery(
            'SELECT Id, Territory2Id, Territory2.Name, AccountId FROM ProviderAcctTerritoryInfo WHERE AccountId = \'' + accountId + '\' LIMIT 5'
        );
        String userTerrResponse = restQuery(
            'SELECT Id, Territory2Id, Territory2.Name FROM UserTerritory2Association WHERE UserId = \'' + userId + '\''
        );

        Object terrParsed = JSON.deserializeUntyped(terrResponse);
        Object userTerrParsed = JSON.deserializeUntyped(userTerrResponse);

        if (terrParsed instanceof Map<String, Object> && userTerrParsed instanceof Map<String, Object>) {
            Map<String, Object> terrResult = (Map<String, Object>) terrParsed;
            Map<String, Object> userTerrResult = (Map<String, Object>) userTerrParsed;
            List<Object> terrRecords = (List<Object>) terrResult.get('records');
            List<Object> userTerrRecords = (List<Object>) userTerrResult.get('records');

            if (terrRecords == null || terrRecords.isEmpty()) {
                checks.add(buildCheck('Account Territory', 'WARN', 'Account has no territory alignment'));
            } else {
                Set<String> userTerritoryIds = new Set<String>();
                List<String> userTerritoryNames = new List<String>();
                if (userTerrRecords != null) {
                    for (Object utObj : userTerrRecords) {
                        Map<String, Object> ut = (Map<String, Object>) utObj;
                        userTerritoryIds.add((String) ut.get('Territory2Id'));
                        Map<String, Object> t2 = (Map<String, Object>) ut.get('Territory2');
                        if (t2 != null) userTerritoryNames.add((String) t2.get('Name'));
                    }
                }

                Boolean inTerritory = false;
                List<String> acctTerritoryNames = new List<String>();
                for (Object tObj : terrRecords) {
                    Map<String, Object> t = (Map<String, Object>) tObj;
                    Map<String, Object> t2 = (Map<String, Object>) t.get('Territory2');
                    if (t2 != null) acctTerritoryNames.add((String) t2.get('Name'));
                    if (userTerritoryIds.contains((String) t.get('Territory2Id'))) {
                        inTerritory = true;
                    }
                }

                if (inTerritory) {
                    checks.add(buildCheck('Account in User Territory', 'PASS', 'Account is in user\'s territory'));
                } else {
                    checks.add(buildCheck('Account in User Territory', 'FAIL',
                        'Account territories: ' + String.join(acctTerritoryNames, ', ') +
                        ' | User territories: ' + (userTerritoryNames.isEmpty() ? '(none)' : String.join(userTerritoryNames, ', '))));
                }
            }
        }

        // 8. Check Account Search Preferences (from effective record)
        try {
            String fieldFilter = String.isNotBlank(effectiveRecordId)
                ? 'WHERE LifeScienceMetadataRecordId = \'' + effectiveRecordId + '\' AND FieldName IN (\'EnableCountryBasedSearch\',\'EnableSearchCountrySelector\',\'RestrictToUserAvailableCountry\',\'EnableSearchOutsideTerritory\') '
                : 'WHERE FieldName IN (\'EnableCountryBasedSearch\',\'EnableSearchCountrySelector\',\'RestrictToUserAvailableCountry\',\'EnableSearchOutsideTerritory\') ';
            String prefResponse = restQuery(
                'SELECT Id, FieldName, HasBooleanValue FROM LifeSciMetadataFieldValue ' +
                fieldFilter +
                'ORDER BY FieldName'
            );
            Object parsed = JSON.deserializeUntyped(prefResponse);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> prefResult = (Map<String, Object>) parsed;
                List<Object> prefRecords = (List<Object>) prefResult.get('records');
                if (prefRecords != null) {
                    for (Object pObj : prefRecords) {
                        Map<String, Object> pRec = (Map<String, Object>) pObj;
                        String fieldName = (String) pRec.get('FieldName');
                        Boolean val = (Boolean) pRec.get('HasBooleanValue');
                        String status = val ? 'PASS' : 'INFO';
                        String detail = val ? 'Enabled' : 'Disabled — not enforced';
                        checks.add(buildCheck('Setting: ' + fieldName, status, detail));
                    }
                }
            }
        } catch (Exception e) {
            checks.add(buildCheck('Account Search Preferences', 'WARN', 'Could not query settings: ' + e.getMessage()));
        }

        // 9. Check SearchOutsideTerritoryRecordTypes (only relevant for out-of-territory search)
        if (acct.RecordType != null) {
            try {
                String rtResponse = restQuery(
                    'SELECT Id, FieldName, LongTextValue FROM LifeSciMetadataFieldValue ' +
                    'WHERE FieldName = \'SearchOutsideTerritoryRecordTypes\''
                );
                Object parsed = JSON.deserializeUntyped(rtResponse);
                if (parsed instanceof Map<String, Object>) {
                    Map<String, Object> rtResult = (Map<String, Object>) parsed;
                    List<Object> rtRecords = (List<Object>) rtResult.get('records');
                    if (rtRecords != null && !rtRecords.isEmpty()) {
                        Map<String, Object> rtRec = (Map<String, Object>) rtRecords[0];
                        String allowedRts = (String) rtRec.get('LongTextValue');
                        if (String.isBlank(allowedRts)) {
                            checks.add(buildCheck('Out-of-Territory RecordType Filter', 'INFO',
                                'No record types configured — all types returned in out-of-territory search'));
                        } else if (allowedRts.contains(acct.RecordType.DeveloperName)) {
                            checks.add(buildCheck('Out-of-Territory RecordType Filter', 'PASS',
                                acct.RecordType.DeveloperName + ' is allowed in out-of-territory search'));
                        } else {
                            checks.add(buildCheck('Out-of-Territory RecordType Filter', 'INFO',
                                acct.RecordType.DeveloperName + ' is not in out-of-territory filter (only affects search outside territory). Configured: ' + allowedRts));
                        }
                    }
                }
            } catch (Exception e) {
                checks.add(buildCheck('Out-of-Territory RecordType Filter', 'WARN', 'Could not check: ' + e.getMessage()));
            }
        }

        result.put('checks', checks);
        result.put('accountName', acct.Name);
        result.put('userName', usr.Name);
        result.put('accountCountry', accountCountry);
        result.put('preferredCountry', preferredCountry);
        result.put('availableCountries', userCountries);
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> getVisualizationData(Id userId, Id accountId, String selectedTerritoryId) {
        Map<String, Object> result = new Map<String, Object>();

        // Get account's territory and country
        String cpaResponse = restQuery(
            'SELECT Id, CountryCode FROM ContactPointAddress WHERE ParentId = \'' + accountId + '\' AND IsPrimary = true LIMIT 1'
        );
        String accountCountry = '';
        Object cpaParsed = JSON.deserializeUntyped(cpaResponse);
        if (cpaParsed instanceof Map<String, Object>) {
            List<Object> cpaRecords = (List<Object>) ((Map<String, Object>) cpaParsed).get('records');
            if (cpaRecords != null && !cpaRecords.isEmpty()) {
                accountCountry = (String) ((Map<String, Object>) cpaRecords[0]).get('CountryCode');
            }
        }
        result.put('accountCountry', accountCountry);

        // Get account's territories
        String acctTerrResponse = restQuery(
            'SELECT Id, Territory2Id, Territory2.Name FROM ProviderAcctTerritoryInfo WHERE AccountId = \'' + accountId + '\''
        );
        List<String> accountTerritoryIds = new List<String>();
        List<String> accountTerritoryNames = new List<String>();
        Object acctTerrParsed = JSON.deserializeUntyped(acctTerrResponse);
        if (acctTerrParsed instanceof Map<String, Object>) {
            List<Object> records = (List<Object>) ((Map<String, Object>) acctTerrParsed).get('records');
            if (records != null) {
                for (Object obj : records) {
                    Map<String, Object> rec = (Map<String, Object>) obj;
                    accountTerritoryIds.add((String) rec.get('Territory2Id'));
                    Map<String, Object> t2 = (Map<String, Object>) rec.get('Territory2');
                    if (t2 != null) accountTerritoryNames.add((String) t2.get('Name'));
                }
            }
        }
        result.put('accountTerritoryIds', accountTerritoryIds);
        result.put('accountTerritoryNames', accountTerritoryNames);

        // Get user's preferred country
        String uaiResponse = restQuery(
            'SELECT Id, PreferredCountry, AvailableCountries FROM UserAdditionalInfo WHERE UserId = \'' + userId + '\' LIMIT 1'
        );
        String preferredCountry = '';
        String availableCountries = '';
        Object uaiParsed = JSON.deserializeUntyped(uaiResponse);
        if (uaiParsed instanceof Map<String, Object>) {
            List<Object> records = (List<Object>) ((Map<String, Object>) uaiParsed).get('records');
            if (records != null && !records.isEmpty()) {
                Map<String, Object> uai = (Map<String, Object>) records[0];
                preferredCountry = (String) uai.get('PreferredCountry');
                availableCountries = (String) uai.get('AvailableCountries');
            }
        }
        result.put('preferredCountry', preferredCountry);
        result.put('availableCountries', availableCountries);

        // Get all countries in the org (from ContactPointAddress)
        String countriesResponse = restQuery(
            'SELECT CountryCode, COUNT(Id) cnt FROM ContactPointAddress WHERE CountryCode != null GROUP BY CountryCode ORDER BY CountryCode'
        );
        List<String> orgCountries = new List<String>();
        Object countriesParsed = JSON.deserializeUntyped(countriesResponse);
        if (countriesParsed instanceof Map<String, Object>) {
            List<Object> records = (List<Object>) ((Map<String, Object>) countriesParsed).get('records');
            if (records != null) {
                for (Object obj : records) {
                    Map<String, Object> rec = (Map<String, Object>) obj;
                    String cc = (String) rec.get('CountryCode');
                    if (cc != null) orgCountries.add(cc);
                }
            }
        }
        result.put('orgCountries', orgCountries);

        // Get user's territories
        String userTerrResponse = restQuery(
            'SELECT Id, Territory2Id, Territory2.Name FROM UserTerritory2Association WHERE UserId = \'' + userId + '\''
        );
        List<String> userTerritoryIds = new List<String>();
        List<String> userTerritoryNames = new List<String>();
        Object userTerrParsed = JSON.deserializeUntyped(userTerrResponse);
        if (userTerrParsed instanceof Map<String, Object>) {
            List<Object> records = (List<Object>) ((Map<String, Object>) userTerrParsed).get('records');
            if (records != null) {
                for (Object obj : records) {
                    Map<String, Object> rec = (Map<String, Object>) obj;
                    userTerritoryIds.add((String) rec.get('Territory2Id'));
                    Map<String, Object> t2 = (Map<String, Object>) rec.get('Territory2');
                    if (t2 != null) userTerritoryNames.add((String) t2.get('Name'));
                }
            }
        }
        result.put('userTerritoryIds', userTerritoryIds);
        result.put('userTerritoryNames', userTerritoryNames);

        // Determine zone: inTerritory, inCountry, otherCountry
        String zone = 'otherCountry';
        if (accountTerritoryIds.contains(selectedTerritoryId)) {
            zone = 'inTerritory';
        } else if (String.isNotBlank(preferredCountry) && preferredCountry.equalsIgnoreCase(accountCountry)) {
            zone = 'inCountry';
        } else if (String.isNotBlank(availableCountries) && availableCountries.contains(accountCountry)) {
            zone = 'inAvailableCountries';
        }
        result.put('zone', zone);

        // Get account name
        Account acct = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
        result.put('accountName', acct.Name);

        return result;
    }

    @AuraEnabled
    public static void fixIsPrimaryProvider(Id healthcareProviderId) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String endpoint = baseUrl + '/services/data/v66.0/sobjects/HealthcareProvider/' + healthcareProviderId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody('{"IsPrimaryProvider": true}');

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() >= 400) {
            throw new AuraHandledException('Failed to update: ' + res.getBody());
        }
    }

    private static Map<String, Object> buildCheck(String checkName, String status, String detail) {
        Map<String, Object> check = new Map<String, Object>();
        check.put('name', checkName);
        check.put('status', status);
        check.put('detail', detail);
        return check;
    }
}
