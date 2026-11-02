/**
 * Queries and small updates for Job_Application__c.
 * Kept everything static so it's easy to call from anonymous apex too.
 */
public with sharing class JobApplicationService {

    public static final Integer STALE_DAYS = 21;

    // "open" = still waiting on something (not Offer / Rejected)
    public static List<Job_Application__c> getOpenApplications() {
        return [
            SELECT Id, Name, Company__c, Role__c, Status__c, Applied_On__c, Fit_Score__c
            FROM Job_Application__c
            WHERE Status__c IN ('Applied', 'Interview')
            ORDER BY Applied_On__c ASC NULLS LAST
            LIMIT 500
        ];
    }

    public static Map<String, Integer> countByStatus() {
        Map<String, Integer> result = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Status__c status, COUNT(Id) total
            FROM Job_Application__c
            GROUP BY Status__c
        ]) {
            String status = (String) ar.get('status');
            if (status == null) {
                status = 'None';
            }
            result.put(status, (Integer) ar.get('total'));
        }
        return result;
    }

    // Anything still "Applied" after 21 days with no answer -> Rejected.
    // Returns how many records were updated.
    public static Integer markStaleAsRejected() {
        Date cutoff = Date.today().addDays(-STALE_DAYS);
        List<Job_Application__c> stale = [
            SELECT Id, Status__c
            FROM Job_Application__c
            WHERE Status__c = 'Applied'
            AND Applied_On__c < :cutoff
        ];
        for (Job_Application__c app : stale) {
            app.Status__c = 'Rejected';
        }
        if (!stale.isEmpty()) {
            update stale;
        }
        // TODO: schedule this weekly (Schedulable class) instead of running by hand
        return stale.size();
    }
}
