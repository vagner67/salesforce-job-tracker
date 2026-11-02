trigger JobApplicationTrigger on Job_Application__c (after insert) {
    // only score records that have something to send
    Set<Id> ids = new Set<Id>();
    for (Job_Application__c app : Trigger.new) {
        if (String.isNotBlank(app.Role__c)) {
            ids.add(app.Id);
        }
    }
    if (!ids.isEmpty() && !System.isQueueable() && !System.isBatch()) {
        System.enqueueJob(new JobFitScoreQueueable(ids));
    }
}
