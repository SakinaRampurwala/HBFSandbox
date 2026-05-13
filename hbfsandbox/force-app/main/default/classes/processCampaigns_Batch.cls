public class processCampaigns_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'processCampaigns_Batch:';
        
    private String upgradeBatchId;
        
    public processCampaigns_Batch(String upgradeBatchIdVal) {
      upgradeBatchId = upgradeBatchIdVal;
    }
            
    public Database.QueryLocator start(Database.BatchableContext BC) {
      String query = 'SELECT Name, css_frm__Benefit__c, css_fm2__Benefit__c, css_fm2__dataMigrationComment__c FROM Campaign';
      System.debug('query: '+query);
      return Database.getQueryLocator(query);
    }
          
    public void execute(Database.BatchableContext BC, List<Campaign> campaignList) {
      String methodName = 'processCampaigns';

      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Campaign' LIMIT 1];

      try{

        List<Clone_Reference__c> benefitCloneList = [SELECT Benefit_fM1__c, Benefit_fM2__c FROM Clone_Reference__c WHERE UpgradeBatchRecord__c =: upgradeBatchRecord.Id];
        Map<Id,Id> fM1tofM2_benefitMap = new Map<Id,Id> ();
        for (Clone_Reference__c cloneReference : benefitCloneList) { fM1tofM2_benefitMap.put(cloneReference.Benefit_fM1__c, cloneReference.Benefit_fM2__c); }

        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+campaignList.size()+ ' record(s)';
  
        for (Campaign camp : campaignList) {
            String dataMigrationComment = camp.css_fm2__dataMigrationComment__c;
            if (dataMigrationComment == null) {dataMigrationComment = '';}  
            camp.css_fm2__Benefit__c = fM1tofM2_benefitMap.get(camp.css_frm__Benefit__c);
            camp.css_fm2__dataMigrationComment__c = dataMigrationComment + '\n Updated by cloudStack fM1-to-fM2 Utility '+Date.today();
        }
        update campaignList;
  
        upgradeBatchRecord.Status__c = 'Pass';
      } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
      }
      update upgradeBatchRecord;
    }
          
    public void finish(Database.BatchableContext BC) {
        UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Campaign' LIMIT 1];
        List<Campaign> campaignList = [SELECT Name FROM Campaign];
        upgradeBatchRecord.recordsProcessed__c = campaignList.size();
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+campaignList.size()+ ' Benefit record(s) processed';
        update upgradeBatchRecord;
      fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Campaign processing complete'); 
    }
  }