@IsTest
private class JobApplicationServiceTest {

    @TestSetup
    static void setup() {
        // no Role__c so the trigger doesn't enqueue a callout here
        insert new List<Job_Application__c>{
            new Job_Application__c(Company__c = 'Acme', Status__c = 'Applied', Applied_On__c = Date.today().addDays(-30)),
            new Job_Application__c(Company__c = 'Globex', Status__c = 'Applied', Applied_On__c = Date.today().addDays(-3)),
            new Job_Application__c(Company__c = 'Initech', Status__c = 'Interview', Applied_On__c = Date.today().addDays(-25)),
            new Job_Application__c(Company__c = 'Umbrella', Status__c = 'Offer', Applied_On__c = Date.today().addDays(-40))
        };
    }

    @IsTest
    static void openApplicationsSkipsOfferAndRejected() {
        List<Job_Application__c> open = JobApplicationService.getOpenApplications();
        Assert.areEqual(3, open.size());
        for (Job_Application__c a : open) {
            Assert.areNotEqual('Offer', a.Status__c);
        }
    }

    @IsTest
    static void countByStatusGroups() {
        Map<String, Integer> counts = JobApplicationService.countByStatus();
        Assert.areEqual(2, counts.get('Applied'));
        Assert.areEqual(1, counts.get('Interview'));
        Assert.areEqual(1, counts.get('Offer'));
    }

    @IsTest
    static void staleAppliedBecomesRejected() {
        Test.startTest();
        Integer updated = JobApplicationService.markStaleAsRejected();
        Test.stopTest();

        // only Acme: Applied and older than 21 days. Initech is Interview so it stays
        Assert.areEqual(1, updated);
        Job_Application__c acme = [SELECT Status__c FROM Job_Application__c WHERE Company__c = 'Acme'];
        Assert.areEqual('Rejected', acme.Status__c);
        Job_Application__c initech = [SELECT Status__c FROM Job_Application__c WHERE Company__c = 'Initech'];
        Assert.areEqual('Interview', initech.Status__c);
    }

    @IsTest
    static void nothingStaleReturnsZero() {
        delete [SELECT Id FROM Job_Application__c WHERE Company__c = 'Acme'];
        Assert.areEqual(0, JobApplicationService.markStaleAsRejected());
    }
}
