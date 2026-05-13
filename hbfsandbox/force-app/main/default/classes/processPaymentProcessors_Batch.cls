public class processPaymentProcessors_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'processPaymentProcessors_Batch:';
        
    private String upgradeBatchId;
        
    public processPaymentProcessors_Batch(String upgradeBatchIdVal) {
        upgradeBatchId = upgradeBatchIdVal;
    }
            
    public Database.QueryLocator start(Database.BatchableContext BC) {
        String query = 'SELECT Name, css_frm__AccountCurrency__c, css_frm__isActive__c, css_frm__StripePublishableKey__c, css_frm__StripeRestrictedKey__c, css_frm__StripeAccountConfigured__c, css_frm__StripeAccountType__c FROM css_frm__PaymentProcessor__c';
        System.debug('query: '+query);
        return Database.getQueryLocator(query);
    }
        
    public void execute(Database.BatchableContext BC, List<css_frm__PaymentProcessor__c> paymentProcessorList) {
        String methodName = 'processPaymentProcessors';
            
        UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Payment Processor' LIMIT 1];

        try{
        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+paymentProcessorList.size()+ ' record(s)';

        List<css_fm2__PaymentProcessor__c> new_fM2_PaymentProcessors = new List<css_fm2__PaymentProcessor__c>();
        for (css_frm__PaymentProcessor__c fM1_PaymentProcessor : paymentProcessorList) {
            css_fm2__PaymentProcessor__c fM2_PaymentProcessor = new css_fm2__PaymentProcessor__c();
            fM2_PaymentProcessor.Name                                   = fM1_PaymentProcessor.Name;
            fM2_PaymentProcessor.css_fm2__AccountCurrency__c            = fM1_PaymentProcessor.css_frm__AccountCurrency__c;
            fM2_PaymentProcessor.css_fm2__isActive__c                   = fM1_PaymentProcessor.css_frm__isActive__c;
            fM2_PaymentProcessor.css_fm2__StripePublishableKey__c       = fM1_PaymentProcessor.css_frm__StripePublishableKey__c;
            fM2_PaymentProcessor.css_fm2__StripeRestrictedKey__c        = fM1_PaymentProcessor.css_frm__StripeRestrictedKey__c;
            fM2_PaymentProcessor.css_fm2__StripeAccountConfigured__c    = fM1_PaymentProcessor.css_frm__StripeAccountConfigured__c;
            fM2_PaymentProcessor.css_fm2__legacyId__c                   = fM1_PaymentProcessor.Id;
            fM2_PaymentProcessor.css_fm2__dataMigrationComment__c       = 'Created by cloudStack fM1-to-fM2 Utility '+Date.today();
            new_fM2_PaymentProcessors.add(fM2_PaymentProcessor);
        }
        insert new_fM2_PaymentProcessors;

        upgradeBatchRecord.Status__c = 'Pass';
        } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
        }
        update upgradeBatchRecord;
    }
        
    public void finish(Database.BatchableContext BC) {
        UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Payment Processor' LIMIT 1];

        List<Clone_Reference__c> cloneRecordList = new List<Clone_Reference__c>();
        List<css_fm2__PaymentProcessor__c> new_fM2_PaymentProcessors = [SELECT Name, css_fm2__legacyId__c FROM css_fm2__PaymentProcessor__c];

        for (css_fm2__PaymentProcessor__c paymentProcessor : new_fM2_PaymentProcessors) {
            Clone_Reference__c cloneReference = new Clone_Reference__c();
            cloneReference.UpgradeBatchRecord__c = upgradeBatchRecord.Id;
            cloneReference.paymentProcessor_fM1__c = paymentProcessor.css_fm2__legacyId__c;
            cloneReference.paymentProcessor_fM2__c = paymentProcessor.Id;
            cloneRecordList.add(cloneReference);
          }
        insert cloneRecordList;

        List<css_frm__PaymentProcessor__c> paymentProcessorList = [SELECT Name FROM css_frm__PaymentProcessor__c];
        upgradeBatchRecord.recordsProcessed__c = paymentProcessorList.size();
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+paymentProcessorList.size()+ ' Payment Processor record(s) processed';
        update upgradeBatchRecord;
        fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Payment Processor processing complete'); 
    }
    }