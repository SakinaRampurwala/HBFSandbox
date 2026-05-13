import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

import getInitialState from '@salesforce/apex/PurchaseOrderPreviewEmailCtrl.getInitialState';

export default class PurchaseOrderPreviewEmail extends LightningElement {
    @track bodyTemplateQuery = '';
    @track attachmentTemplateQuery = '';
    @track defaultSelectedContact = [];
    @track message = '';

    objApiName = 'buildertek__Purchase_Order__c';
    fileName = 'Purchase Order Form';
    includeRefId = false;
    headerTitle = 'Purchase Order Preview and Email';
    showFileUpload = false;
    isBodyRequired = true;
    showSignaturePad = false;
    showAcceptButtons = false;
    defaultFromAddress = '';
    defaultToAddress = '';
    defaultEmailTemplate = '';
    emailSubject = '';
    overrideSubjectWithTemplateSubject = true;
    signedPdfName = 'Purchase Order Form.pdf';
    deleteSignatureAfterSave = false;

    isLoading = true;
    isBlocked = false;
    showEmailComposer = false;

    _recordId;
    loadedRecordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value && value !== this.loadedRecordId) {
            this.loadInitialState();
        }
    }

    connectedCallback() {
        if (this.recordId && this.recordId !== this.loadedRecordId) {
            this.loadInitialState();
        }
    }

    loadInitialState() {
        this.isLoading = true;
        this.isBlocked = false;
        this.showEmailComposer = false;
        this.message = '';
        this.loadedRecordId = this.recordId;

        getInitialState({ purchaseOrderId: this.recordId })
            .then((state) => {
                this.defaultSelectedContact = state.defaultSelectedContact || [];
                this.defaultFromAddress = state.defaultFromAddress || '';
                this.defaultToAddress = state.defaultToAddress || '';
                this.defaultEmailTemplate = state.defaultEmailTemplate || '';
                this.emailSubject = state.defaultSubject || '';
                this.bodyTemplateQuery = state.bodyTemplateQuery || '';
                this.attachmentTemplateQuery = state.attachmentTemplateQuery || '';
                this.signedPdfName = state.signedPdfName || this.signedPdfName;
                this.fileName = state.purchaseOrderName || this.fileName;

                if (state.configurationError) {
                    this.isBlocked = true;
                    this.message = state.configurationError;
                    return;
                }

                this.showEmailComposer = true;
            })
            .catch((error) => {
                this.isBlocked = true;
                this.message = this.extractErrorMessage(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSubmit() {
        getRecordNotifyChange([{ recordId: this.recordId }]);
        this.handleClose();
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    extractErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            const errorMessage = error.body.map((entry) => entry.message).join(', ');
            return errorMessage;
        }
        const fallbackMessage = error?.message || 'Unable to load Purchase Order Preview and Email.';
        return fallbackMessage;
    }
}
