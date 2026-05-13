public with sharing class ProjectCompletionEmailCtrl {
    private static final String SIGN_FIELD_API_NAME = 'Project_Completion_Sign_Id__c';
    private static final String PROJECT_CONFIGURATION_NAME = 'Project Configuration';
    private static final String BODY_TEMPLATE_DEVELOPER_NAME = 'Project_Form_Email';
    private static final String ATTACHMENT_TEMPLATE_DEVELOPER_NAME = 'Project_Completion_Form';
    private static final String ATTACHMENT_TEMPLATE_NAME = 'Project Completion Form';
    private static final String DEFAULT_FORM_TITLE = 'Project Completion Form';

    @AuraEnabled(cacheable=true)
    public static InitialState getInitialState(Id projectId) {
        validateProjectId(projectId);

        ProjectSnapshot projectSnapshot = loadProject(projectId, false);

        InitialState state = new InitialState();
        state.projectId = projectSnapshot.recordId;
        state.projectName = projectSnapshot.projectName;
        state.configurationError = getConfigurationError();
        state.defaultSelectedContact = getDefaultContacts(projectSnapshot);
        state.defaultToAddress = state.defaultSelectedContact.isEmpty()
            ? ''
            : state.defaultSelectedContact[0].Email;
        state.defaultFromAddress = getDefaultFromAddress();
        state.defaultEmailTemplate = ATTACHMENT_TEMPLATE_NAME;
        state.defaultSubject = getDefaultProjectSubject(projectSnapshot.projectName);
        state.bodyTemplateQuery = buildBodyTemplateQuery();
        state.attachmentTemplateQuery = buildAttachmentTemplateQuery();
        state.signedPdfName = buildFileBaseName(projectSnapshot.projectName) + '.pdf';
        return state;
    }

    private static void validateProjectId(Id projectId) {
        if (projectId == null || projectId.getSObjectType() != buildertek__Project__c.SObjectType) {
            throw new AuraHandledException('The selected record is not a valid BT Project.');
        }
    }

    private static ProjectSnapshot loadProject(Id projectId, Boolean lockRow) {
        String selectClause =
            'SELECT Id, Name, buildertek__Customer_Contact__c, buildertek__Customer_Contact__r.Name, '
            + 'buildertek__Customer_Contact__r.Email, buildertek__Customer_Contact__r.Phone, '
            + 'buildertek__Site_Contact__c, buildertek__Site_Contact__r.Name, '
            + 'buildertek__Site_Contact__r.Email, buildertek__Site_Contact__r.Phone';

        String query = selectClause
            + ' FROM buildertek__Project__c WHERE Id = :projectId'
            + (lockRow ? ' FOR UPDATE' : '');

        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            throw new AuraHandledException('The selected record is not a valid BT Project.');
        }

        SObject projectRecord = records[0];
        ProjectSnapshot snapshot = new ProjectSnapshot();
        snapshot.recordId = (Id) projectRecord.get('Id');
        snapshot.projectName = (String) projectRecord.get('Name');

        SObject customerContact = projectRecord.getSObject('buildertek__Customer_Contact__r');
        SObject siteContact = projectRecord.getSObject('buildertek__Site_Contact__r');
        snapshot.defaultContact = getContactResult(customerContact);
        if (snapshot.defaultContact == null || String.isBlank(snapshot.defaultContact.Email)) {
            snapshot.defaultContact = getContactResult(siteContact);
        }

        return snapshot;
    }

    private static String getConfigurationError() {
        if (getProjectField(SIGN_FIELD_API_NAME) == null) {
            return 'Create buildertek__Project__c.Project_Completion_Sign_Id__c before enabling the Project Preview and Email action.';
        }
        if (!Test.isRunningTest() && !visualforceEmailTemplateExists(BODY_TEMPLATE_DEVELOPER_NAME)) {
            return 'Deploy and activate the Visualforce Project_Form_Email email template before using Project Preview and Email.';
        }
        if (!Test.isRunningTest() && !visualforceEmailTemplateExists(ATTACHMENT_TEMPLATE_DEVELOPER_NAME)) {
            return 'Deploy and activate the Visualforce Project_Completion_Form email template before using Project Preview and Email.';
        }
        return '';
    }

    private static Boolean visualforceEmailTemplateExists(String developerName) {
        return [
            SELECT COUNT()
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            AND IsActive = true
            AND TemplateType = 'visualforce'
        ] > 0;
    }

    private static List<ContactResult> getDefaultContacts(ProjectSnapshot projectSnapshot) {
        List<ContactResult> contacts = new List<ContactResult>();
        if (projectSnapshot.defaultContact != null && String.isNotBlank(projectSnapshot.defaultContact.Email)) {
            contacts.add(projectSnapshot.defaultContact);
        }
        return contacts;
    }

    private static ContactResult getContactResult(SObject contactRecord) {
        if (contactRecord == null) {
            return null;
        }

        ContactResult result = new ContactResult();
        result.Id = (Id) contactRecord.get('Id');
        result.Name = (String) contactRecord.get('Name');
        result.Email = (String) contactRecord.get('Email');
        return result;
    }

    private static String getDefaultProjectSubject(String projectName) {
        List<buildertek__Admin_Interface_Node_Configuration__c> configs = [
            SELECT buildertek__Email_Subject__c
            FROM buildertek__Admin_Interface_Node_Configuration__c
            WHERE Name = :PROJECT_CONFIGURATION_NAME
            LIMIT 1
        ];

        if (!configs.isEmpty() && String.isNotBlank(configs[0].buildertek__Email_Subject__c)) {
            return configs[0].buildertek__Email_Subject__c;
        }
        return DEFAULT_FORM_TITLE;
    }

    private static String getDefaultFromAddress() {
        List<buildertek__Admin_Interface_Node_Configuration__c> configs = [
            SELECT buildertek__Default_From_Address_For_Email__c
            FROM buildertek__Admin_Interface_Node_Configuration__c
            WHERE Name = :PROJECT_CONFIGURATION_NAME
            LIMIT 1
        ];

        return configs.isEmpty()
            ? ''
            : configs[0].buildertek__Default_From_Address_For_Email__c;
    }

    private static String buildBodyTemplateQuery() {
        return 'SELECT Id, Name, Subject, HtmlValue, Body, DeveloperName '
            + 'FROM EmailTemplate '
            + 'WHERE DeveloperName = \'' + BODY_TEMPLATE_DEVELOPER_NAME + '\' '
            + 'AND IsActive = true '
            + 'LIMIT 1';
    }

    private static String buildAttachmentTemplateQuery() {
        return 'SELECT Id, Name, Subject, HtmlValue, Body, DeveloperName '
            + 'FROM EmailTemplate '
            + 'WHERE DeveloperName = \'' + ATTACHMENT_TEMPLATE_DEVELOPER_NAME + '\' '
            + 'AND IsActive = true '
            + 'LIMIT 1';
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

    private static Schema.SObjectField getProjectField(String fieldApiName) {
        return buildertek__Project__c.SObjectType.getDescribe().fields.getMap().get(fieldApiName);
    }

    private class ProjectSnapshot {
        Id recordId;
        String projectName;
        ContactResult defaultContact;
    }

    public class InitialState {
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String configurationError { get; set; }
        @AuraEnabled public List<ContactResult> defaultSelectedContact { get; set; }
        @AuraEnabled public String defaultToAddress { get; set; }
        @AuraEnabled public String defaultFromAddress { get; set; }
        @AuraEnabled public String defaultEmailTemplate { get; set; }
        @AuraEnabled public String defaultSubject { get; set; }
        @AuraEnabled public String bodyTemplateQuery { get; set; }
        @AuraEnabled public String attachmentTemplateQuery { get; set; }
        @AuraEnabled public String signedPdfName { get; set; }
    }

    public class ContactResult {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public String Email { get; set; }
    }
}