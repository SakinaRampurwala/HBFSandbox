public class processTransactions_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'processTransactions_Batch:';
      
    private String upgradeBatchId;
      
    public processTransactions_Batch(String upgradeBatchIdVal) {
      upgradeBatchId = upgradeBatchIdVal;
    }
          
    public Database.QueryLocator start(Database.BatchableContext BC) {
      String query = 'SELECT Name, css_frm__Amount__c, css_frm__CreditCardType__c, css_frm__CreditCardExpiryDate__c, css_frm__CreditCardLastFourDigits__c, css_frm__Packet__c,'+
      'css_frm__Payment__c, css_frm__Payment__r.npe01__Opportunity__c, css_frm__PaymentDate__c, RecordTypeId, css_frm__RecurringDonationId__c, css_frm__Status__c, css_frm__StripeChargeId__c, css_frm__StripeChargeStatus__c,'+
      'css_frm__StripeInvoiceId__c, css_frm__StripeSubscriptionId__c, css_frm__TransactionFees__c, CreatedDate'+
      ' FROM css_frm__Transaction__c';
      System.debug('query: '+query);
      return Database.getQueryLocator(query);
    }
        
    public void execute(Database.BatchableContext BC, List<css_frm__Transaction__c> transactionList) {
      String methodName = 'processTransactions';
         
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Transaction' LIMIT 1];

      try{
        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+transactionList.size()+ ' record(s)';

        List<css_fm2__Transaction__c> new_fM2_Transactions = new List<css_fm2__Transaction__c>();
        for (css_frm__Transaction__c fM1_Transaction : transactionList) {
            css_fm2__Transaction__c fM2_Transaction = new css_fm2__Transaction__c();
            fM2_Transaction.Name                                    = fM1_Transaction.Name;

            fM2_Transaction.css_fm2__Amount__c                       = fM1_Transaction.css_frm__Amount__c;
            fM2_Transaction.css_fm2__creditCardExpiryDate__c         = fM1_Transaction.css_frm__CreditCardExpiryDate__c;
            fM2_Transaction.css_fm2__creditCardLastFourDigits__c     = fM1_Transaction.css_frm__CreditCardLastFourDigits__c;
            fM2_Transaction.css_fm2__creditCardType__c               = fM1_Transaction.css_frm__CreditCardType__c;
            fM2_Transaction.css_fm2__Date__c                         = fM1_Transaction.CreatedDate;
            fM2_Transaction.css_fm2__Opportunity__c                  = fM1_Transaction.css_frm__Payment__r.npe01__Opportunity__c;
            fM2_Transaction.css_fm2__Packet__c                       = fM1_Transaction.css_frm__Packet__c;
            fM2_Transaction.css_fm2__Payment__c                      = fM1_Transaction.css_frm__Payment__c;
            fM2_Transaction.css_fm2__methodOfPayment__c              = 'Credit Card';
            Id StripeTransactionRecordTypeId = Schema.Sobjecttype.css_fm2__Transaction__c.getRecordTypeInfosByName().get('Stripe Transaction').getRecordTypeId();
            fM2_Transaction.RecordTypeId                             = StripeTransactionRecordTypeId;
            fM2_Transaction.css_fm2__recurringDonation__c            = fM1_Transaction.css_frm__RecurringDonationId__c;
            fM2_Transaction.css_fm2__Status__c                       = fM1_Transaction.css_frm__Status__c;
            fM2_Transaction.css_fm2__stripeChargeId__c               = fM1_Transaction.css_frm__StripeChargeId__c;
            fM2_Transaction.css_fm2__stripeChargeStatus__c           = fM1_Transaction.css_frm__StripeChargeStatus__c;
            fM2_Transaction.css_fm2__stripeInvoiceId__c              = fM1_Transaction.css_frm__StripeInvoiceId__c;
            fM2_Transaction.css_fm2__stripeSubscriptionId__c         = fM1_Transaction.css_frm__StripeSubscriptionId__c;
            fM2_Transaction.css_fm2__transactionFees__c              = fM1_Transaction.css_frm__TransactionFees__c;

            fM2_Transaction.css_fm2__legacyId__c                    = fM1_Transaction.Id;
            fM2_Transaction.css_fm2__dataMigrationComment__c        = 'Created by cloudStack fM1-to-fM2 Utility '+Date.today();
            new_fM2_Transactions.add(fM2_Transaction);
        }
        insert new_fM2_Transactions;

        upgradeBatchRecord.Status__c = 'Pass';
      } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
      }
      update upgradeBatchRecord;
    }
        
    public void finish(Database.BatchableContext BC) {

      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Transaction' LIMIT 1];

      List<Clone_Reference__c> cloneRecordList = new List<Clone_Reference__c>();
      List<css_fm2__Transaction__c> new_fM2_Transactions = [SELECT Name, Id, css_fm2__legacyId__c FROM css_fm2__Transaction__c];
      for (css_fm2__Transaction__c newTransaction : new_fM2_Transactions) {
        Clone_Reference__c cloneReference = new Clone_Reference__c();
        cloneReference.UpgradeBatchRecord__c = upgradeBatchRecord.Id;
        cloneReference.Transaction_fM1__c = newTransaction.css_fm2__legacyId__c;
        cloneReference.Transaction_fM2__c = newTransaction.Id;
        cloneRecordList.add(cloneReference);
      }
      insert cloneRecordList;

      List<css_frm__Transaction__c> transactionList = [SELECT Name FROM css_frm__Transaction__c];
      upgradeBatchRecord.recordsProcessed__c = transactionList.size();
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+transactionList.size()+ ' Transaction record(s) processed';
      update upgradeBatchRecord;
      fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Transaction processing complete'); 
    }
  }