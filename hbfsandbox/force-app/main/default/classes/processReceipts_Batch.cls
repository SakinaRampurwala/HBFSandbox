public class processReceipts_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts {
  static final String className = 'processReceipts_Batch:';
        
  private String upgradeBatchId;
      
  public processReceipts_Batch(String upgradeBatchIdVal) {
    upgradeBatchId = upgradeBatchIdVal; 
  }
            
  public Database.QueryLocator start(Database.BatchableContext BC) {
    String query = 'SELECT Name, css_frm__Recurring_Donation__c, css_frm__Opportunity__c, css_frm__Opportunity__r.AccountId, css_frm__Opportunity__r.Account.RecordTypeId,'+ 
      'css_frm__Opportunity__r.npsp__Primary_Contact__c, css_frm__ReceiptNumber__c, css_frm__ReceiptNumberStamp__c, css_frm__DonationDate__c, css_frm__ReceiptAmount__c,'+
      'css_frm__Original_Receipt__c, css_frm__AdvantageAmount__c, css_frm__EligibleAmount__c, css_frm__Consolidated_Receipt_Start_Date__c, css_frm__Consolidated_Receipt_End_Date__c,'+
      'css_frm__Receipt_Cancelled__c, CreatedDate, css_frm__Opportunity__r.CampaignId, RecordTypeId, css_frm__Recurring_Donation__r.npe03__Contact__c, css_frm__Consolidated_Receipt_Amount__c'+
      ' FROM css_frm__Receipt__c';
    return Database.getQueryLocator(query);
  }
          
  public void execute(Database.BatchableContext BC, List<css_frm__Receipt__c> receiptList) {
    String methodName = 'processReceipts';

    UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Receipt' LIMIT 1];

    try{
      if(upgradeBatchRecord.Log__c == null) {upgradeBatchRecord.Log__c = '';}
      // upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Processing '+receiptList.size()+ ' record(s)';

      fM2UpgradeManager.customSettings accountCustomSettings = fM2UpgradeManager.getCustomSettings();
      String taxJurisdiction  = accountCustomSettings.TaxJurisdiction;
      String taxNumber        = accountCustomSettings.TaxNumber;
                                            
      Set<Id> fM1_ReceiptIds = new Set<Id>();
      for (css_frm__Receipt__c fM1_Receipt : receiptList) { fM1_ReceiptIds.add(fM1_Receipt.Id); }

      // Create new fM2 Receipt records
        List<css_fm2__Receipt__c> new_fM2_Receipts = new List<css_fm2__Receipt__c>();
        for (css_frm__Receipt__c fM1_Receipt : receiptList) {
          css_fm2__Receipt__c fM2_Receipt = new css_fm2__Receipt__c();
          fM2_Receipt.css_fm2__TaxJurisdiction__c       = taxJurisdiction;
          fM2_Receipt.css_fm2__TaxNumber__c             = taxNumber;
          String [] strArr = fM1_Receipt.css_frm__ReceiptNumberStamp__c.split('-');
          fM2_Receipt.css_fm2__ReceiptPrefix__c         = strArr[0]+'-';
          fM2_Receipt.css_fm2__ReceiptStackNumber__c    = Integer.valueOf(strArr[1]); 
          String Status = 'Issued';
          if(fM1_Receipt.css_frm__Receipt_Cancelled__c == true) {Status = 'Void';}
          fM2_Receipt.css_fm2__Status__c = Status;
          // fM2_Receipt.css_fm2__previouslyIssuedReceipt__c = fM1_Receipt.css_frm__Original_Receipt__c;

          String fM1ReceiptRecordType = Schema.getGlobalDescribe().get('css_frm__Receipt__c').getDescribe().getRecordTypeInfosById().get(fM1_Receipt.RecordTypeId).getName();
          if(fM1ReceiptRecordType == 'Consolidated' ) {
            fM2_Receipt.css_fm2__DonorIndividual__c = fM1_Receipt.css_frm__Recurring_Donation__r.npe03__Contact__c;
          } else {
              String accountRecordType = Schema.getGlobalDescribe().get('Account').getDescribe().getRecordTypeInfosById().get(fM1_Receipt.css_frm__Opportunity__r.Account.RecordTypeId).getName();
              if(accountRecordType == 'Household Account') { fM2_Receipt.css_fm2__DonorIndividual__c = fM1_Receipt.css_frm__Opportunity__r.npsp__Primary_Contact__c; } 
              else { fM2_Receipt.css_fm2__DonorOrganization__c = fM1_Receipt.css_frm__Opportunity__r.AccountId; }
          }
          fM2_Receipt.css_fm2__donationDate__c                  = fM1_Receipt.css_frm__DonationDate__c;
          if(fM1ReceiptRecordType == 'Consolidated' ) {
            fM2_Receipt.css_fm2__DonationAmount__c              = fM1_Receipt.css_frm__Consolidated_Receipt_Amount__c;
          } else {
            fM2_Receipt.css_fm2__DonationAmount__c              = fM1_Receipt.css_frm__ReceiptAmount__c;
          }
          fM2_Receipt.css_fm2__AdvantageAmount__c               = fM1_Receipt.css_frm__AdvantageAmount__c;
          fM2_Receipt.css_fm2__EligibleAmount__c                = fM1_Receipt.css_frm__EligibleAmount__c;
          fM2_Receipt.css_fm2__consolidatedReceiptStartDate__c  = fM1_Receipt.css_frm__Consolidated_Receipt_Start_Date__c;
          fM2_Receipt.css_fm2__consolidatedReceiptEndDate__c    = fM1_Receipt.css_frm__Consolidated_Receipt_End_Date__c;
          fM2_Receipt.css_fm2__receiptIssuedDate__c             = Date.newinstance(fM1_Receipt.CreatedDate.year(), fM1_Receipt.CreatedDate.month(), fM1_Receipt.CreatedDate.day());
          fM2_Receipt.css_fm2__donationCampaign__c              = fM1_Receipt.css_frm__Opportunity__r.CampaignId;        
          fM2_Receipt.css_fm2__receiptType__c                   = Schema.getGlobalDescribe().get('css_frm__Receipt__c').getDescribe().getRecordTypeInfosById().get(fM1_Receipt.RecordTypeId).getName();
          fM2_Receipt.css_fm2__legacyId__c                      = fM1_Receipt.Id;
          fM2_Receipt.css_fm2__dataMigrationComment__c          = 'Created by cloudStack fM1-to-fM2 Utility '+Date.today();
          new_fM2_Receipts.add(fM2_Receipt);
        }
        insert new_fM2_Receipts;

      new_fM2_Receipts = [SELECT Name, Id, css_fm2__legacyId__c FROM css_fm2__Receipt__c];
      Map<Id,Id> fM1tofM2_receiptMap = new Map<Id,Id>();
      new_fM2_Receipts = [SELECT Name, Id, css_fm2__legacyId__c FROM css_fm2__Receipt__c];
      for (css_fm2__Receipt__c receipt : new_fM2_Receipts) { fM1tofM2_receiptMap.put(receipt.css_fm2__legacyId__c, receipt.Id); }

      List<Attachment> fM1_ReceiptAttachments = [SELECT Name, Body, ParentId FROM Attachment WHERE ParentId IN : fM1_ReceiptIds];
      // upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n fM1_ReceiptAttachments '+fM1_ReceiptAttachments.size();

      // Clone existing PDF Attachments
        List<Attachment> cloned_ReceiptAttachments = new List<Attachment>();
        for (Attachment pdfAttachment : fM1_ReceiptAttachments) {
          Attachment clone_pdfAttachment = new Attachment();
          clone_pdfAttachment.Name = pdfAttachment.Name; 
          clone_pdfAttachment.Body = pdfAttachment.Body;
          clone_pdfAttachment.IsPrivate = false;
          clone_pdfAttachment.ParentId = fM1tofM2_receiptMap.get(pdfAttachment.ParentId);
          cloned_ReceiptAttachments.add(clone_pdfAttachment);
        }
        insert cloned_ReceiptAttachments;
        upgradeBatchRecord.Status__c = 'Pass';
    } catch ( Exception e) {
        upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c+ '\n Problem - Exception: ' +e+' Line - '+e.getLineNumber();
        upgradeBatchRecord.Status__c = 'Fail';
    }
    update upgradeBatchRecord;
  }
          
  public void finish(Database.BatchableContext BC) {
    UpgradeBatchRecord__c upgradeBatchRecord = [SELECT Name, Log__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c = 'Receipt' LIMIT 1];

    List<Clone_Reference__c> cloneRecordList = new List<Clone_Reference__c>();
    List<css_fm2__Receipt__c> new_fM2_Receipts = [SELECT Name, Id, css_fm2__legacyId__c FROM css_fm2__Receipt__c];
    for (css_fm2__Receipt__c receipt : new_fM2_Receipts) {
      Clone_Reference__c cloneReference = new Clone_Reference__c();
      cloneReference.UpgradeBatchRecord__c = upgradeBatchRecord.Id;
      cloneReference.Receipt_fM1__c = receipt.css_fm2__legacyId__c;
      cloneReference.Receipt_fM2__c = receipt.Id;
      cloneRecordList.add(cloneReference);
    }
    insert cloneRecordList;

    List<css_frm__Receipt__c> receiptList = [SELECT Name FROM css_frm__Receipt__c];
      upgradeBatchRecord.recordsProcessed__c = receiptList.size();
      upgradeBatchRecord.Log__c = upgradeBatchRecord.Log__c + '\n '+receiptList.size()+ ' Receipt record(s) processed';
    update upgradeBatchRecord;
    fM2UpgradeManager.sendBatchFinishEmail('ken@cloudstackservices.com', 'cloudStack fM2 Upgrade : Receipt processing complete'); 
  }
}