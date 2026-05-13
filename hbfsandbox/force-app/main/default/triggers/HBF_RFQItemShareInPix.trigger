trigger HBF_RFQItemShareInPix on buildertek__RFQ_Item__c (after insert, after update) {
    /*
     * This trigger intentionally avoids throwing errors.
     * The packaged Buildertek trigger must remain the primary owner of RFQ Item behavior.
     * We only add ShareInPix follow-up automation that is missing from the packaged flow.
     */
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            HBF_CreateRFQShareInPixHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            HBF_CreateRFQShareInPixHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}