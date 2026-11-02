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
            Assert.isTrue(req.getEndpoint().startsWith('callout:LLM_API/v1beta/models/'), 'should use the named credential');
            Assert.isTrue(req.getEndpoint().endsWith(':generateContent'));
            Assert.areEqual('POST', req.getMethod());
            Assert.areEqual('test-key', req.getHeader('x-goog-api-key'));
            Assert.isTrue(req.getBody().contains('application/json'), 'should ask for JSON output');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    // wraps our JSON the way Gemini returns it
    private static String gemini(String innerJson) {
        return JSON.serialize(new Map<String, Object>{
            'candidates' => new List<Object>{ new Map<String, Object>{
                'content' => new Map<String, Object>{
                    'parts' => new List<Object>{ new Map<String, Object>{ 'text' => innerJson } }
                }
            } }
        });
    }

    private static void setup(Integer maxCalls, Integer callsToday) {
        insert new LLM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Api_Key__c = 'test-key',
            Max_Calls_Per_Day__c = maxCalls,
            Calls_Today__c = callsToday,
            Last_Call_Date__c = Date.today()
        );
    }

    @IsTest
    static void scoreParsesResponse() {
        setup(5, 0);
        Test.setMock(HttpCalloutMock.class, new LlmMock(200, gemini('{"summary":"Apex heavy role","fit_score":78}')));

        Test.startTest();
        JobFitScorer.FitResult r = JobFitScorer.score(new Job_Application__c(Company__c = 'Acme', Role__c = 'Jr Salesforce Dev'));
        JobFitScorer.saveUsage();
        Test.stopTest();

        Assert.areEqual('Apex heavy role', r.summary);
        Assert.areEqual(78, r.score);
        Assert.areEqual(1, LLM_Settings__c.getOrgDefaults().Calls_Today__c);
    }

    @IsTest
    static void scoreIsClamped() {
        Assert.areEqual(100, JobFitScorer.parse('{"summary":"x","fit_score":140}').score);
        Assert.areEqual(0, JobFitScorer.parse('{"summary":"x","fit_score":-5}').score);
        Assert.areEqual(64, JobFitScorer.parse('{"summary":"x","fit_score":64.7}').score);
        Assert.areEqual(0, JobFitScorer.parse('{"summary":"x"}').score);
    }

    @IsTest
    static void badGeminiShapeThrows() {
        try {
            JobFitScorer.extractText('{"candidates":[]}');
            Assert.fail('expected ScorerException');
        } catch (JobFitScorer.ScorerException e) {
            Assert.isTrue(e.getMessage().contains('Unexpected'));
        }
    }

    @IsTest
    static void errorStatusThrows() {
        setup(5, 0);
        Test.setMock(HttpCalloutMock.class, new LlmMock(500, '{"error":"boom"}'));
        Test.startTest(); // fresh transaction so the setup insert doesn't block the callout
        try {
            JobFitScorer.score(new Job_Application__c(Role__c = 'Dev'));
            Assert.fail('expected ScorerException');
        } catch (JobFitScorer.ScorerException e) {
            Assert.isTrue(e.getMessage().contains('500'));
        }
    }

    @IsTest
    static void missingKeyThrows() {
        try {
            JobFitScorer.score(new Job_Application__c(Role__c = 'Dev'));
            Assert.fail('expected ScorerException');
        } catch (JobFitScorer.ScorerException e) {
            Assert.isTrue(e.getMessage().contains('Api_Key__c'));
        }
    }

    @IsTest
    static void capStopsCallout() {
        setup(2, 2);
        // no mock set: if it tried a callout the test would fail
        try {
            JobFitScorer.score(new Job_Application__c(Role__c = 'Dev'));
            Assert.fail('expected CapReachedException');
        } catch (JobFitScorer.CapReachedException e) {
            Assert.isTrue(JobFitScorer.capReached());
        }
    }

    @IsTest
    static void oldCountResetsNextDay() {
        insert new LLM_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Api_Key__c = 'test-key',
            Max_Calls_Per_Day__c = 2, Calls_Today__c = 2, Last_Call_Date__c = Date.today().addDays(-1));
        Assert.isFalse(JobFitScorer.capReached());
    }

    @IsTest
    static void insertTriggersQueueableAndSavesScore() {
        setup(5, 0);
        Test.setMock(HttpCalloutMock.class, new LlmMock(200, gemini('{"summary":"Good match","fit_score":85}')));

        Test.startTest();
        insert new Job_Application__c(Company__c = 'Globex', Role__c = 'Salesforce Developer', Status__c = 'Applied');
        Test.stopTest(); // queueable runs here

        Job_Application__c saved = [SELECT Fit_Score__c, AI_Summary__c, Applied_On__c FROM Job_Application__c LIMIT 1];
        Assert.areEqual(85, saved.Fit_Score__c);
        Assert.areEqual('Good match', saved.AI_Summary__c);
        // set by the flow
        Assert.areEqual(Date.today(), saved.Applied_On__c);
        Assert.areEqual(1, LLM_Settings__c.getOrgDefaults().Calls_Today__c);
    }

    @IsTest
    static void queueableLeavesNoteWhenCapReached() {
        setup(1, 1);
        Test.startTest();
        insert new Job_Application__c(Company__c = 'Umbrella', Role__c = 'Dev', Status__c = 'Applied');
        Test.stopTest();

        Job_Application__c saved = [SELECT Fit_Score__c, AI_Summary__c FROM Job_Application__c LIMIT 1];
        Assert.isNull(saved.Fit_Score__c);
        Assert.isTrue(saved.AI_Summary__c.contains('limit'));
    }

    @IsTest
    static void queueableSurvivesBadResponse() {
        setup(5, 0);
        Test.setMock(HttpCalloutMock.class, new LlmMock(500, 'oops'));

        Test.startTest();
        insert new Job_Application__c(Company__c = 'Initech', Role__c = 'Admin', Status__c = 'Applied');
        Test.stopTest();

        Job_Application__c saved = [SELECT Fit_Score__c FROM Job_Application__c LIMIT 1];
        Assert.isNull(saved.Fit_Score__c);
    }
}
