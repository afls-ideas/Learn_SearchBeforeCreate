public with sharing class SearchBeforeCreateConfigController {

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

    private static String restUpdate(String objectName, String recordId, String body) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String endpoint = baseUrl + '/services/data/v66.0/sobjects/' + objectName + '/' + recordId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);
        return res.getStatusCode() < 300 ? 'OK' : res.getBody();
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAccountSearchPreferences() {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Step 1: Get the category
            String catResponse = restQuery(
                'SELECT Id, Name, Category FROM LifeSciMetadataCategory WHERE Category = \'AccountSearchPreferences\' LIMIT 1'
            );

            Object parsed = JSON.deserializeUntyped(catResponse);
            if (parsed instanceof List<Object>) {
                // Error response from Tooling API
                List<Object> errors = (List<Object>) parsed;
                Map<String, Object> err = (Map<String, Object>) errors[0];
                result.put('error', 'Tooling API error: ' + (String) err.get('message'));
                result.put('rawResponse', catResponse);
                return result;
            }

            Map<String, Object> catResult = (Map<String, Object>) parsed;
            List<Object> catRecords = (List<Object>) catResult.get('records');

            if (catRecords == null || catRecords.isEmpty()) {
                result.put('error', 'AccountSearchPreferences category not found');
                return result;
            }

            Map<String, Object> category = (Map<String, Object>) catRecords[0];
            String categoryId = (String) category.get('Id');
            result.put('categoryId', categoryId);

            // Step 2: Get config records
            String recResponse = restQuery(
                'SELECT Id, Name, RecordApiName, IsOrgLevel, IsActive FROM LifeSciMetadataRecord WHERE LifeScienceMetadataCategoryId = \'' + categoryId + '\''
            );
            Map<String, Object> recResult = (Map<String, Object>) JSON.deserializeUntyped(recResponse);
            List<Object> recRecords = (List<Object>) recResult.get('records');

            List<Map<String, Object>> configRecords = new List<Map<String, Object>>();
            List<String> recordIds = new List<String>();

            if (recRecords != null) {
                for (Object rec : recRecords) {
                    Map<String, Object> recMap = (Map<String, Object>) rec;
                    Map<String, Object> cleanRec = new Map<String, Object>();
                    cleanRec.put('id', recMap.get('Id'));
                    cleanRec.put('name', recMap.get('Name'));
                    cleanRec.put('recordApiName', recMap.get('RecordApiName'));
                    cleanRec.put('isOrgLevel', recMap.get('IsOrgLevel'));
                    cleanRec.put('isActive', recMap.get('IsActive'));
                    configRecords.add(cleanRec);
                    recordIds.add((String) recMap.get('Id'));
                }
            }

            result.put('records', configRecords);

            // Step 3: Get field values for all records
            if (!recordIds.isEmpty()) {
                String idList = '\'' + String.join(recordIds, '\',\'') + '\'';
                String fvResponse = restQuery(
                    'SELECT Id, Name, FieldName, HasBooleanValue, TextValue, PicklistValue, ' +
                    'LongTextValue, IntegerValue, NumberValue, DataType, ' +
                    'FieldValueApiName, LifeScienceMetadataRecordId ' +
                    'FROM LifeSciMetadataFieldValue ' +
                    'WHERE LifeScienceMetadataRecordId IN (' + idList + ') ' +
                    'ORDER BY FieldName'
                );
                Map<String, Object> fvResult = (Map<String, Object>) JSON.deserializeUntyped(fvResponse);
                List<Object> fvRecords = (List<Object>) fvResult.get('records');

                List<Map<String, Object>> fields = new List<Map<String, Object>>();
                if (fvRecords != null) {
                    for (Object fvObj : fvRecords) {
                        Map<String, Object> fv = (Map<String, Object>) fvObj;
                        Map<String, Object> fieldMap = new Map<String, Object>();
                        fieldMap.put('id', fv.get('Id'));
                        fieldMap.put('fieldName', fv.get('FieldName'));
                        fieldMap.put('dataType', fv.get('DataType'));
                        fieldMap.put('booleanValue', fv.get('HasBooleanValue'));
                        fieldMap.put('textValue', fv.get('TextValue'));
                        fieldMap.put('picklistValue', fv.get('PicklistValue'));
                        fieldMap.put('longTextValue', fv.get('LongTextValue'));
                        fieldMap.put('integerValue', fv.get('IntegerValue'));
                        fieldMap.put('numberValue', fv.get('NumberValue'));
                        fieldMap.put('recordId', fv.get('LifeScienceMetadataRecordId'));
                        fields.add(fieldMap);
                    }
                }
                result.put('fieldValues', fields);
            }
        } catch (Exception e) {
            result.put('error', e.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static Map<String, Object> updateBooleanSetting(Id fieldValueId, Boolean newValue) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            String body = JSON.serialize(new Map<String, Object>{ 'HasBooleanValue' => newValue });
            String response = restUpdate('LifeSciMetadataFieldValue', fieldValueId, body);
            if (response == 'OK') {
                result.put('success', true);
                result.put('newValue', newValue);
            } else {
                result.put('success', false);
                result.put('error', response);
            }
        } catch (Exception e) {
            result.put('success', false);
            result.put('error', e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> updatePicklistSetting(Id fieldValueId, String newValue) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            String body = JSON.serialize(new Map<String, Object>{ 'PicklistValue' => newValue });
            String response = restUpdate('LifeSciMetadataFieldValue', fieldValueId, body);
            if (response == 'OK') {
                result.put('success', true);
                result.put('newValue', newValue);
            } else {
                result.put('success', false);
                result.put('error', response);
            }
        } catch (Exception e) {
            result.put('success', false);
            result.put('error', e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> updateMultipicklistSetting(Id fieldValueId, List<String> selectedValues) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            String joinedValue = String.join(selectedValues, ';');
            String body = JSON.serialize(new Map<String, Object>{ 'LongTextValue' => joinedValue });
            String response = restUpdate('LifeSciMetadataFieldValue', fieldValueId, body);
            if (response == 'OK') {
                result.put('success', true);
                result.put('newValue', joinedValue);
            } else {
                result.put('success', false);
                result.put('error', response);
            }
        } catch (Exception e) {
            result.put('success', false);
            result.put('error', e.getMessage());
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAccountRecordTypes() {
        List<Map<String, String>> recordTypes = new List<Map<String, String>>();
        for (RecordType rt : [
            SELECT Id, Name, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsActive = true
            ORDER BY Name
        ]) {
            Map<String, String> rtMap = new Map<String, String>();
            rtMap.put('value', rt.DeveloperName);
            rtMap.put('label', rt.Name);
            recordTypes.add(rtMap);
        }
        return recordTypes;
    }
}
