import { LightningElement, wire, track } from 'lwc';
import getAccountSearchPreferences from '@salesforce/apex/DemoSearchBeforeCreateConfigController.getAccountSearchPreferences';
import getAccountRecordTypes from '@salesforce/apex/DemoSearchBeforeCreateConfigController.getAccountRecordTypes';
import updateBooleanSetting from '@salesforce/apex/DemoSearchBeforeCreateConfigController.updateBooleanSetting';
import updatePicklistSetting from '@salesforce/apex/DemoSearchBeforeCreateConfigController.updatePicklistSetting';
import updateMultipicklistSetting from '@salesforce/apex/DemoSearchBeforeCreateConfigController.updateMultipicklistSetting';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const FIELD_LABELS = {
    EnableSearchOutsideTerritory: 'Enable users to search for accounts outside the user\'s territory',
    OnlyActiveAccountsInOutOfTerrSearch: 'Show only active accounts in out-of-territory search',
    EnableSearchCountrySelector: 'Add the country filter to the search',
    EnableCountryBasedSearch: 'Enable country-specific search',
    RestrictToUserAvailableCountry: 'Restrict search to countries available to the user',
    AccountIdentifierSearch: 'Enable users to search business licenses',
    EnableMaps: 'Show accounts in a map view',
    AccountsSearchAlignHardAffiliations: 'Auto-align affiliated accounts after primary account alignment',
    SearchOutsideTerritoryRecordTypes: 'Search Outside Territory Record Types',
    AccountRecordTypeAPIName: 'Default Account Type Filters',
    CustomerFilterByDefault: 'Default Customer Filter',
    AdditionalPrvdAcctTerrAccountSearchField: 'Additional Provider Territory Search Field'
};

const FIELD_SECTIONS = {
    searchOutsideTerritory: [
        'EnableSearchOutsideTerritory',
        'OnlyActiveAccountsInOutOfTerrSearch',
        'EnableSearchCountrySelector',
        'EnableCountryBasedSearch'
    ],
    searchOutsideTerritoryRecordTypes: [
        'SearchOutsideTerritoryRecordTypes'
    ],
    advancedSearch: [
        'RestrictToUserAvailableCountry',
        'AccountIdentifierSearch'
    ],
    additionalPreferences: [
        'EnableMaps',
        'AccountsSearchAlignHardAffiliations',
        'CustomerFilterByDefault',
        'AdditionalPrvdAcctTerrAccountSearchField',
        'AccountRecordTypeAPIName'
    ]
};

export default class SearchBeforeCreateConfig extends LightningElement {
    @track settings = {};
    @track fieldValues = [];
    @track recordTypes = [];
    @track isLoading = true;
    @track error;
    @track pendingChanges = [];

    _wiredPreferences;
    _wiredRecordTypes;

    @wire(getAccountSearchPreferences)
    wiredPreferences(result) {
        this._wiredPreferences = result;
        if (result.data) {
            this.processPreferences(result.data);
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error.body?.message || 'Error loading preferences';
            this.isLoading = false;
        }
    }

    @wire(getAccountRecordTypes)
    wiredRecordTypes(result) {
        this._wiredRecordTypes = result;
        if (result.data) {
            this.recordTypes = result.data;
        }
    }

    processPreferences(data) {
        if (data.error) {
            this.error = data.error;
            return;
        }

        const fieldMap = {};
        if (data.fieldValues) {
            data.fieldValues.forEach(fv => {
                fieldMap[fv.fieldName] = fv;
            });
        }
        this.settings = fieldMap;
        this.fieldValues = data.fieldValues || [];
    }

    get searchOutsideTerritoryFields() {
        return this.getFieldsForSection('searchOutsideTerritory');
    }

    get advancedSearchFields() {
        return this.getFieldsForSection('advancedSearch');
    }

    get additionalPreferencesFields() {
        return this.getFieldsForSection('additionalPreferences');
    }

    get territoryRecordTypeField() {
        return this.settings['SearchOutsideTerritoryRecordTypes'] || null;
    }

    get accountRecordTypeField() {
        return this.settings['AccountRecordTypeAPIName'] || null;
    }

    get selectedTerritoryRecordTypes() {
        const field = this.territoryRecordTypeField;
        if (!field || !field.longTextValue) return [];
        return field.longTextValue.split(';').filter(v => v);
    }

    get selectedAccountRecordTypes() {
        const field = this.accountRecordTypeField;
        if (!field || !field.longTextValue) return [];
        return field.longTextValue.split(';').filter(v => v);
    }

    get availableRecordTypeOptions() {
        return this.recordTypes.map(rt => ({
            label: rt.label,
            value: rt.value
        }));
    }

    get hasPendingChanges() {
        return this.pendingChanges.length > 0;
    }

    getFieldsForSection(section) {
        const fieldNames = FIELD_SECTIONS[section] || [];
        return fieldNames
            .filter(name => this.settings[name])
            .map(name => {
                const fv = this.settings[name];
                return {
                    ...fv,
                    label: FIELD_LABELS[name] || name,
                    isBoolean: fv.dataType === 'BOOLEAN',
                    isPicklist: fv.dataType === 'PICKLIST',
                    isMultipicklist: fv.dataType === 'MULTIPICKLIST',
                    checked: fv.booleanValue
                };
            });
    }

    handleToggleChange(event) {
        const fieldValueId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        const newValue = event.target.checked;

        this.isLoading = true;
        updateBooleanSetting({ fieldValueId, newValue })
            .then(result => {
                if (result.success) {
                    this.showToast('Success', `${FIELD_LABELS[fieldName] || fieldName} updated`, 'success');
                    return refreshApex(this._wiredPreferences);
                } else {
                    this.showToast('Error', result.error, 'error');
                    event.target.checked = !newValue;
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Update failed', 'error');
                event.target.checked = !newValue;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handlePicklistChange(event) {
        const fieldValueId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        const newValue = event.detail.value;

        this.isLoading = true;
        updatePicklistSetting({ fieldValueId, newValue })
            .then(result => {
                if (result.success) {
                    this.showToast('Success', `${FIELD_LABELS[fieldName] || fieldName} updated`, 'success');
                    return refreshApex(this._wiredPreferences);
                } else {
                    this.showToast('Error', result.error, 'error');
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Update failed', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleMultipicklistChange(event) {
        const fieldValueId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        const selectedValues = event.detail.value;

        this.isLoading = true;
        updateMultipicklistSetting({ fieldValueId, selectedValues })
            .then(result => {
                if (result.success) {
                    this.showToast('Success', `${FIELD_LABELS[fieldName] || fieldName} updated`, 'success');
                    return refreshApex(this._wiredPreferences);
                } else {
                    this.showToast('Error', result.error, 'error');
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Update failed', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredPreferences)
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
