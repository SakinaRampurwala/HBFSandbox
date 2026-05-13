@isTest private class fM2UpgradeManager_Test {
    static final String className = 'processContacts_Batch_Test';
  
    @testSetup static void setup() {
      String methodName = 'setup';
      
      Contact testContact = new Contact(LastName = 'Testerson'); insert testContact;
      System.debug(className+methodName+' testContact: '+testContact);
      Account testAccount = new Account(Name = 'cloudStack'); insert testAccount;
      System.debug(className+methodName+' testAccount: '+testAccount);
      css_frm__Benefit__c testBenefit = new css_frm__Benefit__c(Name = 'testBenefit', css_frm__AdvantagePercentage__c = 1, css_frm__AdvantageDescription__c = 'test'); insert testBenefit;
      System.debug(className+methodName+' testBenefit: '+testBenefit);
      Campaign testCampaign = new Campaign(Name = 'testCampaign', css_frm__Benefit__c = testBenefit.Id); insert testCampaign;
      System.debug(className+methodName+' testCampaign: '+testCampaign);
      Opportunity testOpp = new Opportunity(Name = 'testOpp', npsp__Primary_Contact__c = testContact.Id, Amount = 10, StageName = 'Closed Won', CloseDate = Date.Today()); insert testOpp;
      System.debug(className+methodName+' testOpp: '+testOpp);
      npe01__OppPayment__c testPayment = new npe01__OppPayment__c(npe01__Opportunity__c = testOpp.Id, npe01__Payment_Amount__c = 10, npe01__Payment_Date__c = Date.Today()); insert testPayment;
      System.debug(className+methodName+' testPayment: '+testPayment);
      css_frm__Transaction__c testTransaction = new css_frm__Transaction__c(css_frm__Payment__c = testPayment.Id, css_frm__Amount__c = 10, css_frm__PaymentDate__c = Date.Today()); insert testTransaction;
      System.debug(className+methodName+' testTransaction: '+testTransaction);
      css_frm__PaymentProcessor__c testPaymentProcessor = new css_frm__PaymentProcessor__c(Name = 'testPaymentProcessor'); insert testPaymentProcessor;
      System.debug(className+methodName+' testPaymentProcessor: '+testPaymentProcessor);
      css_frm__Receipt__c testReceipt = new css_frm__Receipt__c(css_frm__Opportunity__c = testOpp.Id); insert testReceipt;
      System.debug(className+methodName+' testReceipt: '+testReceipt);

      UpgradeBatch__c testUpgradeBatch = new UpgradeBatch__c(Name = 'testUpgradeBatch');
      insert testUpgradeBatch;
      fM2UpgradeManager.upgradeInitialize(testUpgradeBatch.Id);
  
      List<UpgradeBatchRecord__c> upgradeBatchRecords = [SELECT Name, Type__c FROM UpgradeBatchRecord__c WHERE UpgradeBatch__c =: testUpgradeBatch.Id ];
      System.assertEquals(10, upgradeBatchRecords.Size(), 'Check correct Batch size');
    }
  
    static testmethod void upgradeContacts_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeContacts(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }
    
    static testmethod void upgradeAccounts_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeAccounts(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradeBenefits_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeBenefits(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradeCampaigns_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeCampaigns(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradeOpportunities_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeOpportunities(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradePayments_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradePayments(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradeTransactions_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeTransactions(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradePaymentProcessors_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradePaymentProcessors(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradeReceipts_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeReceipts(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }

    static testmethod void upgradeOpportunityReceipts_Test() {
      UpgradeBatch__c upgradeBatch = [SELECT Name FROM UpgradeBatch__c WHERE Name = 'testUpgradeBatch' LIMIT 1];
      fM2UpgradeManager.upgradeOpportunityReceipts(upgradeBatch.Id);
      System.assertEquals(true, true, 'Check correct Batch status');
    }
  }