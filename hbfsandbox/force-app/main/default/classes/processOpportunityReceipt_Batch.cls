public class processOpportunityReceipt_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    static final String className = 'processOpportunityReceipt_Batch:';
      
    private String upgradeBatchId;
      
    public processOpportunityReceipt_Batch(String upgradeBatchIdVal) {
      upgradeBatchId = upgradeBatchIdVal;
    }
          
    public Database.QueryLocator start(Database.BatchableContext BC) {
      String query = 'SELECT Name, Id, css_frm__Opportunity__c FROM css_frm__Receipt__c';
      System.debug('query: '+query);
      return Database.getQueryLocator(query);
    }
        
    public void execute(Database.BatchableContext BC, List<css_frm__Receipt__c> fM1_Receipts) {
      String methodName = 'processOpportunityReceipt';
         
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Opportunity Receipt' LIMIT 1];

      List<Opportunity> oppsToUpdate = new List<Opportunity>();
      try{
        if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}

        List<Id> fM1_ReceiptIds = new List<Id>();
        for (css_frm__Receipt__c fM1_Receipt : fM1_Receipts) { fM1_ReceiptIds.add(fM1_Receipt.Id); }

        List<Opportunity> opportunityList = [SELECT Name, css_frm__Consolidated_Receipt__c FROM Opportunity];
        // List<css_frm__Receipt__c> fM1_Receipts = [SELECT Name, Id, css_frm__Opportunity__c FROM css_frm__Receipt__c];
        List<css_fm2__Receipt__c> cloned_fM2_OneTimeReceipts = [SELECT Name, Id, css_fm2__legacyId__c, css_fm2__receiptType__c, css_fm2__Status__c FROM css_fm2__Receipt__c 
                                                                WHERE css_fm2__receiptType__c = 'One-Time' AND css_fm2__Status__c !='Void' AND css_fm2__legacyId__c IN: fM1_ReceiptIds];
        List<css_fm2__Receipt__c> cloned_fM2_ConsolidatedReceipts = [SELECT Name, Id, css_fm2__legacyId__c, css_fm2__receiptType__c, css_fm2__Status__c FROM css_fm2__Receipt__c 
                                                                     WHERE css_fm2__receiptType__c = 'Consolidated' AND css_fm2__Status__c !='Void' AND css_fm2__legacyId__c IN: fM1_ReceiptIds];

        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n\n fM1_Receipts:\n '+fM1_Receipts;
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n\n cloned_fM2_OneTimeReceipts:\n '+cloned_fM2_OneTimeReceipts;
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n\n cloned_fM2_ConsolidatedReceipts:\n '+cloned_fM2_ConsolidatedReceipts;

        Map<Id,Id> fM1tofM2_receiptMap = new Map<Id,Id>();
        for (css_fm2__Receipt__c receipt : cloned_fM2_OneTimeReceipts)      { fM1tofM2_receiptMap.put(receipt.css_fm2__legacyId__c, receipt.Id); }
        for (css_fm2__Receipt__c receipt : cloned_fM2_ConsolidatedReceipts) { fM1tofM2_receiptMap.put(receipt.css_fm2__legacyId__c, receipt.Id); }
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n\n fM1tofM2_receiptMap:\n '+fM1tofM2_receiptMap;
  
        // One-Time Opp/Receipts Mapping
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n\n Processing '+cloned_fM2_OneTimeReceipts.size()+ ' One-Time Receipt record(s)';
        Map<Id,Opportunity> fM2ReceipttoOpportunityMap = new Map<Id,Opportunity>();
        for (css_frm__Receipt__c fM1_Receipt : fM1_Receipts) {
          for (Opportunity opp : opportunityList) {
            if(fM1_Receipt.css_frm__Opportunity__c == opp.Id) {fM2ReceipttoOpportunityMap.put(fM1tofM2_receiptMap.get(fM1_Receipt.Id), opp);}
          }
        }
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n fM2ReceipttoOpportunityMap:\n '+fM2ReceipttoOpportunityMap;
  
        for (css_fm2__Receipt__c receipt : cloned_fM2_OneTimeReceipts) {
          fM2ReceipttoOpportunityMap.get(receipt.Id).css_fm2__Receipt__c = receipt.Id;
          oppsToUpdate.add(fM2ReceipttoOpportunityMap.get(receipt.Id));
        }

        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n\n Processing '+cloned_fM2_ConsolidatedReceipts.size()+ ' Consolidated Receipt record(s)';
        for (Opportunity opp : opportunityList) {
          if(opp.css_frm__Consolidated_Receipt__c != null) {
            opp.css_fm2__Receipt__c = fM1tofM2_receiptMap.get(opp.css_frm__Consolidated_Receipt__c);
            oppsToUpdate.add(opp);
          }
        }
        update oppsToUpdate;
  
        upgradeBatchRecord.Status__c = 'Pass';
      } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
      }
      update upgradeBatchRecord;
    }
        
    public void finish(Database.BatchableContext BC) {
      UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Opportunity Receipt' LIMIT 1];
      List<css_fm2__Receipt__c> cloned_fM2_Receipts = [SELECT Name, Id, css_fm2__legacyId__c, css_fm2__receiptType__c FROM css_fm2__Receipt__c WHERE css_fm2__Status__c !='Void' AND css_fm2__legacyId__c != null];
      upgradeBatchRecord.recordsProcessed__c = cloned_fM2_Receipts.size();
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+cloned_fM2_Receipts.size()+ ' Opportunity Receipt record(s) processed';
      update upgradeBatchRecord;
      fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Opportunity Receipt processing complete'); 
    }
  }