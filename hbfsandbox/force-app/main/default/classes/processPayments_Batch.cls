public class processPayments_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'processPayments_Batch:';
      
    private String upgradeBatchId;
      
    public processPayments_Batch(String upgradeBatchIdVal) {
      upgradeBatchId = upgradeBatchIdVal;
    }
          
    public Database.QueryLocator start(Database.BatchableContext BC) {
      String query = 'SELECT Name, css_frm__LegacyPaymentID__c, css_frm__transactionFees__c, css_frm__DataMigrationComment__c FROM npe01__OppPayment__c';
      System.debug('query: '+query);
      return Database.getQueryLocator(query);
    }
        
    public void execute(Database.BatchableContext BC, List<npe01__OppPayment__c> paymentList) {
      String methodName = 'processPayments';
         
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Payment' LIMIT 1];
    
      try{
        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+paymentList.size()+ ' record(s)';
  
        for (npe01__OppPayment__c pmt : paymentList) {
          String dataMigrationComment = pmt.css_frm__DataMigrationComment__c;
          if (dataMigrationComment == null) {dataMigrationComment = '';}
          pmt.RecordTypeId = Schema.Sobjecttype.npe01__OppPayment__c.getRecordTypeInfosByName().get('Generic Payment').getRecordTypeId();
          pmt.css_fm2__transactionFees__c = pmt.css_frm__transactionFees__c;
          pmt.css_fm2__legacyId__c = pmt.css_frm__LegacyPaymentID__c;
          pmt.css_fm2__dataMigrationComment__c = dataMigrationComment + '\n Updated by cloudStack fM1-to-fM2 Utility '+Date.today();
        }
        update paymentList;
  
        upgradeBatchRecord.Status__c = 'Pass';
      } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
      }
      update upgradeBatchRecord;
    }
        
    public void finish(Database.BatchableContext BC) {
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Payment' LIMIT 1];
      List<npe01__OppPayment__c> paymentList = [SELECT Name FROM npe01__OppPayment__c];
      upgradeBatchRecord.recordsProcessed__c = paymentList.size();
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+paymentList.size()+ ' Payment record(s) processed';
      update upgradeBatchRecord;
      fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Payment processing complete'); 
    }
  }