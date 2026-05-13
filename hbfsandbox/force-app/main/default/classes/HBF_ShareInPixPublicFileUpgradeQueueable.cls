public without sharing class HBF_ShareInPixPublicFileUpgradeQueueable implements Queueable, Database.AllowsCallouts {
    /*
     * Purpose:
     * Upgrade ShareInPix-backed buildertek__Public_File__c records from raw external
     * URLs into Salesforce File + ContentDistribution backed records.
     *
     * Why this exists:
     * ShareInPix image URLs in this org respond with Content-Disposition=attachment,
     * so a browser click tends to download instead of opening inline.
     * Buildertek's public-file experience already works well with
     * ContentDistribution.DistributionPublicUrl, so this job converts the image
     * into that model without blocking RFQ creation.
     *
     * Design goals:
     * 1. Run asynchronously so Create RFQ never waits on callouts.
     * 2. Fail soft per image and keep processing the rest.
     * 3. Reuse existing buildertek__Public_File__c rows when present.
     * 4. Only upgrade ShareInPix-backed files that do not already have a
     *    Content Version / Content Distribution attached.
     */

    private final List<Id> imageIds;

    public HBF_ShareInPixPublicFileUpgradeQueueable(List<Id> imageIds) {
        this.imageIds = new List<Id>();
        if (imageIds != null) {
            this.imageIds.addAll(imageIds);
        }
    }

    public void execute(QueueableContext context) {
        if (imageIds.isEmpty()) {
            return;
        }

        try {
            List<ShareInPixImageRow> images = loadImages();
            if (images.isEmpty()) {
                System.debug(LoggingLevel.DEBUG,
                    'HBF_ShareInPixPublicFileUpgradeQueueable: no ShareInPix images found to upgrade.');
                return;
            }

            Map<String, buildertek__Public_File__c> publicFilesByName = loadExistingPublicFiles(images);
            List<ImageUpgradeWorkItem> workItems = buildWorkItems(images, publicFilesByName);
            if (workItems.isEmpty()) {
                System.debug(LoggingLevel.DEBUG,
                    'HBF_ShareInPixPublicFileUpgradeQueueable: no Public Files need browser-view upgrades.');
                return;
            }

            createContentVersions(workItems);
            createContentDistributions(workItems);
            upsertPublicFiles(workItems);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HBF_ShareInPixPublicFileUpgradeQueueable: unexpected error. Message=' +
                ex.getMessage() + ' line=' + ex.getLineNumber());
        }
    }

    private List<ShareInPixImageRow> loadImages() {
        Schema.SObjectType sharinPixType = Schema.getGlobalDescribe().get('sharinpix__SharinPixImage__c');
        if (sharinPixType == null) {
            return new List<ShareInPixImageRow>();
        }

        Map<String, Schema.SObjectField> fieldMap = sharinPixType.getDescribe().fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'Name', 'sharinpix__ImageURLFull__c' };
        if (fieldMap.containsKey('sharinpix__ImageURLOriginal__c')) {
            selectFields.add('sharinpix__ImageURLOriginal__c');
        }
        if (fieldMap.containsKey('sharinpix__FileName__c')) {
            selectFields.add('sharinpix__FileName__c');
        }
        if (fieldMap.containsKey('sharinpix__Format__c')) {
            selectFields.add('sharinpix__Format__c');
        }

        String query =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM sharinpix__SharinPixImage__c WHERE Id IN :imageIds';

        List<ShareInPixImageRow> results = new List<ShareInPixImageRow>();
        for (SObject row : Database.query(query)) {
            ShareInPixImageRow image = new ShareInPixImageRow();
            image.imageId = (Id) row.get('Id');
            image.imageName = (String) row.get('Name');
            image.fullUrl = (String) row.get('sharinpix__ImageURLFull__c');
            image.originalUrl = fieldMap.containsKey('sharinpix__ImageURLOriginal__c')
                ? (String) row.get('sharinpix__ImageURLOriginal__c')
                : null;
            image.fileName = fieldMap.containsKey('sharinpix__FileName__c')
                ? (String) row.get('sharinpix__FileName__c')
                : null;
            image.format = fieldMap.containsKey('sharinpix__Format__c')
                ? (String) row.get('sharinpix__Format__c')
                : null;
            results.add(image);
        }
        return results;
    }

    private Map<String, buildertek__Public_File__c> loadExistingPublicFiles(List<ShareInPixImageRow> images) {
        Set<String> publicFileNames = new Set<String>();
        for (ShareInPixImageRow image : images) {
            publicFileNames.add(buildPublicFileName(image));
        }

        Map<String, buildertek__Public_File__c> publicFilesByName = new Map<String, buildertek__Public_File__c>();
        if (publicFileNames.isEmpty()) {
            return publicFilesByName;
        }

        for (buildertek__Public_File__c publicFile : [
            SELECT Id, buildertek__File_Name__c, buildertek__Public_URL__c,
                   buildertek__Content_Distrubution__c, buildertek__Content_Version__c
            FROM buildertek__Public_File__c
            WHERE buildertek__File_Name__c IN :publicFileNames
        ]) {
            publicFilesByName.put(publicFile.buildertek__File_Name__c, publicFile);
        }

        return publicFilesByName;
    }

    private List<ImageUpgradeWorkItem> buildWorkItems(
        List<ShareInPixImageRow> images,
        Map<String, buildertek__Public_File__c> publicFilesByName
    ) {
        List<ImageUpgradeWorkItem> workItems = new List<ImageUpgradeWorkItem>();
        for (ShareInPixImageRow image : images) {
            String publicFileName = buildPublicFileName(image);
            buildertek__Public_File__c existingPublicFile = publicFilesByName.get(publicFileName);
            if (existingPublicFile == null) {
                continue;
            }

            if (!String.isBlank(existingPublicFile.buildertek__Content_Version__c) &&
                !String.isBlank(existingPublicFile.buildertek__Content_Distrubution__c) &&
                !String.isBlank(existingPublicFile.buildertek__Public_URL__c) &&
                !existingPublicFile.buildertek__Public_URL__c.contains('p.sharinpix.com/')) {
                continue;
            }

            String sourceUrl = chooseBestSourceUrl(image);
            if (String.isBlank(sourceUrl)) {
                continue;
            }

            ImageUpgradeWorkItem workItem = new ImageUpgradeWorkItem();
            workItem.image = image;
            workItem.publicFile = existingPublicFile;
            workItem.sourceUrl = sourceUrl;
            workItem.publicFileName = publicFileName;
            workItems.add(workItem);
        }
        return workItems;
    }

    private void createContentVersions(List<ImageUpgradeWorkItem> workItems) {
        List<ContentVersion> versionsToInsert = new List<ContentVersion>();
        List<ImageUpgradeWorkItem> readyForVersionInsert = new List<ImageUpgradeWorkItem>();

        for (ImageUpgradeWorkItem workItem : workItems) {
            try {
                HttpRequest request = new HttpRequest();
                request.setEndpoint(workItem.sourceUrl);
                request.setMethod('GET');
                request.setTimeout(20000);

                HttpResponse response = new Http().send(request);
                if (response.getStatusCode() != 200 || response.getBodyAsBlob() == null) {
                    System.debug(LoggingLevel.WARN,
                        'HBF_ShareInPixPublicFileUpgradeQueueable: unable to fetch image ' +
                        workItem.image.imageId + '. Status=' + response.getStatusCode());
                    continue;
                }

                String extension = determineExtension(workItem, response);
                ContentVersion versionRecord = new ContentVersion();
                versionRecord.Title = buildContentTitle(workItem.image);
                versionRecord.PathOnClient = buildPathOnClient(workItem, extension);
                versionRecord.VersionData = response.getBodyAsBlob();
                versionsToInsert.add(versionRecord);
                readyForVersionInsert.add(workItem);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'HBF_ShareInPixPublicFileUpgradeQueueable: callout failed for image ' +
                    workItem.image.imageId + '. Message=' + ex.getMessage());
            }
        }

        if (versionsToInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults = Database.insert(versionsToInsert, false);
        logSaveResults('ContentVersion inserts', saveResults);

        for (Integer index = 0; index < saveResults.size(); index++) {
            if (!saveResults[index].isSuccess()) {
                continue;
            }
            readyForVersionInsert[index].contentVersionId = saveResults[index].getId();
        }
    }

    private void createContentDistributions(List<ImageUpgradeWorkItem> workItems) {
        List<ContentDistribution> distributionsToInsert = new List<ContentDistribution>();
        List<ImageUpgradeWorkItem> readyForDistributionInsert = new List<ImageUpgradeWorkItem>();

        for (ImageUpgradeWorkItem workItem : workItems) {
            if (workItem.contentVersionId == null) {
                continue;
            }

            ContentDistribution distribution = new ContentDistribution();
            distribution.Name = buildContentTitle(workItem.image);
            distribution.ContentVersionId = workItem.contentVersionId;
            distribution.PreferencesAllowViewInBrowser = true;
            distribution.PreferencesLinkLatestVersion = true;
            distribution.PreferencesNotifyOnVisit = false;
            distribution.PreferencesPasswordRequired = false;
            distribution.PreferencesAllowOriginalDownload = true;
            distributionsToInsert.add(distribution);
            readyForDistributionInsert.add(workItem);
        }

        if (distributionsToInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults = Database.insert(distributionsToInsert, false);
        logSaveResults('ContentDistribution inserts', saveResults);

        Set<Id> distributionIds = new Set<Id>();
        for (Integer index = 0; index < saveResults.size(); index++) {
            if (!saveResults[index].isSuccess()) {
                continue;
            }
            Id distributionId = saveResults[index].getId();
            readyForDistributionInsert[index].contentDistributionId = distributionId;
            distributionIds.add(distributionId);
        }

        if (distributionIds.isEmpty()) {
            return;
        }

        Map<Id, ContentDistribution> distributionsById = new Map<Id, ContentDistribution>([
            SELECT Id, DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id IN :distributionIds
        ]);

        for (ImageUpgradeWorkItem workItem : readyForDistributionInsert) {
            if (workItem.contentDistributionId == null || !distributionsById.containsKey(workItem.contentDistributionId)) {
                continue;
            }
            workItem.browserFriendlyUrl = distributionsById.get(workItem.contentDistributionId).DistributionPublicUrl;
        }
    }

    private void upsertPublicFiles(List<ImageUpgradeWorkItem> workItems) {
        List<buildertek__Public_File__c> publicFilesToUpdate = new List<buildertek__Public_File__c>();

        for (ImageUpgradeWorkItem workItem : workItems) {
            if (workItem.publicFile == null ||
                workItem.contentVersionId == null ||
                workItem.contentDistributionId == null ||
                String.isBlank(workItem.browserFriendlyUrl)) {
                continue;
            }

            publicFilesToUpdate.add(new buildertek__Public_File__c(
                Id = workItem.publicFile.Id,
                buildertek__Content_Version__c = String.valueOf(workItem.contentVersionId),
                buildertek__Content_Distrubution__c = String.valueOf(workItem.contentDistributionId),
                buildertek__Public_URL__c = workItem.browserFriendlyUrl,
                buildertek__Skip_Validation__c = true
            ));
        }

        if (publicFilesToUpdate.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults = Database.update(publicFilesToUpdate, false);
        logSaveResults('buildertek__Public_File__c browser-link updates', saveResults);
    }

    private static String chooseBestSourceUrl(ShareInPixImageRow image) {
        if (!String.isBlank(image.originalUrl)) {
            return image.originalUrl.trim();
        }
        if (!String.isBlank(image.fullUrl)) {
            return image.fullUrl.trim();
        }
        return null;
    }

    private static String buildPublicFileName(ShareInPixImageRow image) {
        String baseName = String.isBlank(image.imageName) ? 'ShareInPix Image' : image.imageName.trim();
        String uniqueName = baseName + ' ' + image.imageId;
        return uniqueName.length() > 255 ? uniqueName.substring(0, 255) : uniqueName;
    }

    private static String buildContentTitle(ShareInPixImageRow image) {
        String title = String.isBlank(image.imageName) ? 'ShareInPix Image' : image.imageName.trim();
        return title.length() > 255 ? title.substring(0, 255) : title;
    }

    private static String buildPathOnClient(ImageUpgradeWorkItem workItem, String extension) {
        String baseName = String.isBlank(workItem.image.fileName) ? buildContentTitle(workItem.image) : workItem.image.fileName.trim();
        String safeBaseName = baseName.replaceAll('[^A-Za-z0-9._ -]', '_');
        if (String.isBlank(extension)) {
            extension = 'jpg';
        }
        String path = safeBaseName + '.' + extension;
        return path.length() > 500 ? path.substring(0, 500) : path;
    }

    private static String determineExtension(ImageUpgradeWorkItem workItem, HttpResponse response) {
        if (!String.isBlank(workItem.image.format)) {
            return workItem.image.format.trim().toLowerCase();
        }

        String contentType = response.getHeader('Content-Type');
        if (!String.isBlank(contentType)) {
            String lowered = contentType.toLowerCase();
            if (lowered.contains('png')) {
                return 'png';
            }
            if (lowered.contains('jpeg') || lowered.contains('jpg')) {
                return 'jpg';
            }
            if (lowered.contains('webp')) {
                return 'webp';
            }
            if (lowered.contains('gif')) {
                return 'gif';
            }
        }

        return 'jpg';
    }

    private static void logSaveResults(String stageName, Database.SaveResult[] saveResults) {
        Integer successCount = 0;
        Integer errorCount = 0;
        List<String> errorMessages = new List<String>();

        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                successCount++;
                continue;
            }

            errorCount++;
            for (Database.Error singleError : saveResult.getErrors()) {
                errorMessages.add(singleError.getStatusCode() + ': ' + singleError.getMessage());
            }
        }

        System.debug(LoggingLevel.DEBUG,
            'HBF_ShareInPixPublicFileUpgradeQueueable [' + stageName + '] successes=' +
            successCount + ' errors=' + errorCount);

        if (!errorMessages.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'HBF_ShareInPixPublicFileUpgradeQueueable [' + stageName + '] error details=' +
                String.join(errorMessages, ' | '));
        }
    }

    private class ShareInPixImageRow {
        Id imageId;
        String imageName;
        String fileName;
        String format;
        String fullUrl;
        String originalUrl;
    }

    private class ImageUpgradeWorkItem {
        ShareInPixImageRow image;
        buildertek__Public_File__c publicFile;
        String publicFileName;
        String sourceUrl;
        Id contentVersionId;
        Id contentDistributionId;
        String browserFriendlyUrl;
    }
}