/**
 * Runs the LLM callout async because triggers can't do callouts directly.
 */
public with sharing class JobFitScoreQueueable implements Queueable, Database.AllowsCallouts {

    private Set<Id> appIds;

    public JobFitScoreQueueable(Set<Id> appIds) {
        this.appIds = appIds;
    }

    public void execute(QueueableContext ctx) {
        List<Job_Application__c> apps = [
            SELECT Id, Company__c, Role__c, Job_Url__c
            FROM Job_Application__c
            WHERE Id IN :appIds
        ];
        List<Job_Application__c> toUpdate = new List<Job_Application__c>();

        // TODO: callout limit is 100 per transaction, chain jobs if I ever bulk import more
        for (Job_Application__c app : apps) {
            try {
                JobFitScorer.FitResult r = JobFitScorer.score(app);
                toUpdate.add(new Job_Application__c(
                    Id = app.Id,
                    AI_Summary__c = r.summary,
                    Fit_Score__c = r.score
                ));
            } catch (Exception e) {
                // don't kill the whole batch for one bad response
                System.debug(LoggingLevel.ERROR, 'Fit score failed for ' + app.Id + ': ' + e.getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
