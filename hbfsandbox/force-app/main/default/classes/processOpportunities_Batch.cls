public class processOpportunities_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'receiptsCreate_BatchProcess:';
      
    private String upgradeBatchId;
      
    public processOpportunities_Batch(String upgradeBatchIdVal) {
      upgradeBatchId = upgradeBatchIdVal;
    }
          
    public Database.QueryLocator start(Database.BatchableContext BC) {
      String query = 'SELECT Name, css_frm__Anonymous__c, css_frm__LegacyDonationID__c, css_frm__Data_Migration_Comment__c,'+
        ' css_frm__TributeeCardID__c, css_frm__GroupDonation__c, css_frm__NotEligibleForReceipt__c'+
        ' FROM Opportunity';
      System.debug('query: '+query);
      return Database.getQueryLocator(query);
    }
        
    public void execute(Database.BatchableContext BC, List<Opportunity> opportunityList) {
      String methodName = 'processOpportunities';
         
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Opportunity' LIMIT 1];
    
      try{
        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+opportunityList.size()+ ' record(s)';
  
        for (Opportunity opp : opportunityList) {
          String dataMigrationComment = opp.css_frm__Data_Migration_Comment__c;
          if (dataMigrationComment == null) {dataMigrationComment = '';}
          opp.css_fm2__Anonymous__c = opp.css_frm__Anonymous__c;
          opp.css_fm2__tributeeCardId__c = opp.css_frm__TributeeCardID__c;
          opp.css_fm2__groupDonation__c = opp.css_frm__GroupDonation__c;
          opp.css_fm2__notEligibleForReceipt__c = opp.css_frm__NotEligibleForReceipt__c;
          opp.css_fm2__legacyId__c = opp.css_frm__LegacyDonationID__c;
          opp.css_fm2__dataMigrationComment__c = dataMigrationComment + '\n Updated by cloudStack fM1-to-fM2 Utility '+Date.today();
        }
        update opportunityList;
  
        upgradeBatchRecord.Status__c = 'Pass';
      } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
      }
      update upgradeBatchRecord;
    }
        
    public void finish(Database.BatchableContext BC) {
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Opportunity' LIMIT 1];
      List<Opportunity> opportunityList = [SELECT Name FROM Opportunity];
      upgradeBatchRecord.recordsProcessed__c = opportunityList.size();
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+opportunityList.size()+ ' Opportunity record(s) processed';
      update upgradeBatchRecord;
      fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Opportunity processing complete'); 
    }
  }