public with sharing class PurchaseOrderPreviewEmailCtrl {
    private static final String CONFIGURATION_NAME = 'Project Configuration';
    private static final String BODY_TEMPLATE_DEVELOPER_NAME = 'PurchaseOrderBodyTemplateV2';
    private static final String ATTACHMENT_TEMPLATE_DEVELOPER_NAME = 'Purchase_Order_Template_1';
    private static final String ATTACHMENT_TEMPLATE_NAME = 'Purchase Order Template';
    private static final String DEFAULT_FORM_TITLE = 'Purchase Order Template';

    @AuraEnabled
    public static InitialState getInitialState(Id purchaseOrderId) {
        validatePurchaseOrderId(purchaseOrderId);

        PurchaseOrderSnapshot purchaseOrderSnapshot = loadPurchaseOrder(purchaseOrderId);
        Boolean bodyTemplateExists = visualforceEmailTemplateExists(BODY_TEMPLATE_DEVELOPER_NAME);
        Boolean attachmentTemplateExists = visualforceEmailTemplateExists(ATTACHMENT_TEMPLATE_DEVELOPER_NAME);

        InitialState state = new InitialState();
        state.purchaseOrderId = purchaseOrderSnapshot.recordId;
        state.purchaseOrderName = purchaseOrderSnapshot.purchaseOrderName;
        state.configurationError = '';
        state.defaultSelectedContact = new List<ContactResult>();
        state.defaultToAddress = '';
        state.defaultFromAddress = getDefaultFromAddress();
        state.defaultEmailTemplate = getDefaultEmailTemplateName(attachmentTemplateExists);
        state.defaultSubject = getDefaultSubject();
        state.bodyTemplateQuery = buildBodyTemplateQuery(bodyTemplateExists);
        state.attachmentTemplateQuery = buildAttachmentTemplateQuery(attachmentTemplateExists);
        state.signedPdfName = buildFileBaseName(purchaseOrderSnapshot.purchaseOrderName) + '.pdf';
        return state;
    }

    private static void validatePurchaseOrderId(Id purchaseOrderId) {
        if (purchaseOrderId == null || purchaseOrderId.getSObjectType() != buildertek__Purchase_Order__c.SObjectType) {
            throw new AuraHandledException('The selected record is not a valid Purchase Order.');
        }
    }

    private static PurchaseOrderSnapshot loadPurchaseOrder(Id purchaseOrderId) {
        List<buildertek__Purchase_Order__c> purchaseOrders = [
            SELECT Id, Name
            FROM buildertek__Purchase_Order__c
            WHERE Id = :purchaseOrderId
            LIMIT 1
        ];

        if (purchaseOrders.isEmpty()) {
            throw new AuraHandledException('The selected record is not a valid Purchase Order.');
        }

        buildertek__Purchase_Order__c purchaseOrder = purchaseOrders[0];

        PurchaseOrderSnapshot snapshot = new PurchaseOrderSnapshot();
        snapshot.recordId = purchaseOrder.Id;
        snapshot.purchaseOrderName = purchaseOrder.Name;
        return snapshot;
    }

    private static Boolean visualforceEmailTemplateExists(String developerName) {
        Integer templateCount = [
            SELECT COUNT()
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            AND IsActive = true
            AND TemplateType = 'visualforce'
        ];
        Boolean exists = templateCount > 0;
        return exists;
    }

    private static String getDefaultFromAddress() {
        List<buildertek__Admin_Interface_Node_Configuration__c> configs = [
            SELECT buildertek__Default_From_Address_For_Email__c
            FROM buildertek__Admin_Interface_Node_Configuration__c
            WHERE Name = :CONFIGURATION_NAME
            LIMIT 1
        ];

        String defaultFromAddress = '';
        if (!configs.isEmpty()) {
            defaultFromAddress = configs[0].buildertek__Default_From_Address_For_Email__c;
        }
        return defaultFromAddress;
    }

    private static String getDefaultSubject() {
        String defaultSubject = DEFAULT_FORM_TITLE;
        return defaultSubject;
    }

    private static String getDefaultEmailTemplateName(Boolean attachmentTemplateExists) {
        String defaultEmailTemplateName = '';
        if (attachmentTemplateExists) {
            defaultEmailTemplateName = ATTACHMENT_TEMPLATE_NAME;
        }
        return defaultEmailTemplateName;
    }

    private static String buildBodyTemplateQuery(Boolean bodyTemplateExists) {
        if (!bodyTemplateExists) {
            String emptyQuery = '';
            return emptyQuery;
        }

        String templateQuery = 'SELECT Id, Name, Subject, HtmlValue, Body, DeveloperName '
            + 'FROM EmailTemplate '
            + 'WHERE DeveloperName = \'' + BODY_TEMPLATE_DEVELOPER_NAME + '\' '
            + 'AND IsActive = true '
            + 'LIMIT 1';
        return templateQuery;
    }

    private static String buildAttachmentTemplateQuery(Boolean attachmentTemplateExists) {
        if (!attachmentTemplateExists) {
            String emptyQuery = '';
            return emptyQuery;
        }

        String templateQuery = 'SELECT Id, Name, Subject, HtmlValue, Body, DeveloperName '
            + 'FROM EmailTemplate '
            + 'WHERE DeveloperName = \'' + ATTACHMENT_TEMPLATE_DEVELOPER_NAME + '\' '
            + 'AND IsActive = true '
            + 'LIMIT 1';
        return templateQuery;
    }

    private static String buildFileBaseName(String purchaseOrderName) {
        String cleanName = purchaseOrderName;
        if (String.isBlank(cleanName)) {
            cleanName = DEFAULT_FORM_TITLE;
        } else {
            cleanName = cleanName.replaceAll('[^A-Za-z0-9 _.-]', '').trim();
        }
        if (String.isBlank(cleanName)) {
            cleanName = DEFAULT_FORM_TITLE;
        }

        String fileBaseName = DEFAULT_FORM_TITLE + ' - ' + cleanName;
        return fileBaseName;
    }

    private class PurchaseOrderSnapshot {
        Id recordId;
        String purchaseOrderName;
    }

    public class InitialState {
        @AuraEnabled public Id purchaseOrderId { get; set; }
        @AuraEnabled public String purchaseOrderName { get; set; }
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
