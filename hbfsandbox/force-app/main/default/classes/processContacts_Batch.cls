public class processContacts_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
  static final String className = 'processContacts_Batch:';
    
  private String upgradeBatchId;
    
  public processContacts_Batch(String upgradeBatchIdVal) {
    upgradeBatchId = upgradeBatchIdVal;
  }
        
  public Database.QueryLocator start(Database.BatchableContext BC) {
    String query = 'SELECT Name, FirstName, LastName,'+ 
      'css_frm__Anonymous__c, css_frm__NewsletterOptIn__c, css_frm__CorrespondenceLanguagePreference__c, css_frm__LegacyContactID__c, css_frm__DataMigrationComment__c,'+
      'css_fm2__Anonymous__c, css_fm2__newsletterOptIn__c, css_fm2__correspondenceLanguagePreference__c, css_fm2__legacyId__c, css_fm2__dataMigrationComment__c'+
      ' FROM Contact';
    System.debug('query: '+query);
    return Database.getQueryLocator(query);
  }
      
  public void execute(Database.BatchableContext BC, List<Contact> contactList) {
    String methodName = 'processContacts';
       
    UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Contact' LIMIT 1];
  
    try{
      if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+contactList.size()+ ' record(s)';

      for (Contact con : contactList) {
        String dataMigrationComment = con.css_frm__DataMigrationComment__c;
        if (dataMigrationComment == null) {dataMigrationComment = '';}
        con.css_fm2__Anonymous__c = con.css_frm__Anonymous__c;
        con.css_fm2__newsletterOptIn__c = con.css_frm__NewsletterOptIn__c;
        con.css_fm2__correspondenceLanguagePreference__c = con.css_frm__CorrespondenceLanguagePreference__c;
        con.css_fm2__legacyId__c = con.css_frm__LegacyContactID__c;
        con.css_fm2__dataMigrationComment__c = dataMigrationComment + '\n Updated by cloudStack fM1-to-fM2 Utility '+Date.today();
      }
      update contactList;

      upgradeBatchRecord.Status__c = 'Pass';
    } catch ( Exception e) {
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
      upgradeBatchRecord.Status__c = 'Fail';
    }
    update upgradeBatchRecord;
  }
      
  public void finish(Database.BatchableContext BC) {
    UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Contact' LIMIT 1];
    List<Contact> contactList = [SELECT Name FROM Contact];
    upgradeBatchRecord.recordsProcessed__c = contactList.size();
    upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+contactList.size()+ ' Contact record(s) processed';
    update upgradeBatchRecord;
    fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Contact processing complete'); 
  }
}