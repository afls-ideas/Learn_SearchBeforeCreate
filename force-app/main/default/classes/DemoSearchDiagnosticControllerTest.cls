@isTest(SeeAllData=true)
private class DemoSearchDiagnosticControllerTest {

    private class MockHttpResponse implements HttpCalloutMock {
        private Map<String, String> responseMap = new Map<String, String>();

        public void addResponse(String urlFragment, String body) {
            responseMap.put(urlFragment, body);
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (req.getMethod() == 'PATCH') {
                res.setStatusCode(204);
                res.setBody('');
                return res;
            }

            String endpoint = req.getEndpoint();
            for (String fragment : responseMap.keySet()) {
                if (endpoint.contains(fragment)) {
                    res.setStatusCode(200);
                    res.setBody(responseMap.get(fragment));
                    return res;
                }
            }

            res.setStatusCode(200);
            res.setBody('{"totalSize":0,"done":true,"records":[]}');
            return res;
        }
    }

    private class FailingPatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"message":"Invalid field"}');
            return res;
        }
    }

    @isTest
    static void testDiagnoseSearch() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        User usr = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        mock.addResponse('HealthcareProvider', '{"totalSize":1,"done":true,"records":[{"Id":"0cmHs000000tN0eIAE","IsPrimaryProvider":true,"Status":"Active","AccountId":"' + acct.Id + '"}]}');
        mock.addResponse('ContactPointAddress', '{"totalSize":1,"done":true,"records":[{"Id":"0a1Hs000000AAAAAA","Street":"123 Main","City":"Paris","StateCode":null,"CountryCode":"FR","IsPrimary":true}]}');
        mock.addResponse('LifeSciMetadataCategory', '{"totalSize":1,"done":true,"records":[{"Id":"0ltHs000000AAAAAA"}]}');
        mock.addResponse('LifeSciMetadataRecord', '{"totalSize":1,"done":true,"records":[{"Id":"0luHs000000AAAAAA","Name":"Default","IsOrgLevel":true,"IsActive":true}]}');
        mock.addResponse('LifeSciMetadataAssignment', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('UserAdditionalInfo', '{"totalSize":1,"done":true,"records":[{"Id":"0PwHs000000AAAAAA","AvailableCountries":"FR;US","PreferredCountry":"FR"}]}');
        mock.addResponse('ProviderAcctTerritoryInfo', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('UserTerritory2Association', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('LifeSciMetadataFieldValue', '{"totalSize":1,"done":true,"records":[{"Id":"0lvHs000000AAAAAA","FieldName":"EnableCountryBasedSearch","HasBooleanValue":true,"LongTextValue":null}]}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchDiagnosticController.diagnoseSearch(usr.Id, acct.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        List<Object> checks = (List<Object>) result.get('checks');
        System.assert(checks.size() > 0, 'Should have diagnostic checks');
        System.assertNotEquals(null, result.get('accountName'));
        System.assertNotEquals(null, result.get('userName'));
    }

    @isTest
    static void testDiagnoseSearchIsPrimaryProviderFail() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        User usr = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        mock.addResponse('HealthcareProvider', '{"totalSize":1,"done":true,"records":[{"Id":"0cmHs000000tN0eIAE","IsPrimaryProvider":false,"Status":"Active","AccountId":"' + acct.Id + '"}]}');
        mock.addResponse('ContactPointAddress', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('LifeSciMetadataCategory', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('UserAdditionalInfo', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('ProviderAcctTerritoryInfo', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('UserTerritory2Association', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('LifeSciMetadataFieldValue', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('LifeSciMetadataAssignment', '{"totalSize":0,"done":true,"records":[]}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchDiagnosticController.diagnoseSearch(usr.Id, acct.Id);
        Test.stopTest();

        List<Object> checks = (List<Object>) result.get('checks');
        Boolean foundHpFail = false;
        for (Object c : checks) {
            Map<String, Object> check = (Map<String, Object>) c;
            if (check.get('name') == 'IsPrimaryProvider' && check.get('status') == 'FAIL') {
                foundHpFail = true;
                System.assertNotEquals(null, check.get('fixHpId'));
            }
        }
        System.assert(foundHpFail, 'Should have IsPrimaryProvider FAIL check with fixHpId');
    }

    @isTest
    static void testDiagnoseSearchInvalidAccount() {
        User usr = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchDiagnosticController.diagnoseSearch(usr.Id, '001000000000000AAA');
        Test.stopTest();

        List<Object> checks = (List<Object>) result.get('checks');
        Boolean foundFail = false;
        for (Object c : checks) {
            Map<String, Object> check = (Map<String, Object>) c;
            if (check.get('name') == 'Account Exists' && check.get('status') == 'FAIL') {
                foundFail = true;
            }
        }
        System.assert(foundFail, 'Should report account not found');
    }

    @isTest
    static void testGetUserTerritories() {
        User usr = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        mock.addResponse('UserTerritory2Association', '{"totalSize":1,"done":true,"records":[{"Id":"07tHs000000AAAAAA","Territory2Id":"0MIHs000000AAAAAA","Territory2":{"Name":"France"}}]}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<Map<String, String>> territories = DemoSearchDiagnosticController.getUserTerritories(usr.Id);
        Test.stopTest();

        System.assertEquals(1, territories.size());
        System.assertEquals('France', territories[0].get('name'));
    }

    @isTest
    static void testFixIsPrimaryProvider() {
        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        DemoSearchDiagnosticController.fixIsPrimaryProvider('0cmHs000000tN0eIAE');
        Test.stopTest();
    }

    @isTest
    static void testFixIsPrimaryProviderError() {
        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        Test.setMock(HttpCalloutMock.class, new FailingPatchMock());

        Test.startTest();
        try {
            DemoSearchDiagnosticController.fixIsPrimaryProvider('0cmHs000000tN0eIAE');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetVisualizationData() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        User usr = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        DemoSearchDiagnosticController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        mock.addResponse('ContactPointAddress', '{"totalSize":1,"done":true,"records":[{"Id":"0a1Hs000000AAAAAA","CountryCode":"FR","IsPrimary":true}]}');
        mock.addResponse('ProviderAcctTerritoryInfo', '{"totalSize":0,"done":true,"records":[]}');
        mock.addResponse('UserAdditionalInfo', '{"totalSize":1,"done":true,"records":[{"Id":"0PwHs000000AAAAAA","PreferredCountry":"FR","AvailableCountries":"FR;US"}]}');
        mock.addResponse('CountryCode', '{"totalSize":2,"done":true,"records":[{"CountryCode":"FR"},{"CountryCode":"US"}]}');
        mock.addResponse('UserTerritory2Association', '{"totalSize":0,"done":true,"records":[]}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchDiagnosticController.getVisualizationData(usr.Id, acct.Id, '0MIHs000000AAAAAA');
        Test.stopTest();

        System.assertNotEquals(null, result.get('zone'));
    }
}
