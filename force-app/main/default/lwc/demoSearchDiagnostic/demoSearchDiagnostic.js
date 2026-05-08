import { LightningElement } from 'lwc';
import diagnoseSearch from '@salesforce/apex/DemoSearchDiagnosticController.diagnoseSearch';
import getUserTerritories from '@salesforce/apex/DemoSearchDiagnosticController.getUserTerritories';
import fixIsPrimaryProvider from '@salesforce/apex/DemoSearchDiagnosticController.fixIsPrimaryProvider';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STATUS_ICONS = {
    PASS: 'utility:success',
    FAIL: 'utility:error',
    WARN: 'utility:warning',
    INFO: 'utility:info'
};

const STATUS_VARIANTS = {
    PASS: 'success',
    FAIL: 'error',
    WARN: 'warning',
    INFO: 'info'
};

export default class DemoSearchDiagnostic extends LightningElement {
    userId = null;
    accountId = null;
    checks = [];
    isLoading = false;
    hasResults = false;
    accountName = '';
    userName = '';
    territories = [];
    showTerritories = false;

    handleOpenLink(event) {
        const url = event.currentTarget.dataset.url;
        window.open(url, '_blank');
    }

    handleFixPrimaryProvider(event) {
        const hpId = event.currentTarget.dataset.hpid;
        fixIsPrimaryProvider({ healthcareProviderId: hpId })
            .then(() => {
                this.checks = this.checks.map(c => {
                    if (c.fixHpId === hpId) {
                        return { ...c, fixHpDone: true };
                    }
                    return c;
                });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Fixed',
                    message: 'IsPrimaryProvider set to true',
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Could not update',
                    variant: 'error'
                }));
            });
    }

    handleDiagnose() {
        const userPicker = this.template.querySelector('[data-id="userPicker"]');
        const accountPicker = this.template.querySelector('[data-id="accountPicker"]');
        this.userId = userPicker ? userPicker.value : null;
        this.accountId = accountPicker ? accountPicker.value : null;

        if (!this.userId || !this.accountId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Missing Selection',
                message: 'Please select both a User and an Account',
                variant: 'warning'
            }));
            return;
        }

        this.isLoading = true;
        this.checks = [];
        this.hasResults = false;

        // Load territories when user is selected
        getUserTerritories({ userId: this.userId })
            .then(territories => {
                this.territories = territories.map(t => ({
                    label: t.name,
                    value: t.id
                }));
                this.showTerritories = this.territories.length > 0;
                return diagnoseSearch({ userId: this.userId, accountId: this.accountId });
            })
            .then(result => {
                if (result.checks) {
                    this.checks = result.checks.map((check, index) => {
                        let detailText = check.detail || '';
                        let linkId = null;
                        if (detailText.includes('||LINK||')) {
                            const parts = detailText.split('||LINK||');
                            detailText = parts[0];
                            linkId = parts[1];
                        }
                        return {
                            name: check.name,
                            status: check.status,
                            displayDetail: detailText,
                            linkId: linkId,
                            hasLink: !!linkId,
                            linkUrl: linkId ? '/' + linkId : '',
                            fixHpId: check.fixHpId || null,
                            hasFixHp: !!check.fixHpId,
                            fixHpDone: false,
                            key: index,
                            iconName: STATUS_ICONS[check.status] || 'utility:info',
                            iconVariant: STATUS_VARIANTS[check.status] || '',
                            isFail: check.status === 'FAIL',
                            isPass: check.status === 'PASS',
                            isWarn: check.status === 'WARN',
                            isInfo: check.status === 'INFO'
                        };
                    });
                }
                this.accountName = result.accountName || '';
                this.userName = result.userName || '';
                this.hasResults = true;
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Diagnosis failed',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get summaryText() {
        if (!this.hasResults) return '';
        const failCount = this.checks.filter(c => c.status === 'FAIL').length;
        const warnCount = this.checks.filter(c => c.status === 'WARN').length;
        if (failCount === 0 && warnCount === 0) {
            return 'All checks passed — this account should be searchable by this user.';
        }
        let summary = '';
        if (failCount > 0) summary += failCount + ' issue(s) found';
        if (warnCount > 0) summary += (failCount > 0 ? ', ' : '') + warnCount + ' warning(s)';
        return summary;
    }

    get summaryVariant() {
        if (!this.hasResults) return '';
        const failCount = this.checks.filter(c => c.status === 'FAIL').length;
        if (failCount > 0) return 'error';
        const warnCount = this.checks.filter(c => c.status === 'WARN').length;
        if (warnCount > 0) return 'warning';
        return 'success';
    }

    get summaryIconName() {
        const variant = this.summaryVariant;
        if (variant === 'error') return 'utility:error';
        if (variant === 'warning') return 'utility:warning';
        return 'utility:success';
    }
}
