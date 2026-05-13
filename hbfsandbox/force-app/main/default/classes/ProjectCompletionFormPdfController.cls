// PDF rendering may be invoked after public site signing and needs direct access to the BT Project/files.
public without sharing class ProjectCompletionFormPdfController {
    private static final String SIGN_FIELD_API_NAME = 'Project_Completion_Sign_Id__c';

    public String projectName { get; private set; }
    public String signerName { get; private set; }
    public String signerEmail { get; private set; }
    public String signerPhone { get; private set; }
    public String signatureVersionId { get; private set; }
    public String signatureDocumentId { get; private set; }
    public String signatureDistributionId { get; private set; }
    public Date signedDate { get; private set; }
    private String signatureImageUrl;

    public ProjectCompletionFormPdfController() {
        Map<String, String> parameters = ApexPages.currentPage().getParameters();
        Id projectId = (Id) parameters.get('Id');
        signatureVersionId = parameters.get('signatureVersionId');
        signatureDocumentId = parameters.get('signatureDocumentId');
        signatureDistributionId = parameters.get('signatureDistributionId');
        loadProject(projectId);
        signatureDocumentId = resolveContentDocumentId(signatureVersionId, signatureDocumentId);
    }

    public Boolean getHasSignature() {
        return String.isNotBlank(getSignatureImageUrl());
    }

    public String getSignatureImageUrl() {
        if (signatureImageUrl == null) {
            signatureImageUrl = resolveImageUrl(
                signatureDistributionId,
                signatureVersionId,
                signatureDocumentId
            );
        }
        return signatureImageUrl;
    }

    public String getSignedDateDisplay() {
        Date dateToDisplay = signedDate == null ? Date.today() : signedDate;
        return DateTime.newInstance(dateToDisplay.year(), dateToDisplay.month(), dateToDisplay.day()).format('MM/dd/yyyy');
    }

    private void loadProject(Id projectId) {
        String selectClause =
            'SELECT Id, Name, buildertek__Project_Completion_Date__c, '
            + 'buildertek__Customer_Contact__r.Name, buildertek__Customer_Contact__r.Email, '
            + 'buildertek__Customer_Contact__r.Phone, buildertek__Site_Contact__r.Name, '
            + 'buildertek__Site_Contact__r.Email, buildertek__Site_Contact__r.Phone';

        if (getProjectField(SIGN_FIELD_API_NAME) != null) {
            selectClause += ', ' + SIGN_FIELD_API_NAME;
        }

        List<SObject> projects = Database.query(selectClause + ' FROM buildertek__Project__c WHERE Id = :projectId LIMIT 1');
        if (projects.isEmpty()) {
            return;
        }

        SObject projectRecord = projects[0];
        projectName = (String) projectRecord.get('Name');
        signedDate = (Date) projectRecord.get('buildertek__Project_Completion_Date__c');

        if (String.isBlank(signatureVersionId) && getProjectField(SIGN_FIELD_API_NAME) != null) {
            signatureVersionId = (String) projectRecord.get(SIGN_FIELD_API_NAME);
        }

        SObject contactRecord = projectRecord.getSObject('buildertek__Customer_Contact__r');
        if (contactRecord == null || String.isBlank((String) contactRecord.get('Email'))) {
            contactRecord = projectRecord.getSObject('buildertek__Site_Contact__r');
        }

        signerName = contactRecord == null ? '' : (String) contactRecord.get('Name');
        signerEmail = contactRecord == null ? '' : (String) contactRecord.get('Email');
        signerPhone = contactRecord == null ? '' : (String) contactRecord.get('Phone');
    }

    private static Schema.SObjectField getProjectField(String fieldApiName) {
        return buildertek__Project__c.SObjectType.getDescribe().fields.getMap().get(fieldApiName);
    }

    @TestVisible
    private static String resolveImageUrl(
        String contentDistributionId,
        String contentVersionId,
        String contentDocumentId
    ) {
        String distributionDownloadUrl = loadContentDistributionDownloadUrl(contentDistributionId);
        if (String.isNotBlank(distributionDownloadUrl)) {
            return distributionDownloadUrl;
        }

        return buildSalesforceFileDownloadUrl(contentVersionId, contentDocumentId);
    }

    @TestVisible
    private static String loadContentDistributionDownloadUrl(String contentDistributionId) {
        Id parsedId = parseId(contentDistributionId, ContentDistribution.SObjectType);
        if (parsedId == null) {
            return '';
        }

        List<ContentDistribution> distributions = [
            SELECT ContentDownloadUrl
            FROM ContentDistribution
            WHERE Id = :parsedId
            LIMIT 1
        ];
        if (distributions.isEmpty() || String.isBlank(distributions[0].ContentDownloadUrl)) {
            return '';
        }

        return distributions[0].ContentDownloadUrl;
    }

    @TestVisible
    private static String resolveContentDocumentId(String contentVersionId, String contentDocumentId) {
        if (parseId(contentDocumentId, ContentDocument.SObjectType) != null) {
            return contentDocumentId;
        }

        Id versionId = parseId(contentVersionId, ContentVersion.SObjectType);
        if (versionId == null) {
            return '';
        }

        List<ContentVersion> versions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return '';
        }

        return String.valueOf(versions[0].ContentDocumentId);
    }

    @TestVisible
    private static String buildSalesforceFileDownloadUrl(String contentVersionId, String contentDocumentId) {
        Id documentId = parseId(contentDocumentId, ContentDocument.SObjectType);
        if (documentId != null) {
            return '/sfc/servlet.shepherd/document/download/' + String.valueOf(documentId);
        }

        Id versionId = parseId(contentVersionId, ContentVersion.SObjectType);
        return versionId == null
            ? ''
            : '/sfc/servlet.shepherd/version/download/' + String.valueOf(versionId);
    }

    private static Id parseId(String candidateId, Schema.SObjectType expectedType) {
        if (String.isBlank(candidateId)) {
            return null;
        }

        try {
            Id parsedId = (Id) candidateId;
            return parsedId.getSObjectType() == expectedType ? parsedId : null;
        } catch (Exception ex) {
            return null;
        }
    }
}