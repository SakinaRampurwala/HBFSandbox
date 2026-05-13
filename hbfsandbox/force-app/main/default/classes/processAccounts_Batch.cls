public class processAccounts_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
  static final String className = 'processAccounts_Batch:';
      
  private String upgradeBatchId;
      
  public processAccounts_Batch(String upgradeBatchIdVal) {
    upgradeBatchId = upgradeBatchIdVal;
  }
          
  public Database.QueryLocator start(Database.BatchableContext BC) {
    String query = 'SELECT Name,'+
      'css_frm__Anonymous__c, css_frm__LegacyAccountID__c, css_frm__DataMigrationComment__c,'+
      'css_fm2__Anonymous__c, css_fm2__legacyId__c, css_fm2__dataMigrationComment__c'+
      ' FROM Account';
    System.debug('query: '+query);
    return Database.getQueryLocator(query);
  }
        
  public void execute(Database.BatchableContext BC, List<Account> accountList) {
    String methodName = 'processAccounts';
        
    UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Account' LIMIT 1];

    try{
      if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+accountList.size()+ ' record(s)';

      for (Account acc : accountList) {
        String dataMigrationComment = acc.css_frm__DataMigrationComment__c;
        if (dataMigrationComment == null) {dataMigrationComment = '';}  
        acc.css_fm2__Anonymous__c = acc.css_frm__Anonymous__c;
        acc.css_fm2__legacyId__c = acc.css_frm__LegacyAccountID__c;
        acc.css_fm2__dataMigrationComment__c = dataMigrationComment + '\n Updated by cloudStack fM1-to-fM2 Utility '+Date.today();
      }
      update accountList;

      upgradeBatchRecord.Status__c = 'Pass';
    } catch ( Exception e) {
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
      upgradeBatchRecord.Status__c = 'Fail';
    }
    update upgradeBatchRecord;
  }
        
  public void finish(Database.BatchableContext BC) {
    UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Account' LIMIT 1];
    List<Account> accountList = [SELECT Name FROM Account];
    upgradeBatchRecord.recordsProcessed__c = accountList.size();
    upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+accountList.size()+ ' Account record(s) processed';
    update upgradeBatchRecord;
    fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Account processing complete'); 
  }
}