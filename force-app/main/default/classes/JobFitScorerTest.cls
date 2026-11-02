@IsTest
private class JobFitScorerTest {

    private class LlmMock implements HttpCalloutMock {
        Integer code;
        String body;
        LlmMock(Integer code, String body) {
            this.code = code;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            Assert.isTrue(req.getEndpoint().startsWith('callout:LLM_API'), 'should use the named credential');
            Assert.areEqual('POST', req.getMethod());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void scoreParsesResponse() {
        Test.setMock(HttpCalloutMock.class, new LlmMock(200, '{"summary":"Apex heavy role","fit_score":78}'));
        Job_Application__c app = new Job_Application__c(Company__c = 'Acme', Role__c = 'Jr Salesforce Dev');

        Test.startTest();
        JobFitScorer.FitResult r = JobFitScorer.score(app);
        Test.stopTest();

        Assert.areEqual('Apex heavy role', r.summary);
        Assert.areEqual(78, r.score);
    }

    @IsTest
    static void scoreIsClamped() {
        Assert.areEqual(100, JobFitScorer.parse('{"summary":"x","fit_score":140}').score);
        Assert.areEqual(0, JobFitScorer.parse('{"summary":"x","fit_score":-5}').score);
        Assert.areEqual(64, JobFitScorer.parse('{"summary":"x","fit_score":64.7}').score);
        Assert.areEqual(0, JobFitScorer.parse('{"summary":"x"}').score);
    }

    @IsTest
    static void errorStatusThrows() {
        Test.setMock(HttpCalloutMock.class, new LlmMock(500, '{"error":"boom"}'));
        try {
            JobFitScorer.score(new Job_Application__c(Role__c = 'Dev'));
            Assert.fail('expected ScorerException');
        } catch (JobFitScorer.ScorerException e) {
            Assert.isTrue(e.getMessage().contains('500'));
        }
    }

    @IsTest
    static void insertTriggersQueueableAndSavesScore() {
        Test.setMock(HttpCalloutMock.class, new LlmMock(200, '{"summary":"Good match","fit_score":85}'));

        Test.startTest();
        insert new Job_Application__c(Company__c = 'Globex', Role__c = 'Salesforce Developer', Status__c = 'Applied');
        Test.stopTest(); // queueable runs here

        Job_Application__c saved = [SELECT Fit_Score__c, AI_Summary__c, Applied_On__c FROM Job_Application__c LIMIT 1];
        Assert.areEqual(85, saved.Fit_Score__c);
        Assert.areEqual('Good match', saved.AI_Summary__c);
        // set by the flow
        Assert.areEqual(Date.today(), saved.Applied_On__c);
    }

    @IsTest
    static void queueableSurvivesBadResponse() {
        Test.setMock(HttpCalloutMock.class, new LlmMock(500, 'oops'));

        Test.startTest();
        insert new Job_Application__c(Company__c = 'Initech', Role__c = 'Admin', Status__c = 'Applied');
        Test.stopTest();

        Job_Application__c saved = [SELECT Fit_Score__c FROM Job_Application__c LIMIT 1];
        Assert.isNull(saved.Fit_Score__c);
    }
}
