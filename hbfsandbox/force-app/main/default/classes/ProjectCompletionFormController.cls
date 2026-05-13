// Public signing runs from the Salesforce Site guest context and must update the BT Project/files.
public without sharing class ProjectCompletionFormController {
    private static final String COMPLETED_STAGE = 'Completed';
    private static final String SIGN_FIELD_API_NAME = 'Project_Completion_Sign_Id__c';
    private static final String DEFAULT_FORM_TITLE = 'Project Completion Form';
    private class ProjectCompletionFormException extends Exception {}

    public String imageContent { get; set; }
    public String recordId { get; set; }
    public String projectName { get; private set; }
    public String signerName { get; private set; }
    public String signerEmail { get; private set; }
    public String signerPhone { get; private set; }
    public String message { get; private set; }
    public Boolean isSubmitted { get; private set; }
    public Boolean isAlreadyComplete { get; private set; }
    public Boolean hasError { get; private set; }

    public ProjectCompletionFormController() {
        recordId = getRecordIdParameter();
        isSubmitted = false;
        isAlreadyComplete = false;
        hasError = false;
        message = '';
    }

    public PageReference initialize() {
        try {
            ProjectSnapshot project = loadProject(false);
            applyProjectDisplay(project);
            isAlreadyComplete = isProjectComplete(project);
            if (isAlreadyComplete) {
                message = 'This project completion form has already been signed.';
            }
        } catch (Exception ex) {
            hasError = true;
            message = ex.getMessage();
        }
        return null;
    }

    public PageReference submitProjectCompletion() {
        try {
            if (String.isBlank(imageContent)) {
                hasError = true;
                message = 'Signature is required.';
                return null;
            }

            ProjectSnapshot project = loadProject(true);
            applyProjectDisplay(project);

            if (isProjectComplete(project)) {
                isAlreadyComplete = true;
                message = 'This project completion form has already been signed.';
                return null;
            }

            PdfImageReference signatureImage = saveSignature(project.recordId, project.projectName, imageContent);
            completeProject(project.recordId, signatureImage.contentVersionId);
            saveSignedPdfAsync(
                String.valueOf(project.recordId),
                project.projectName,
                signatureImage.contentVersionId,
                signatureImage.contentDocumentId,
                signatureImage.contentDistributionId,
                getCurrentRequestBaseUrl()
            );

            isSubmitted = true;
            isAlreadyComplete = true;
            hasError = false;
            message = 'Thank you. Your project completion form has been signed.';
        } catch (Exception ex) {
            hasError = true;
            message = ex.getMessage();
        }
        return null;
    }

    public Boolean getCanSign() {
        return !isSubmitted && !isAlreadyComplete && !hasError;
    }

    public String getDisplayMessageClass() {
        return hasError ? 'message error' : 'message success';
    }

    public String getCurrentDateDisplay() {
        Date currentDate = Date.today();
        return DateTime.newInstance(currentDate.year(), currentDate.month(), currentDate.day()).format('MM/dd/yyyy');
    }

    private ProjectSnapshot loadProject(Boolean lockRow) {
        if (String.isBlank(recordId)) {
            throw new ProjectCompletionFormException('Project id is required.');
        }

        Id projectId;
        try {
            projectId = (Id) recordId;
        } catch (Exception ex) {
            throw new ProjectCompletionFormException('Invalid project id.');
        }

        if (projectId.getSObjectType() != buildertek__Project__c.SObjectType) {
            throw new ProjectCompletionFormException('Invalid project id.');
        }

        String selectClause =
            'SELECT Id, Name, buildertek__Customer_Contact__r.Name, buildertek__Customer_Contact__r.Email, '
            + 'buildertek__Customer_Contact__r.Phone, buildertek__Site_Contact__r.Name, '
            + 'buildertek__Site_Contact__r.Email, buildertek__Site_Contact__r.Phone';

        if (getProjectField(SIGN_FIELD_API_NAME) != null) {
            selectClause += ', ' + SIGN_FIELD_API_NAME;
        } else if (!Test.isRunningTest()) {
            throw new ProjectCompletionFormException('Project_Completion_Sign_Id__c is not configured on BT Project.');
        }

        String query = selectClause
            + ' FROM buildertek__Project__c WHERE Id = :projectId'
            + (lockRow ? ' FOR UPDATE' : '');

        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            throw new ProjectCompletionFormException('Project was not found.');
        }

        SObject projectRecord = records[0];
        ProjectSnapshot snapshot = new ProjectSnapshot();
        snapshot.recordId = (Id) projectRecord.get('Id');
        snapshot.projectName = (String) projectRecord.get('Name');
        snapshot.signId = getProjectField(SIGN_FIELD_API_NAME) == null
            ? null
            : (String) projectRecord.get(SIGN_FIELD_API_NAME);

        snapshot.customerContact = projectRecord.getSObject('buildertek__Customer_Contact__r');
        snapshot.siteContact = projectRecord.getSObject('buildertek__Site_Contact__r');
        return snapshot;
    }

    private void applyProjectDisplay(ProjectSnapshot project) {
        projectName = project.projectName;
        SObject contactRecord = project.customerContact != null ? project.customerContact : project.siteContact;
        signerName = contactRecord == null ? '' : (String) contactRecord.get('Name');
        signerEmail = contactRecord == null ? '' : (String) contactRecord.get('Email');
        signerPhone = contactRecord == null ? '' : (String) contactRecord.get('Phone');
    }

    private static Boolean isProjectComplete(ProjectSnapshot project) {
        return String.isNotBlank(project.signId);
    }

    private static PdfImageReference saveSignature(Id projectId, String projectName, String signatureBase64Data) {
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.ContentLocation = 'S';
        contentVersion.PathOnClient = buildFileBaseName(projectName) + ' Signature.png';
        contentVersion.Title = buildFileBaseName(projectName) + ' Signature';
        contentVersion.VersionData = EncodingUtil.base64Decode(signatureBase64Data);
        insert contentVersion;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
        ].ContentDocumentId;

        linkContentDocumentToProject(projectId, contentDocumentId);

        PdfImageReference imageReference = new PdfImageReference();
        imageReference.contentVersionId = String.valueOf(contentVersion.Id);
        imageReference.contentDocumentId = String.valueOf(contentDocumentId);
        imageReference.contentDistributionId = ensureContentDistributionId(
            contentVersion.Id,
            contentVersion.Title
        );
        return imageReference;
    }

    private void completeProject(Id projectId, String signatureVersionId) {
        buildertek__Project__c projectUpdate = new buildertek__Project__c();
        projectUpdate.Id = projectId;
        projectUpdate.buildertek__Stage__c = COMPLETED_STAGE;
        projectUpdate.buildertek__Actual_Completion_Date__c = Date.today();
        projectUpdate.buildertek__Project_Completion_Date__c = Date.today();
        projectUpdate.buildertek__Closing_Date__c = Date.today();
        projectUpdate.buildertek__Project_Completion__c = 100;
        if (getProjectField(SIGN_FIELD_API_NAME) != null) {
            projectUpdate.put(SIGN_FIELD_API_NAME, signatureVersionId);
        }
        update projectUpdate;

        completeRelatedProjectTasks(projectId);
    }

    private static void completeRelatedProjectTasks(Id projectId) {
        List<buildertek__Project_Task__c> projectTasks = [
            SELECT Id, buildertek__Milestone__c, buildertek__Completion__c
            FROM buildertek__Project_Task__c
            WHERE buildertek__Schedule__r.buildertek__Project__c = :projectId
        ];

        List<buildertek__Project_Task__c> taskUpdates = new List<buildertek__Project_Task__c>();
        for (buildertek__Project_Task__c projectTask : projectTasks) {
            if (projectTask.buildertek__Milestone__c != true) {
                projectTask.buildertek__Completion__c = 100;
                taskUpdates.add(projectTask);
            }
        }

        if (!taskUpdates.isEmpty()) {
            update taskUpdates;
        }
    }

    private static void saveSignedPdf(
        Id projectId,
        String projectName,
        String signatureVersionId,
        String signatureDocumentId,
        String signatureDistributionId,
        String publicBaseUrl
    ) {
        Blob pdfBody = buildSignedPdf(
            projectId,
            signatureVersionId,
            signatureDocumentId,
            signatureDistributionId,
            publicBaseUrl
        );
        String fileName = buildFileBaseName(projectName) + '.pdf';
        Id fileOwnerId = resolveContentVersionOwnerId(projectId, signatureVersionId);

        ContentVersion contentVersion = new ContentVersion();
        contentVersion.ContentLocation = 'S';
        contentVersion.OwnerId = fileOwnerId;
        contentVersion.FirstPublishLocationId = projectId;
        contentVersion.PathOnClient = fileName;
        contentVersion.Title = buildFileBaseName(projectName);
        contentVersion.VersionData = pdfBody;
        insert contentVersion;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
        ].ContentDocumentId;

        if (!hasProjectFileLink(projectId, contentDocumentId)) {
            linkContentDocumentToProject(projectId, contentDocumentId);
        }
    }

    private static Boolean hasProjectFileLink(Id projectId, Id contentDocumentId) {
        return ![
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
            AND ContentDocumentId = :contentDocumentId
            LIMIT 1
        ].isEmpty();
    }

    private static void linkContentDocumentToProject(Id projectId, Id contentDocumentId) {
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
        contentDocumentLink.LinkedEntityId = projectId;
        contentDocumentLink.ContentDocumentId = contentDocumentId;
        contentDocumentLink.ShareType = 'I';
        contentDocumentLink.Visibility = 'AllUsers';
        insert contentDocumentLink;
    }

    private static Id resolveContentVersionOwnerId(Id projectId, String signatureVersionId) {
        Id signatureId = parseContentVersionId(signatureVersionId);
        if (signatureId != null) {
            List<ContentVersion> signatureVersions = [
                SELECT OwnerId
                FROM ContentVersion
                WHERE Id = :signatureId
                LIMIT 1
            ];
            if (!signatureVersions.isEmpty() && isUserId(signatureVersions[0].OwnerId)) {
                return signatureVersions[0].OwnerId;
            }
        }

        List<buildertek__Project__c> projects = [
            SELECT OwnerId
            FROM buildertek__Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];
        if (!projects.isEmpty() && isUserId(projects[0].OwnerId)) {
            return projects[0].OwnerId;
        }

        return UserInfo.getUserId();
    }

    private static Id parseContentVersionId(String candidateId) {
        if (String.isBlank(candidateId)) {
            return null;
        }

        try {
            Id parsedId = (Id) candidateId;
            return parsedId.getSObjectType() == ContentVersion.SObjectType ? parsedId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isUserId(Id candidateId) {
        return candidateId != null && candidateId.getSObjectType() == User.SObjectType;
    }

    @future(callout=true)
    public static void saveSignedPdfAsync(
        String projectIdValue,
        String projectName,
        String signatureVersionId,
        String signatureDocumentId,
        String signatureDistributionId,
        String publicBaseUrl
    ) {
        try {
            saveSignedPdf(
                (Id) projectIdValue,
                projectName,
                signatureVersionId,
                signatureDocumentId,
                signatureDistributionId,
                publicBaseUrl
            );
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'ProjectCompletionFormController.saveSignedPdfAsync failed for projectId='
                    + projectIdValue
                    + ', signatureVersionId='
                    + signatureVersionId
                    + ', publicBaseUrl='
                    + publicBaseUrl
                    + ': '
                    + ex.getMessage()
                    + ' (line '
                    + ex.getLineNumber()
                    + ')'
                    + '\n'
                    + ex.getStackTraceString()
            );
            throw ex;
        }
    }

    private static Blob buildSignedPdf(
        Id projectId,
        String signatureVersionId,
        String signatureDocumentId,
        String signatureDistributionId,
        String publicBaseUrl
    ) {
        if (Test.isRunningTest()) {
            return Blob.valueOf('Project Completion Signed PDF');
        }

        String publicPdfUrl = buildPublicPdfUrl(
            publicBaseUrl,
            projectId,
            signatureVersionId,
            signatureDocumentId,
            signatureDistributionId
        );
        if (String.isNotBlank(publicPdfUrl)) {
            Blob publicPdfBody = new PageReference(publicPdfUrl).getContentAsPDF();
            if (isUsablePdf(publicPdfBody)) {
                return publicPdfBody;
            }
            System.debug(
                LoggingLevel.WARN,
                'ProjectCompletionFormController.buildSignedPdf public render returned blank PDF. Url='
                    + publicPdfUrl
                    + ', size='
                    + (publicPdfBody == null ? null : publicPdfBody.size())
            );
        }

        PageReference pdfPage = Page.ProjectCompletionFormPdf;
        pdfPage.getParameters().put('Id', String.valueOf(projectId));
        pdfPage.getParameters().put('signatureVersionId', signatureVersionId);
        pdfPage.getParameters().put('signatureDocumentId', signatureDocumentId);
        pdfPage.getParameters().put('signatureDistributionId', signatureDistributionId);
        pdfPage.setRedirect(true);
        Blob internalPdfBody = pdfPage.getContentAsPDF();
        if (!isUsablePdf(internalPdfBody)) {
            throw new ProjectCompletionFormException(
                'Project completion PDF rendered blank. Public Site render was unavailable and internal render did not produce content.'
            );
        }
        return internalPdfBody;
    }

    @TestVisible
    private static Boolean isUsablePdf(Blob pdfBody) {
        return pdfBody != null && pdfBody.size() > 1000;
    }

    @TestVisible
    private static String buildPublicPdfUrl(
        String publicBaseUrl,
        Id projectId,
        String signatureVersionId,
        String signatureDocumentId,
        String signatureDistributionId
    ) {
        if (String.isBlank(publicBaseUrl)) {
            return null;
        }

        String normalizedBaseUrl = publicBaseUrl.trim();
        while (normalizedBaseUrl.endsWith('/')) {
            normalizedBaseUrl = normalizedBaseUrl.left(normalizedBaseUrl.length() - 1);
        }

        return normalizedBaseUrl
            + '/apex/ProjectCompletionFormPdf?Id='
            + EncodingUtil.urlEncode(String.valueOf(projectId), 'UTF-8')
            + '&signatureVersionId='
            + EncodingUtil.urlEncode(blankToEmpty(signatureVersionId), 'UTF-8')
            + '&signatureDocumentId='
            + EncodingUtil.urlEncode(blankToEmpty(signatureDocumentId), 'UTF-8')
            + '&signatureDistributionId='
            + EncodingUtil.urlEncode(blankToEmpty(signatureDistributionId), 'UTF-8');
    }

    @TestVisible
    private static String getCurrentRequestBaseUrl() {
        Map<String, String> headers = ApexPages.currentPage().getHeaders();
        String host = headers.get('Host');
        if (String.isBlank(host)) {
            return null;
        }

        host = host.trim().toLowerCase();
        if (!Pattern.matches('^[a-z0-9.-]+(:[0-9]+)?$', host)) {
            return null;
        }

        String pathPrefix = Site.getPathPrefix();
        String baseUrl = 'https://' + host;
        if (String.isNotBlank(pathPrefix)) {
            String normalizedPrefix = pathPrefix.trim();
            while (normalizedPrefix.startsWith('/')) {
                normalizedPrefix = normalizedPrefix.substring(1);
            }
            while (normalizedPrefix.endsWith('/')) {
                normalizedPrefix = normalizedPrefix.substring(0, normalizedPrefix.length() - 1);
            }
            if (String.isNotBlank(normalizedPrefix)) {
                baseUrl += '/' + normalizedPrefix;
            }
        }
        return baseUrl;
    }

    private static String buildFileBaseName(String projectName) {
        String cleanName = String.isBlank(projectName)
            ? DEFAULT_FORM_TITLE
            : projectName.replaceAll('[^A-Za-z0-9 _.-]', '').trim();
        if (String.isBlank(cleanName)) {
            cleanName = DEFAULT_FORM_TITLE;
        }
        return DEFAULT_FORM_TITLE + ' - ' + cleanName;
    }

    private static String ensureContentDistributionId(Id contentVersionId, String distributionName) {
        if (contentVersionId == null) {
            return '';
        }

        try {
            List<ContentDistribution> existingDistributions = [
                SELECT Id
                FROM ContentDistribution
                WHERE ContentVersionId = :contentVersionId
                LIMIT 1
            ];
            if (!existingDistributions.isEmpty()) {
                return String.valueOf(existingDistributions[0].Id);
            }

            ContentDistribution distribution = new ContentDistribution();
            distribution.Name = String.isBlank(distributionName) ? DEFAULT_FORM_TITLE : distributionName;
            distribution.ContentVersionId = contentVersionId;
            distribution.PreferencesAllowViewInBrowser = true;
            distribution.PreferencesLinkLatestVersion = true;
            distribution.PreferencesNotifyOnVisit = false;
            distribution.PreferencesPasswordRequired = false;
            distribution.PreferencesAllowOriginalDownload = true;
            insert distribution;

            return String.valueOf(distribution.Id);
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'ProjectCompletionFormController.ensureContentDistributionId failed for contentVersionId='
                    + contentVersionId
                    + ': '
                    + ex.getMessage()
            );
            return '';
        }
    }

    private static String blankToEmpty(String value) {
        return String.isBlank(value) ? '' : value;
    }

    private static Schema.SObjectField getProjectField(String fieldApiName) {
        return buildertek__Project__c.SObjectType.getDescribe().fields.getMap().get(fieldApiName);
    }

    private static String getRecordIdParameter() {
        Map<String, String> parameters = ApexPages.currentPage().getParameters();
        for (String parameterName : new List<String>{ 'Id', 'id', 'recordId', 'projectId' }) {
            if (String.isNotBlank(parameters.get(parameterName))) {
                return parameters.get(parameterName);
            }
        }
        return null;
    }

    private class ProjectSnapshot {
        Id recordId;
        String projectName;
        String signId;
        SObject customerContact;
        SObject siteContact;
    }

    private class PdfImageReference {
        String contentVersionId = '';
        String contentDocumentId = '';
        String contentDistributionId = '';
    }
}