public class processBenefits_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'processBenefits_Batch:';
      
    private String upgradeBatchId;
      
    public processBenefits_Batch(String upgradeBatchIdVal) {
      upgradeBatchId = upgradeBatchIdVal;
    }
          
    public Database.QueryLocator start(Database.BatchableContext BC) {
      String query = 'SELECT Name, css_frm__AdvantagePercentage__c, css_frm__AdvantageAmount__c, css_frm__Advantage_isCash__c, css_frm__AdvantageDescription__c, css_frm__Advantage_isObject__c FROM css_frm__Benefit__c';
      System.debug('query: '+query);
      return Database.getQueryLocator(query);
    }
        
    public void execute(Database.BatchableContext BC, List<css_frm__Benefit__c> benefitList) {
      String methodName = 'processBenefits';
         
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Benefit' LIMIT 1];

      try{
        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+benefitList.size()+ ' record(s)';

        List<css_fm2__Benefit__c> new_fM2_Benefits = new List<css_fm2__Benefit__c>();
        for (css_frm__Benefit__c fM1_Benefit : benefitList) {
            css_fm2__Benefit__c fM2_Benefit = new css_fm2__Benefit__c();
            fM2_Benefit.Name                              = fM1_Benefit.Name;
            fM2_Benefit.css_fm2__advantagePercentage__c   = fM1_Benefit.css_frm__AdvantagePercentage__c;
            fM2_Benefit.css_fm2__advantageAmount__c       = fM1_Benefit.css_frm__AdvantageAmount__c;
            fM2_Benefit.css_fm2__advantageIsCash__c       = fM1_Benefit.css_frm__Advantage_isCash__c;
            fM2_Benefit.css_fm2__advantageDescription__c  = fM1_Benefit.css_frm__AdvantageDescription__c;
            fM2_Benefit.css_fm2__advantageIsObject__c     = fM1_Benefit.css_frm__Advantage_isObject__c;
            fM2_Benefit.css_fm2__legacyId__c              = fM1_Benefit.Id;
            fM2_Benefit.css_fm2__dataMigrationComment__c  = 'Created by cloudStack fM1-to-fM2 Utility '+Date.today();
            new_fM2_Benefits.add(fM2_Benefit);
        }
        insert new_fM2_Benefits;

        upgradeBatchRecord.Status__c = 'Pass';
      } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
      }
      update upgradeBatchRecord;
    }
        
    public void finish(Database.BatchableContext BC) {
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Benefit' LIMIT 1];

      List<Clone_Reference__c> cloneRecordList = new List<Clone_Reference__c>();
      List<css_fm2__Benefit__c> new_fM2_Benefits = [SELECT Name, Id, css_fm2__legacyId__c FROM css_fm2__Benefit__c];
      for (css_fm2__Benefit__c benefit : new_fM2_Benefits) {
        Clone_Reference__c cloneReference = new Clone_Reference__c();
        cloneReference.UpgradeBatchRecord__c = upgradeBatchRecord.Id;
        cloneReference.Benefit_fM1__c = benefit.css_fm2__legacyId__c;
        cloneReference.Benefit_fM2__c = benefit.Id;
        cloneRecordList.add(cloneReference);
      }
      insert cloneRecordList;

      List<css_frm__Benefit__c> benefitList = [SELECT Name FROM css_frm__Benefit__c];
      upgradeBatchRecord.recordsProcessed__c = benefitList.size();
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+benefitList.size()+ ' Benefit record(s) processed';
      update upgradeBatchRecord;
      fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Benefit processing complete'); 
    }
  }