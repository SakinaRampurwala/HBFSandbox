public without sharing class HBF_CreateRFQShareInPixHandler {
    /*
     * This handler is intentionally narrow.
     * It does not try to replace Buildertek's RFQ creation or file-copy logic.
     * It only fills the custom gap needed to make the packaged Create RFQ flow
     * behave like the Acts custom flow for ShareInPix-backed walkthrough images.
     *
     * Design goals:
     * 1. Never block RFQ line insert/update if ShareInPix automation has a problem.
     * 2. Only run when an RFQ Item is linked back to a walkthrough line.
     * 3. Update ShareInPix image linkage (BT_RFQ_Lines__c) when those fields exist.
     * 4. Create/reuse Public File records for ShareInPix image URLs.
     * 5. Create missing Public File Folder junctions once the RFQ line folder exists.
     */

    private static Boolean isRunning = false;
    private static Boolean browserUpgradeQueued = false;
    private static final String SHARINPIX_OBJECT_API_NAME = 'sharinpix__SharinPixImage__c';
    private static final String SHARINPIX_ALBUM_FIELD = 'sharinpix__AlbumID__c';
    private static final String SHARINPIX_IMAGE_URL_FIELD = 'sharinpix__ImageURLFull__c';
    private static final String SHARINPIX_WT_LINE_FIELD = 'BT_Walk_Through_Line_Item__c';
    private static final String SHARINPIX_RFQ_LINE_FIELD = 'BT_RFQ_Lines__c';

    public static void handleAfterInsert(List<buildertek__RFQ_Item__c> newRecords) {
        processRecords(newRecords, null);
    }

    public static void handleAfterUpdate(
        List<buildertek__RFQ_Item__c> newRecords,
        Map<Id, buildertek__RFQ_Item__c> oldMap
    ) {
        processRecords(newRecords, oldMap);
    }

    private static void processRecords(
        List<buildertek__RFQ_Item__c> newRecords,
        Map<Id, buildertek__RFQ_Item__c> oldMap
    ) {
        if (isRunning || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        isRunning = true;
        try {
            Map<Id, buildertek__RFQ_Item__c> candidatesById = collectCandidates(newRecords, oldMap);
            if (candidatesById.isEmpty()) {
                System.debug(LoggingLevel.DEBUG,
                    'HBF_CreateRFQShareInPixHandler: no RFQ Items qualified for ShareInPix sync.');
                return;
            }

            /*
             * Stage 1:
             * Update BT_RFQ_Lines__c on ShareInPix images so the image records point
             * back to the RFQ Item created by the packaged button.
             * This stage is automatically skipped in orgs where the custom fields
             * do not exist on sharinpix__SharinPixImage__c.
             */
            syncShareInPixImageLinks(candidatesById);

            /*
             * Stage 2:
             * If the RFQ Item already has a Public Folder, make sure ShareInPix image
             * URLs are represented as Public Files and joined into that folder.
             */
            syncShareInPixPublicFiles(candidatesById);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HBF_CreateRFQShareInPixHandler: unexpected error. Message=' + ex.getMessage() +
                ' line=' + ex.getLineNumber());
        } finally {
            isRunning = false;
        }
    }

    private static Map<Id, buildertek__RFQ_Item__c> collectCandidates(
        List<buildertek__RFQ_Item__c> newRecords,
        Map<Id, buildertek__RFQ_Item__c> oldMap
    ) {
        Map<Id, buildertek__RFQ_Item__c> candidatesById = new Map<Id, buildertek__RFQ_Item__c>();

        for (buildertek__RFQ_Item__c recordItem : newRecords) {
            if (recordItem.buildertek__BT_Walk_Through_Line_Item__c == null) {
                continue;
            }

            Boolean shouldProcess = false;
            if (oldMap == null) {
                // After insert: the package Create RFQ flow has just created the line.
                shouldProcess = true;
            } else {
                buildertek__RFQ_Item__c oldItem = oldMap.get(recordItem.Id);
                if (oldItem == null) {
                    shouldProcess = true;
                } else if (
                    oldItem.buildertek__BT_Walk_Through_Line_Item__c != recordItem.buildertek__BT_Walk_Through_Line_Item__c ||
                    oldItem.buildertek__Public_Folder__c != recordItem.buildertek__Public_Folder__c
                ) {
                    // After update: rerun when walkthrough linkage or RFQ folder changes.
                    shouldProcess = true;
                }
            }

            if (shouldProcess) {
                candidatesById.put(recordItem.Id, recordItem);
            }
        }

        return candidatesById;
    }

    private static void syncShareInPixImageLinks(Map<Id, buildertek__RFQ_Item__c> candidatesById) {
        if (!hasSharinPixField(SHARINPIX_RFQ_LINE_FIELD)) {
            System.debug(LoggingLevel.DEBUG,
                'HBF_CreateRFQShareInPixHandler: ' + SHARINPIX_RFQ_LINE_FIELD +
                ' does not exist in this org, skipping ShareInPix RFQ line backfill.');
            return;
        }

        Set<Id> walkThroughLineIds = new Set<Id>();
        Set<String> walkThroughLineIdStrings = new Set<String>();
        for (buildertek__RFQ_Item__c rfqItem : candidatesById.values()) {
            walkThroughLineIds.add(rfqItem.buildertek__BT_Walk_Through_Line_Item__c);
            walkThroughLineIdStrings.add(String.valueOf(rfqItem.buildertek__BT_Walk_Through_Line_Item__c));
        }

        if (walkThroughLineIds.isEmpty()) {
            return;
        }

        Map<Id, Id> walkThroughLineToRfqLineMap = new Map<Id, Id>();
        for (buildertek__RFQ_Item__c rfqItem : candidatesById.values()) {
            walkThroughLineToRfqLineMap.put(
                rfqItem.buildertek__BT_Walk_Through_Line_Item__c,
                rfqItem.Id
            );
        }

        List<ShareInPixImageRow> images = loadShareInPixImages(walkThroughLineIds, walkThroughLineIdStrings);
        List<SObject> imagesToUpdate = new List<SObject>();
        Schema.SObjectType sharinPixType = Schema.getGlobalDescribe().get(SHARINPIX_OBJECT_API_NAME);

        for (ShareInPixImageRow image : images) {
            if (image.walkThroughLineId == null || !walkThroughLineToRfqLineMap.containsKey(image.walkThroughLineId)) {
                continue;
            }

            Id targetRfqLineId = walkThroughLineToRfqLineMap.get(image.walkThroughLineId);
            if (image.currentRfqLineId != targetRfqLineId) {
                SObject imageUpdate = sharinPixType.newSObject(image.imageId);
                imageUpdate.put(SHARINPIX_RFQ_LINE_FIELD, targetRfqLineId);
                imagesToUpdate.add(imageUpdate);
            }
        }

        if (!imagesToUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(imagesToUpdate, false);
            logSaveResults('ShareInPix image RFQ line updates', saveResults);
        } else {
            System.debug(LoggingLevel.DEBUG,
                'HBF_CreateRFQShareInPixHandler: no ShareInPix image BT_RFQ_Lines__c updates were needed.');
        }
    }

    private static void syncShareInPixPublicFiles(Map<Id, buildertek__RFQ_Item__c> candidatesById) {
        Set<Id> walkThroughLineIds = new Set<Id>();
        for (buildertek__RFQ_Item__c rfqItem : candidatesById.values()) {
            walkThroughLineIds.add(rfqItem.buildertek__BT_Walk_Through_Line_Item__c);
        }

        Map<Id, List<ShareInPixImageRow>> imagesByWalkThroughLineId =
            loadImagesByWalkThroughLine(walkThroughLineIds);
        if (imagesByWalkThroughLineId.isEmpty()) {
            System.debug(LoggingLevel.DEBUG,
                'HBF_CreateRFQShareInPixHandler: no ShareInPix images found for candidate walkthrough lines.');
            return;
        }

        /*
         * Stage 2 pre-step:
         * Buildertek usually creates a line-level Public Folder during RFQ file processing.
         * If that folder is missing, create a safe fallback folder here, but only for
         * RFQ lines whose walkthrough lines actually have ShareInPix images.
         */
        ensurePublicFolders(candidatesById, imagesByWalkThroughLineId.keySet());

        Map<Id, buildertek__RFQ_Item__c> folderReadyItemsById = new Map<Id, buildertek__RFQ_Item__c>();
        Set<Id> rfqFolderIds = new Set<Id>();

        for (buildertek__RFQ_Item__c rfqItem : candidatesById.values()) {
            if (rfqItem.buildertek__Public_Folder__c == null) {
                continue;
            }
            if (!imagesByWalkThroughLineId.containsKey(rfqItem.buildertek__BT_Walk_Through_Line_Item__c)) {
                continue;
            }

            folderReadyItemsById.put(rfqItem.Id, rfqItem);
            rfqFolderIds.add(rfqItem.buildertek__Public_Folder__c);
        }

        if (folderReadyItemsById.isEmpty()) {
            System.debug(LoggingLevel.DEBUG,
                'HBF_CreateRFQShareInPixHandler: no RFQ lines with ShareInPix images have usable folders yet.');
            return;
        }

        Map<String, buildertek__Public_File__c> existingPublicFilesByUrl =
            loadExistingPublicFilesByUrl(imagesByWalkThroughLineId);
        Map<Id, Set<Id>> existingFolderFilePairs = loadExistingFolderFilePairs(rfqFolderIds);

        List<buildertek__Public_File__c> publicFilesToInsert = new List<buildertek__Public_File__c>();
        /*
         * Stage 2A:
         * Create any missing Public File records for ShareInPix image URLs.
         */
        for (buildertek__RFQ_Item__c rfqItem : folderReadyItemsById.values()) {
            List<ShareInPixImageRow> lineImages =
                imagesByWalkThroughLineId.get(rfqItem.buildertek__BT_Walk_Through_Line_Item__c);
            if (lineImages == null) {
                continue;
            }

            for (ShareInPixImageRow image : lineImages) {
                String normalizedUrl = normalizeUrl(image.imageUrl);
                if (String.isBlank(normalizedUrl)) {
                    continue;
                }

                if (existingPublicFilesByUrl.containsKey(normalizedUrl)) {
                    continue;
                }

                buildertek__Public_File__c publicFile = new buildertek__Public_File__c();
                publicFile.buildertek__File_Name__c = buildPublicFileName(image);
                publicFile.buildertek__Public_URL__c = normalizedUrl;
                publicFile.buildertek__Skip_Validation__c = true;
                publicFilesToInsert.add(publicFile);
                existingPublicFilesByUrl.put(normalizedUrl, publicFile);
            }
        }

        if (!publicFilesToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(publicFilesToInsert, false);
            logSaveResults('ShareInPix Public File inserts', saveResults);

            for (Integer index = 0; index < saveResults.size(); index++) {
                if (!saveResults[index].isSuccess()) {
                    continue;
                }

                buildertek__Public_File__c insertedPublicFile = publicFilesToInsert[index];
                insertedPublicFile.Id = saveResults[index].getId();
                existingPublicFilesByUrl.put(
                    normalizeUrl(insertedPublicFile.buildertek__Public_URL__c),
                    insertedPublicFile
                );
            }
        }

        /*
         * Stage 2B:
         * Join each ShareInPix-backed Public File into the RFQ line's Public Folder,
         * skipping any existing junctions.
         */
        List<buildertek__Public_File_Folder_Jn__c> junctionsToInsert =
            new List<buildertek__Public_File_Folder_Jn__c>();

        for (buildertek__RFQ_Item__c rfqItem : folderReadyItemsById.values()) {
            List<ShareInPixImageRow> lineImages =
                imagesByWalkThroughLineId.get(rfqItem.buildertek__BT_Walk_Through_Line_Item__c);
            if (lineImages == null) {
                continue;
            }

            Set<Id> existingFileIdsForFolder = existingFolderFilePairs.get(rfqItem.buildertek__Public_Folder__c);
            if (existingFileIdsForFolder == null) {
                existingFileIdsForFolder = new Set<Id>();
                existingFolderFilePairs.put(rfqItem.buildertek__Public_Folder__c, existingFileIdsForFolder);
            }

            for (ShareInPixImageRow image : lineImages) {
                buildertek__Public_File__c publicFile =
                    existingPublicFilesByUrl.get(normalizeUrl(image.imageUrl));
                if (publicFile == null || publicFile.Id == null) {
                    continue;
                }

                if (existingFileIdsForFolder.contains(publicFile.Id)) {
                    continue;
                }

                junctionsToInsert.add(new buildertek__Public_File_Folder_Jn__c(
                    buildertek__Public_Folder__c = rfqItem.buildertek__Public_Folder__c,
                    buildertek__Public_File__c = publicFile.Id
                ));
                existingFileIdsForFolder.add(publicFile.Id);
            }
        }

        if (!junctionsToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(junctionsToInsert, false);
            logSaveResults('ShareInPix Public File Folder junction inserts', saveResults);
        } else {
            System.debug(LoggingLevel.DEBUG,
                'HBF_CreateRFQShareInPixHandler: no ShareInPix Public File Folder junctions were needed.');
        }

        /*
         * Stage 2C:
         * Raw ShareInPix URLs currently respond with Content-Disposition=attachment,
         * which forces download behavior in the browser.
         * Queue an async upgrade that copies the image into Salesforce Files and swaps
         * the Public File over to a browser-viewable ContentDistribution URL.
         */
        queueBrowserFriendlyPublicFileUpgrade(imagesByWalkThroughLineId, existingPublicFilesByUrl);
    }

    private static void ensurePublicFolders(
        Map<Id, buildertek__RFQ_Item__c> candidatesById,
        Set<Id> walkThroughLineIdsWithImages
    ) {
        if (candidatesById == null || candidatesById.isEmpty()) {
            return;
        }
        if (walkThroughLineIdsWithImages == null || walkThroughLineIdsWithImages.isEmpty()) {
            return;
        }

        List<buildertek__Public_Folder__c> foldersToInsert = new List<buildertek__Public_Folder__c>();
        List<Id> rfqItemIdsForFolderInsertOrder = new List<Id>();

        for (buildertek__RFQ_Item__c rfqItem : candidatesById.values()) {
            if (rfqItem.buildertek__Public_Folder__c != null) {
                continue;
            }
            if (!walkThroughLineIdsWithImages.contains(rfqItem.buildertek__BT_Walk_Through_Line_Item__c)) {
                continue;
            }

            buildertek__Public_Folder__c publicFolder = new buildertek__Public_Folder__c();
            publicFolder.Name = buildFolderName(rfqItem);
            publicFolder.buildertek__Description__c = buildFolderDescription(rfqItem);
            publicFolder.buildertek__RelatedToId__c = rfqItem.Id;
            foldersToInsert.add(publicFolder);
            rfqItemIdsForFolderInsertOrder.add(rfqItem.Id);
        }

        if (foldersToInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] folderSaveResults = Database.insert(foldersToInsert, false);
        logSaveResults('RFQ line Public Folder fallback inserts', folderSaveResults);

        List<buildertek__RFQ_Item__c> rfqItemsToUpdate = new List<buildertek__RFQ_Item__c>();

        for (Integer index = 0; index < folderSaveResults.size(); index++) {
            if (!folderSaveResults[index].isSuccess()) {
                continue;
            }

            Id rfqItemId = rfqItemIdsForFolderInsertOrder[index];
            Id publicFolderId = folderSaveResults[index].getId();

            rfqItemsToUpdate.add(new buildertek__RFQ_Item__c(
                Id = rfqItemId,
                buildertek__Public_Folder__c = publicFolderId
            ));
        }

        if (!rfqItemsToUpdate.isEmpty()) {
            Database.SaveResult[] rfqUpdateResults = Database.update(rfqItemsToUpdate, false);
            logSaveResults('RFQ line Public Folder fallback stamps', rfqUpdateResults);

            /*
             * Refresh the local working map from the successful DML results.
             * Trigger.new records are read-only in after context, so never mutate them directly.
             * Instead, replace the cached values with fresh writable instances for downstream logic.
             */
            for (buildertek__RFQ_Item__c stampedItem : [
                SELECT Id, Name, buildertek__BT_Walk_Through_Line_Item__c, buildertek__Public_Folder__c
                FROM buildertek__RFQ_Item__c
                WHERE Id IN :candidatesById.keySet()
            ]) {
                candidatesById.put(stampedItem.Id, stampedItem);
            }
        }
    }

    private static Map<Id, List<ShareInPixImageRow>> loadImagesByWalkThroughLine(Set<Id> walkThroughLineIds) {
        Map<Id, List<ShareInPixImageRow>> imagesByWalkThroughLineId =
            new Map<Id, List<ShareInPixImageRow>>();
        if (walkThroughLineIds.isEmpty()) {
            return imagesByWalkThroughLineId;
        }

        Set<String> walkThroughLineIdStrings = new Set<String>();
        for (Id walkThroughLineId : walkThroughLineIds) {
            walkThroughLineIdStrings.add(String.valueOf(walkThroughLineId));
        }

        for (ShareInPixImageRow image : loadShareInPixImages(walkThroughLineIds, walkThroughLineIdStrings)) {
            if (image.walkThroughLineId == null) {
                continue;
            }

            if (!imagesByWalkThroughLineId.containsKey(image.walkThroughLineId)) {
                imagesByWalkThroughLineId.put(image.walkThroughLineId, new List<ShareInPixImageRow>());
            }
            imagesByWalkThroughLineId.get(image.walkThroughLineId).add(image);
        }

        return imagesByWalkThroughLineId;
    }

    private static Map<String, buildertek__Public_File__c> loadExistingPublicFilesByUrl(
        Map<Id, List<ShareInPixImageRow>> imagesByWalkThroughLineId
    ) {
        Map<String, buildertek__Public_File__c> existingPublicFilesByUrl =
            new Map<String, buildertek__Public_File__c>();
        Set<String> imageUrls = new Set<String>();

        for (List<ShareInPixImageRow> lineImages : imagesByWalkThroughLineId.values()) {
            for (ShareInPixImageRow image : lineImages) {
                String normalizedUrl = normalizeUrl(image.imageUrl);
                if (!String.isBlank(normalizedUrl)) {
                    imageUrls.add(normalizedUrl);
                }
            }
        }

        if (imageUrls.isEmpty()) {
            return existingPublicFilesByUrl;
        }

        for (buildertek__Public_File__c publicFile : [
            SELECT Id, buildertek__File_Name__c, buildertek__Public_URL__c,
                   buildertek__Content_Distrubution__c, buildertek__Content_Version__c
            FROM buildertek__Public_File__c
            WHERE buildertek__Public_URL__c IN :imageUrls
        ]) {
            existingPublicFilesByUrl.put(normalizeUrl(publicFile.buildertek__Public_URL__c), publicFile);
        }

        return existingPublicFilesByUrl;
    }

    private static Map<Id, Set<Id>> loadExistingFolderFilePairs(Set<Id> folderIds) {
        Map<Id, Set<Id>> existingFolderFilePairs = new Map<Id, Set<Id>>();
        if (folderIds.isEmpty()) {
            return existingFolderFilePairs;
        }

        for (buildertek__Public_File_Folder_Jn__c junctionRecord : [
            SELECT buildertek__Public_Folder__c, buildertek__Public_File__c
            FROM buildertek__Public_File_Folder_Jn__c
            WHERE buildertek__Public_Folder__c IN :folderIds
        ]) {
            if (!existingFolderFilePairs.containsKey(junctionRecord.buildertek__Public_Folder__c)) {
                existingFolderFilePairs.put(junctionRecord.buildertek__Public_Folder__c, new Set<Id>());
            }
            existingFolderFilePairs.get(junctionRecord.buildertek__Public_Folder__c)
                .add(junctionRecord.buildertek__Public_File__c);
        }

        return existingFolderFilePairs;
    }

    private static String buildPublicFileName(ShareInPixImageRow image) {
        String baseName = String.isBlank(image.imageName) ? 'ShareInPix Image' : image.imageName.trim();
        String uniqueName = baseName + ' ' + image.imageId;
        return uniqueName.length() > 255 ? uniqueName.substring(0, 255) : uniqueName;
    }

    private static void queueBrowserFriendlyPublicFileUpgrade(
        Map<Id, List<ShareInPixImageRow>> imagesByWalkThroughLineId,
        Map<String, buildertek__Public_File__c> existingPublicFilesByUrl
    ) {
        if (browserUpgradeQueued || imagesByWalkThroughLineId == null || imagesByWalkThroughLineId.isEmpty()) {
            return;
        }

        Set<Id> imageIdsToUpgrade = new Set<Id>();
        for (List<ShareInPixImageRow> lineImages : imagesByWalkThroughLineId.values()) {
            for (ShareInPixImageRow image : lineImages) {
                String normalizedUrl = normalizeUrl(image.imageUrl);
                if (String.isBlank(normalizedUrl) || !isShareInPixHostedUrl(normalizedUrl)) {
                    continue;
                }

                buildertek__Public_File__c publicFile = existingPublicFilesByUrl.get(normalizedUrl);
                if (publicFile == null) {
                    continue;
                }

                if (String.isBlank(publicFile.buildertek__Content_Version__c) ||
                    String.isBlank(publicFile.buildertek__Content_Distrubution__c)) {
                    imageIdsToUpgrade.add(image.imageId);
                }
            }
        }

        if (imageIdsToUpgrade.isEmpty()) {
            return;
        }

        browserUpgradeQueued = true;
        try {
            System.enqueueJob(new HBF_ShareInPixPublicFileUpgradeQueueable(new List<Id>(imageIdsToUpgrade)));
            System.debug(LoggingLevel.DEBUG,
                'HBF_CreateRFQShareInPixHandler: queued browser-friendly upgrade for ShareInPix images=' +
                imageIdsToUpgrade.size());
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'HBF_CreateRFQShareInPixHandler: unable to queue browser-friendly upgrade. Message=' +
                ex.getMessage());
        }
    }

    private static String buildFolderName(buildertek__RFQ_Item__c rfqItem) {
        String preferredName = 'RFQ Line Images for ' + String.valueOf(rfqItem.Name);
        return preferredName.length() > 79 ? 'RFQ Line Img' : preferredName;
    }

    private static String buildFolderDescription(buildertek__RFQ_Item__c rfqItem) {
        String descriptionValue =
            'ShareInPix images for WT line ' + String.valueOf(rfqItem.buildertek__BT_Walk_Through_Line_Item__c);
        return descriptionValue.length() > 255 ? descriptionValue.substring(0, 255) : descriptionValue;
    }

    private static List<ShareInPixImageRow> loadShareInPixImages(
        Set<Id> walkThroughLineIds,
        Set<String> walkThroughLineIdStrings
    ) {
        List<ShareInPixImageRow> results = new List<ShareInPixImageRow>();
        if (walkThroughLineIds.isEmpty() || walkThroughLineIdStrings.isEmpty()) {
            return results;
        }

        List<String> selectFields = new List<String>{ 'Id', 'Name', SHARINPIX_IMAGE_URL_FIELD, SHARINPIX_ALBUM_FIELD };
        if (hasSharinPixField(SHARINPIX_WT_LINE_FIELD)) {
            selectFields.add(SHARINPIX_WT_LINE_FIELD);
        }
        if (hasSharinPixField(SHARINPIX_RFQ_LINE_FIELD)) {
            selectFields.add(SHARINPIX_RFQ_LINE_FIELD);
        }

        String query =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + SHARINPIX_OBJECT_API_NAME +
            ' WHERE ' + SHARINPIX_ALBUM_FIELD + ' IN :walkThroughLineIdStrings';

        if (hasSharinPixField(SHARINPIX_WT_LINE_FIELD)) {
            query += ' OR ' + SHARINPIX_WT_LINE_FIELD + ' IN :walkThroughLineIds';
        }

        for (SObject row : Database.query(query)) {
            ShareInPixImageRow image = new ShareInPixImageRow();
            image.imageId = (Id) row.get('Id');
            image.imageName = (String) row.get('Name');
            image.imageUrl = (String) row.get(SHARINPIX_IMAGE_URL_FIELD);
            image.albumId = (String) row.get(SHARINPIX_ALBUM_FIELD);

            if (hasSharinPixField(SHARINPIX_WT_LINE_FIELD)) {
                image.walkThroughLineId = (Id) row.get(SHARINPIX_WT_LINE_FIELD);
            }
            if (image.walkThroughLineId == null && !String.isBlank(image.albumId)) {
                try {
                    image.walkThroughLineId = (Id) image.albumId;
                } catch (Exception ignored) {
                    // Ignore album ids that are not walkthrough line ids.
                }
            }
            if (hasSharinPixField(SHARINPIX_RFQ_LINE_FIELD)) {
                image.currentRfqLineId = (Id) row.get(SHARINPIX_RFQ_LINE_FIELD);
            }

            results.add(image);
        }

        return results;
    }

    private static Boolean hasSharinPixField(String fieldApiName) {
        Schema.SObjectType sharinPixType = Schema.getGlobalDescribe().get(SHARINPIX_OBJECT_API_NAME);
        if (sharinPixType == null || String.isBlank(fieldApiName)) {
            return false;
        }

        return sharinPixType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    private static String normalizeUrl(String urlValue) {
        return String.isBlank(urlValue) ? null : urlValue.trim();
    }

    private static Boolean isShareInPixHostedUrl(String urlValue) {
        String normalizedUrl = normalizeUrl(urlValue);
        return !String.isBlank(normalizedUrl) && normalizedUrl.contains('p.sharinpix.com/');
    }

    private static void logSaveResults(String stageName, Database.SaveResult[] saveResults) {
        if (saveResults == null) {
            return;
        }

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
            'HBF_CreateRFQShareInPixHandler [' + stageName + '] successes=' + successCount +
            ' errors=' + errorCount);

        if (!errorMessages.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'HBF_CreateRFQShareInPixHandler [' + stageName + '] error details=' +
                String.join(errorMessages, ' | '));
        }
    }

    private class ShareInPixImageRow {
        Id imageId;
        String imageName;
        String imageUrl;
        String albumId;
        Id walkThroughLineId;
        Id currentRfqLineId;
    }
}