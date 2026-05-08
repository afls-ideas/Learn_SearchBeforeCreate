@isTest
private class DemoSBCConfigControllerTest {

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

    @isTest
    static void testGetAccountSearchPreferences() {
        DemoSearchBeforeCreateConfigController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        mock.addResponse('LifeSciMetadataCategory', '{"totalSize":1,"done":true,"records":[{"Id":"0ltHs000000AAAAAA","Name":"AccountSearchPreferences","Category":"AccountSearchPreferences"}]}');
        mock.addResponse('LifeSciMetadataRecord', '{"totalSize":1,"done":true,"records":[{"Id":"0luHs000000AAAAAA","Name":"Default","RecordApiName":"Default","IsOrgLevel":true,"IsActive":true}]}');
        mock.addResponse('LifeSciMetadataFieldValue', '{"totalSize":2,"done":true,"records":[{"Id":"0lvHs000000AAAAAA","FieldName":"EnableCountryBasedSearch","DataType":"BOOLEAN","HasBooleanValue":true,"TextValue":null,"PicklistValue":null,"LongTextValue":null,"IntegerValue":null,"NumberValue":null,"FieldValueApiName":"EnableCountryBasedSearch","LifeScienceMetadataRecordId":"0luHs000000AAAAAA"},{"Id":"0lvHs000000BAAAAA","FieldName":"EnableSearchOutsideTerritory","DataType":"BOOLEAN","HasBooleanValue":false,"TextValue":null,"PicklistValue":null,"LongTextValue":null,"IntegerValue":null,"NumberValue":null,"FieldValueApiName":"EnableSearchOutsideTerritory","LifeScienceMetadataRecordId":"0luHs000000AAAAAA"}]}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchBeforeCreateConfigController.getAccountSearchPreferences();
        Test.stopTest();

        System.assertEquals(null, result.get('error'));
        System.assertNotEquals(null, result.get('categoryId'));
        List<Object> records = (List<Object>) result.get('records');
        System.assertEquals(1, records.size());
        List<Object> fields = (List<Object>) result.get('fieldValues');
        System.assertEquals(2, fields.size());
    }

    @isTest
    static void testGetAccountSearchPreferencesNoCategory() {
        DemoSearchBeforeCreateConfigController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchBeforeCreateConfigController.getAccountSearchPreferences();
        Test.stopTest();

        System.assertEquals('AccountSearchPreferences category not found', result.get('error'));
    }

    @isTest
    static void testUpdateBooleanSetting() {
        DemoSearchBeforeCreateConfigController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchBeforeCreateConfigController.updateBooleanSetting('0lvHs000000tN0eIAE', true);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
    }

    @isTest
    static void testUpdatePicklistSetting() {
        DemoSearchBeforeCreateConfigController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchBeforeCreateConfigController.updatePicklistSetting('0lvHs000000tN0eIAE', 'MyCustomers');
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
    }

    @isTest
    static void testUpdateMultipicklistSetting() {
        DemoSearchBeforeCreateConfigController.testSessionId = 'fake-session-id';
        MockHttpResponse mock = new MockHttpResponse();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = DemoSearchBeforeCreateConfigController.updateMultipicklistSetting(
            '0lvHs000000tN0eIAE',
            new List<String>{'Health_Care_Provider', 'Business_Account'}
        );
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
    }

    @isTest
    static void testGetAccountRecordTypes() {
        Test.startTest();
        List<Map<String, String>> recordTypes = DemoSearchBeforeCreateConfigController.getAccountRecordTypes();
        Test.stopTest();

        System.assertNotEquals(null, recordTypes);
    }
}
