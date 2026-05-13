public class fM2UpgradeManager {
  static final Integer commonBatchSize = 200;

  public class orgInfo {
    public String contactInfo;
    public String accountInfo;
    public String benefitInfo;
    public String campaignInfo;
    public String opportunityInfo;
    public String paymentInfo;
    public String receiptInfo;
    public String transactionInfo;
    public String paymentProcessorInfo;
  }

  public class batchRecordInfo {
    String Type;
    String Status;
    Integer recordsProcessed;
    String message;
  }

  public class response {
    public String responseString;
    public String batchId;
  }

   public class customSettings {
    public String EmailDisplay;
    public String EmailReplyTo;
    public String TaxJurisdiction;
    public String TaxNumber;
    public String ReceiptPrefix;
    public Decimal ReceiptStartingNumber;
  }

  public fM2UpgradeManager(ApexPages.StandardController stdController) {
  } // end fM2UpgradeManager

  @RemoteAction
  public static List<batchRecordInfo> upgradeInitialize(String upgradeBatchId) {
    Integer contactListsize = [SELECT Name FROM Contact].size();

    List<String> batchObjects = new List<String> {'Contact','Account','Benefit','Campaign','Opportunity','Payment','Receipt','Transaction','Payment Processor', 'Opportunity Receipt'};
    List<UpgradeBatchRecord__c> newBatchRecordList = new List<UpgradeBatchRecord__c>();
    List<UpgradeBatchRecord__c> batchRecordList = new List<UpgradeBatchRecord__c>();

    // Create BatchRecords if they do not already exist
    for (String batchObject : batchObjects) {
      batchRecordList = [SELECT Type__c, Status__c, recordsProcessed__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId AND Type__c =: batchObject];
      if(batchRecordList.size() == 0) {
        UpgradeBatchRecord__c newBatchRecord = new UpgradeBatchRecord__c();
          newBatchRecord.Type__c = batchObject;
          newBatchRecord.recordsProcessed__c = 0;
          newBatchRecord.Status__c = 'Created';
          newBatchRecord.UpgradeBatch__c = upgradeBatchId;
          newBatchRecordList.add(newBatchRecord);
      }
    }
    insert newBatchRecordList;

    List<batchRecordInfo> batchRecordInfoList = new List<batchRecordInfo>();
    batchRecordList = [SELECT Type__c, Status__c, recordsProcessed__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: upgradeBatchId ];
    for (UpgradeBatchRecord__c batchRecord : batchRecordList) {
      batchRecordInfo info = new batchRecordInfo();
        info.Type = batchRecord.Type__c;
        info.Status = batchRecord.Status__c;
        info.recordsProcessed = (Integer)batchRecord.recordsProcessed__c;
        info.message = (Integer)batchRecord.recordsProcessed__c + ' records processed';
        batchRecordInfoList.add(info);
    }

    return batchRecordInfoList;
  } // end upgradeInitialize

  @RemoteAction
  public static orgInfo upgradeSetup() {
    orgInfo oInfo = new orgInfo();

    List<Contact> contactList = [SELECT Name FROM Contact];
    oInfo.contactInfo = 'Process '+contactList.size()+ ' Contact(s)';

    List<Account> accountList = [SELECT Name FROM Account];
    oInfo.accountInfo = 'Process '+accountList.size() + ' Account(s)';

    List<css_frm__Benefit__c> benefitList = [SELECT Name FROM css_frm__Benefit__c];
    oInfo.benefitInfo = 'Process '+benefitList.size() + ' Benefit(s)';

    List<Campaign> campaignList = [SELECT Name FROM Campaign];
    oInfo.campaignInfo = 'Process '+campaignList.size() + ' Campaign(s)';

    List<Opportunity> opportunityList = [SELECT Name FROM Opportunity];
    oInfo.opportunityInfo = 'Process '+opportunityList.size() + ' Opportunity(s)';

    List<npe01__OppPayment__c> paymentList = [SELECT Name FROM npe01__OppPayment__c];
    oInfo.paymentInfo = 'Process '+paymentList.size() + ' Payment(s)';

    List<css_frm__Receipt__c> receiptList = [SELECT Name FROM css_frm__Receipt__c];
    oInfo.receiptInfo = 'Process '+receiptList.size() + ' Receipt(s)';

    List<css_frm__Transaction__c> transactionList = [SELECT Name FROM css_frm__Transaction__c];
    oInfo.transactionInfo = 'Process '+transactionList.size() + ' Transaction(s)';

    List<css_frm__PaymentProcessor__c> paymentProcessorList = [SELECT Name FROM css_frm__PaymentProcessor__c];
    oInfo.paymentProcessorInfo = 'Process '+paymentProcessorList.size() + ' Payment Processor(s)';

    return oInfo;
  } // end upgradeSetup

  @RemoteAction
  public static response upgradeContacts(String upgradeBatchId) {
    response contactResponse = new response();
    contactResponse.batchId = upgradeBatchId;
    contactResponse.responseString = 'Processing Contact records(s)';
    processContacts_Batch myBatchObject = new processContacts_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return contactResponse;
  } // end upgradeContacts

  @RemoteAction
  public static response upgradeAccounts(String upgradeBatchId) {
    response accountResponse = new response();
    accountResponse.batchId = upgradeBatchId;
    accountResponse.responseString = 'Processing Account records(s)';
    processAccounts_Batch myBatchObject = new processAccounts_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return accountResponse;
  } // end upgradeAccounts

  @RemoteAction
  public static response upgradeCampaigns(String upgradeBatchId) {
    response accountResponse = new response();
    accountResponse.batchId = upgradeBatchId;
    accountResponse.responseString = 'Processing Campaign records(s)';
    processCampaigns_Batch myBatchObject = new processCampaigns_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return accountResponse;
  } // end upgradeCampaigns

  @RemoteAction
  public static response upgradeBenefits(String upgradeBatchId) {
    response benefitResponse = new response();
    benefitResponse.batchId = upgradeBatchId;
    benefitResponse.responseString = 'Processing Benefit records(s)';
    processBenefits_Batch myBatchObject = new processBenefits_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return benefitResponse;
  } // end upgradeBenefits

  @RemoteAction
  public static response upgradeReceipts(String upgradeBatchId) {
    response receiptResponse = new response();
    receiptResponse.batchId = upgradeBatchId;
    receiptResponse.responseString = 'Processing Receipt records(s)';
    processReceipts_Batch myBatchObject = new processReceipts_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return receiptResponse;
  } // end upgradeReceipts

  @RemoteAction
  public static response upgradeOpportunities(String upgradeBatchId) {
    response opportunityResponse = new response();
    opportunityResponse.batchId = upgradeBatchId;
    opportunityResponse.responseString = 'Processing Opportunity records(s)';
    processOpportunities_Batch myBatchObject = new processOpportunities_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return opportunityResponse;
  } // end upgradeOpportunities

  @RemoteAction
  public static response upgradePayments(String upgradeBatchId) {
    response paymentResponse = new response();
    paymentResponse.batchId = upgradeBatchId;
    paymentResponse.responseString = 'Processing Payment records(s)';
    processPayments_Batch myBatchObject = new processPayments_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return paymentResponse;
  } // end upgradePayments

  @RemoteAction
  public static response upgradeTransactions(String upgradeBatchId) {
    response transactionResponse = new response();
    transactionResponse.batchId = upgradeBatchId;
    transactionResponse.responseString = 'Processing Transaction records(s)';
    processTransactions_Batch myBatchObject = new processTransactions_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return transactionResponse;
  } // end upgradeTransactions

  @RemoteAction
  public static response upgradeOpportunityReceipts(String upgradeBatchId) {
    response opportunityReceiptsResponse = new response();
    opportunityReceiptsResponse.batchId = upgradeBatchId;
    opportunityReceiptsResponse.responseString = 'Processing Opportunity Receipt records(s)';
    processOpportunityReceipt_Batch myBatchObject = new processOpportunityReceipt_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return opportunityReceiptsResponse;
  } // end upgradeOpportunityReceipts

  @RemoteAction
  public static response upgradePaymentProcessors(String upgradeBatchId) {
    response paymentProcessorResponse = new response();
    paymentProcessorResponse.batchId = upgradeBatchId;
    paymentProcessorResponse.responseString = 'Processing Payment records(s)';
    processPaymentProcessors_Batch myBatchObject = new processPaymentProcessors_Batch(upgradeBatchId);
    Id batchId = Database.executeBatch(myBatchObject, commonBatchSize);
    return paymentProcessorResponse;
  } // end upgradePaymentProcessors

  public static void sendBatchFinishEmail(String toAddress, String emailSubject) {
    String[] toAddresses = new String[]{toAddress};
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(toAddresses);
      mail.setReplyTo('support@package.dev');
      mail.setSenderDisplayName('cloudStack Services Package Support');
      mail.setSubject(emailSubject);
      mail.setHtmlBody('');
    Messaging.sendEmail(new Messaging.Email[] { mail });
  } // end sendBatchFinishEmail

  public static customSettings getCustomSettings() {
    css_fm2__fundraisingManager_Setting__mdt[] fundraisingManager_Settings = [SELECT css_fm2__TaxJurisdiction__c, css_fm2__TaxNumber__c, css_fm2__ReceiptPrefix__c, css_fm2__ReceiptStartingNumber__c
                                                                     FROM css_fm2__fundraisingManager_Setting__mdt WHERE css_fm2__ClientAccountId__c = null];

    customSettings accountCustomSettings = new customSettings();
    if(fundraisingManager_Settings.size() > 0) {
      accountCustomSettings.TaxJurisdiction = fundraisingManager_Settings[0].css_fm2__TaxJurisdiction__c;
      accountCustomSettings.TaxNumber = fundraisingManager_Settings[0].css_fm2__TaxNumber__c;
      accountCustomSettings.ReceiptPrefix = fundraisingManager_Settings[0].css_fm2__ReceiptPrefix__c;
      accountCustomSettings.ReceiptStartingNumber = fundraisingManager_Settings[0].css_fm2__ReceiptStartingNumber__c;
    }

    return accountCustomSettings;
  } // end getCustomSettings
}