@IsTest
private class ProjectCompletionEmailCtrlTest {
    @TestSetup
    static void setupData() {
        Account customer = new Account(Name = 'Project Test Customer');
        insert customer;

        Contact client = new Contact(
            FirstName = 'Project',
            LastName = 'Client',
            Email = 'client@example.com',
            Phone = '3035550100',
            AccountId = customer.Id
        );
        insert client;

        buildertek__Project__c project = new buildertek__Project__c(
            Name = 'Completion Test Project',
            buildertek__Customer__c = customer.Id,
            buildertek__Customer_Contact__c = client.Id
        );
        insert project;
    }

    @IsTest
    static void getInitialStateReturnsDefaultsForIncompleteProject() {
        buildertek__Project__c project = getProject();

        ProjectCompletionEmailCtrl.InitialState state =
            ProjectCompletionEmailCtrl.getInitialState(project.Id);

        System.assertEquals(project.Id, state.projectId);
        System.assertEquals('Project Completion Form', state.defaultSubject);
        System.assertEquals(1, state.defaultSelectedContact.size());
        System.assertEquals('Project Client', state.defaultSelectedContact[0].Name);
        System.assertEquals('client@example.com', state.defaultSelectedContact[0].Email);
        System.assertEquals('client@example.com', state.defaultToAddress);
        System.assertEquals('Project Completion Form', state.defaultEmailTemplate);
        System.assert(state.bodyTemplateQuery.contains('Project_Form_Email'));
        System.assert(state.attachmentTemplateQuery.contains('Project_Completion_Form'));
        System.assert(state.signedPdfName.endsWith('.pdf'));
    }

    @IsTest
    static void getInitialStateDoesNotBlockProjectWithSavedSignature() {
        buildertek__Project__c project = getProject();
        putSignIdIfConfigured(project, '068000000000001AAA');
        update project;

        ProjectCompletionEmailCtrl.InitialState state =
            ProjectCompletionEmailCtrl.getInitialState(project.Id);

        System.assertEquals(project.Id, state.projectId);
        System.assertEquals('client@example.com', state.defaultToAddress);
    }

    @IsTest
    static void publicFormSubmitCreatesFilesAndCompletesProject() {
        buildertek__Project__c project = getProject();

        PageReference page = Page.ProjectCompletionForm;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('Id', String.valueOf(project.Id));

        ProjectCompletionFormController controller = new ProjectCompletionFormController();

        Test.startTest();
        controller.initialize();
        controller.imageContent = EncodingUtil.base64Encode(Blob.valueOf('signature'));
        controller.submitProjectCompletion();
        Test.stopTest();

        System.assertEquals(true, controller.isSubmitted);
        System.assertEquals(true, controller.isAlreadyComplete);
        System.assertEquals(false, controller.hasError);

        buildertek__Project__c completedProject = [
            SELECT buildertek__Stage__c,
                   buildertek__Actual_Completion_Date__c,
                   buildertek__Project_Completion_Date__c,
                   buildertek__Closing_Date__c,
                   buildertek__Project_Completion__c
            FROM buildertek__Project__c
            WHERE Id = :project.Id
        ];
        System.assertEquals('Completed', completedProject.buildertek__Stage__c);
        System.assertEquals(Date.today(), completedProject.buildertek__Actual_Completion_Date__c);
        System.assertEquals(Date.today(), completedProject.buildertek__Project_Completion_Date__c);
        System.assertEquals(Date.today(), completedProject.buildertek__Closing_Date__c);
        System.assertEquals(100, completedProject.buildertek__Project_Completion__c);
        assertSignIdIfConfigured(project.Id);

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :project.Id
        ];
        System.assertEquals(2, links.size());

        Map<String, ContentVersion> versionsByTitle = new Map<String, ContentVersion>();
        for (ContentVersion versionRecord : [
            SELECT Title, OwnerId, FirstPublishLocationId
            FROM ContentVersion
            WHERE Title IN (
                'Project Completion Form - Completion Test Project',
                'Project Completion Form - Completion Test Project Signature'
            )
        ]) {
            versionsByTitle.put(versionRecord.Title, versionRecord);
        }

        ContentVersion signatureVersion =
            versionsByTitle.get('Project Completion Form - Completion Test Project Signature');
        ContentVersion pdfVersion =
            versionsByTitle.get('Project Completion Form - Completion Test Project');
        System.assertNotEquals(null, signatureVersion);
        System.assertNotEquals(null, pdfVersion);
        System.assertEquals(signatureVersion.OwnerId, pdfVersion.OwnerId);
        System.assertEquals(project.Id, pdfVersion.FirstPublishLocationId);
    }

    @IsTest
    static void publicFormSubmitBlocksDuplicateCompletedProject() {
        buildertek__Project__c project = getProject();
        putSignIdIfConfigured(project, '068000000000001AAA');
        update project;

        PageReference page = Page.ProjectCompletionForm;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('Id', String.valueOf(project.Id));

        ProjectCompletionFormController controller = new ProjectCompletionFormController();
        controller.initialize();
        controller.imageContent = EncodingUtil.base64Encode(Blob.valueOf('signature'));
        controller.submitProjectCompletion();

        System.assertEquals(false, controller.isSubmitted);
        System.assertEquals(true, controller.isAlreadyComplete);
        System.assert(controller.message.contains('already been signed'));
    }

    @IsTest
    static void publicFormSubmitRequiresSignature() {
        buildertek__Project__c project = getProject();

        PageReference page = Page.ProjectCompletionForm;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('Id', String.valueOf(project.Id));

        ProjectCompletionFormController controller = new ProjectCompletionFormController();
        controller.initialize();
        controller.submitProjectCompletion();

        System.assertEquals(true, controller.hasError);
        System.assertEquals('Signature is required.', controller.message);
    }

    @IsTest
    static void pdfRenderHelpersBuildPublicSiteUrlAndRejectBlankPdf() {
        buildertek__Project__c project = getProject();

        PageReference page = Page.ProjectCompletionForm;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getHeaders().put('Host', 'HBFDenver--PartialDev.Sandbox.My.Salesforce-Sites.com');

        String publicBaseUrl = ProjectCompletionFormController.getCurrentRequestBaseUrl();
        System.assertEquals(
            'https://hbfdenver--partialdev.sandbox.my.salesforce-sites.com',
            publicBaseUrl
        );

        String publicPdfUrl = ProjectCompletionFormController.buildPublicPdfUrl(
            publicBaseUrl + '/',
            project.Id,
            '068000000000001AAA',
            '069000000000001AAA',
            '05D000000000001AAA'
        );
        System.assert(publicPdfUrl.startsWith(publicBaseUrl + '/apex/ProjectCompletionFormPdf?Id='));
        System.assert(publicPdfUrl.contains('&signatureVersionId=068000000000001AAA'));
        System.assert(publicPdfUrl.contains('&signatureDocumentId=069000000000001AAA'));
        System.assert(publicPdfUrl.contains('&signatureDistributionId=05D000000000001AAA'));
        System.assertEquals(
            null,
            ProjectCompletionFormController.buildPublicPdfUrl('', project.Id, null, null, null)
        );
        System.assertEquals(false, ProjectCompletionFormController.isUsablePdf(null));
        System.assertEquals(false, ProjectCompletionFormController.isUsablePdf(Blob.valueOf('small')));

        String largeBody = '';
        for (Integer index = 0; index < 1001; index++) {
            largeBody += 'x';
        }
        System.assertEquals(true, ProjectCompletionFormController.isUsablePdf(Blob.valueOf(largeBody)));
    }

    @IsTest
    static void pdfControllerReadsProjectAndSignature() {
        buildertek__Project__c project = getProject();
        project.buildertek__Project_Completion_Date__c = Date.newInstance(2026, 5, 8);
        update project;

        ContentVersion signatureVersion = new ContentVersion(
            Title = 'PDF Controller Signature',
            PathOnClient = 'signature.png',
            VersionData = Blob.valueOf('signature'),
            FirstPublishLocationId = project.Id
        );
        insert signatureVersion;
        signatureVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :signatureVersion.Id
        ];

        PageReference page = Page.ProjectCompletionFormPdf;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('Id', String.valueOf(project.Id));
        ApexPages.currentPage().getParameters().put('signatureVersionId', String.valueOf(signatureVersion.Id));
        ApexPages.currentPage().getParameters().put('signatureDocumentId', String.valueOf(signatureVersion.ContentDocumentId));

        ProjectCompletionFormPdfController controller = new ProjectCompletionFormPdfController();

        System.assertEquals(project.Name, controller.projectName);
        System.assertEquals('Project Client', controller.signerName);
        System.assertEquals('client@example.com', controller.signerEmail);
        System.assertEquals(true, controller.getHasSignature());
        System.assertEquals(
            '/sfc/servlet.shepherd/document/download/' + String.valueOf(signatureVersion.ContentDocumentId),
            controller.getSignatureImageUrl()
        );
        System.assertEquals(
            '',
            ProjectCompletionFormPdfController.loadContentDistributionDownloadUrl(null)
        );
        System.assertEquals(
            '',
            ProjectCompletionFormPdfController.resolveContentDocumentId(null, null)
        );
        System.assertEquals(
            '/sfc/servlet.shepherd/version/download/' + String.valueOf(signatureVersion.Id),
            ProjectCompletionFormPdfController.buildSalesforceFileDownloadUrl(String.valueOf(signatureVersion.Id), null)
        );
        System.assertEquals(
            '',
            ProjectCompletionFormPdfController.buildSalesforceFileDownloadUrl(null, null)
        );
        System.assertEquals('05/08/2026', controller.getSignedDateDisplay());
    }

    private static buildertek__Project__c getProject() {
        return [
            SELECT Id, Name
            FROM buildertek__Project__c
            WHERE Name = 'Completion Test Project'
            LIMIT 1
        ];
    }

    private static void assertSignIdIfConfigured(Id projectId) {
        if (!buildertek__Project__c.SObjectType.getDescribe().fields.getMap().containsKey('Project_Completion_Sign_Id__c')) {
            return;
        }

        List<SObject> projects = Database.query(
            'SELECT Project_Completion_Sign_Id__c FROM buildertek__Project__c WHERE Id = :projectId'
        );
        System.assertNotEquals(null, projects[0].get('Project_Completion_Sign_Id__c'));
    }

    private static void putSignIdIfConfigured(buildertek__Project__c project, String signId) {
        if (!buildertek__Project__c.SObjectType.getDescribe().fields.getMap().containsKey('Project_Completion_Sign_Id__c')) {
            return;
        }
        project.put('Project_Completion_Sign_Id__c', signId);
    }
}