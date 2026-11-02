/**
 * Asks Google Gemini (free tier) to summarize a job and give a fit score (0-100).
 * URL comes from the Named Credential LLM_API, the API key comes from the
 * protected custom setting LLM_Settings__c (org default). Nothing secret in code.
 *
 * There is also a small daily cap (Max_Calls_Per_Day__c) so I don't burn the free quota.
 */
public with sharing class JobFitScorer {

    public class FitResult {
        public String summary;
        public Integer score;
    }

    public class ScorerException extends Exception {}
    public class CapReachedException extends Exception {}

    @TestVisible
    private static final String MODEL = 'gemini-2.5-flash';

    // TODO: move my profile text to a custom metadata type so it's not in code
    private static final String MY_PROFILE =
        'Junior Salesforce developer. Apex, SOQL, Flows, LWC basics. ' +
        'Based in Brazil, open to remote.';

    // calls made in this transaction, saved to the setting later by saveUsage()
    private static Integer callsThisRun = 0;

    private static LLM_Settings__c settings() {
        LLM_Settings__c s = LLM_Settings__c.getOrgDefaults();
        if (s == null) {
            s = new LLM_Settings__c();
        }
        return s;
    }

    private static Integer callsUsedToday(LLM_Settings__c s) {
        Integer saved = (s.Last_Call_Date__c == Date.today() && s.Calls_Today__c != null)
            ? s.Calls_Today__c.intValue() : 0;
        return saved + callsThisRun;
    }

    public static Boolean capReached() {
        LLM_Settings__c s = settings();
        Integer max = s.Max_Calls_Per_Day__c == null ? 2 : s.Max_Calls_Per_Day__c.intValue();
        return callsUsedToday(s) >= max;
    }

    public static FitResult score(Job_Application__c app) {
        if (capReached()) {
            throw new CapReachedException('Daily Gemini call limit reached, skipped.');
        }
        LLM_Settings__c s = settings();
        if (String.isBlank(s.Api_Key__c)) {
            throw new ScorerException('LLM_Settings__c.Api_Key__c is not set');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LLM_API/v1beta/models/' + MODEL + ':generateContent');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-goog-api-key', s.Api_Key__c);
        req.setTimeout(60000);

        String prompt =
            'You review job postings for a candidate. Reply ONLY with JSON like ' +
            '{"summary": "<2 short sentences about the role>", "fit_score": <integer 0-100>}.\n' +
            'Candidate: ' + MY_PROFILE + '\n' +
            'Company: ' + app.Company__c + '\n' +
            'Role: ' + app.Role__c + '\n' +
            'Job URL: ' + app.Job_Url__c;

        Map<String, Object> body = new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{
                    'parts' => new List<Object>{ new Map<String, Object>{ 'text' => prompt } }
                }
            },
            'generationConfig' => new Map<String, Object>{
                'responseMimeType' => 'application/json'
            }
        };
        req.setBody(JSON.serialize(body));

        callsThisRun++; // count it even if it fails, it still used quota
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new ScorerException('Gemini returned ' + res.getStatusCode() + ': ' + res.getBody());
        }
        return parse(extractText(res.getBody()));
    }

    // Saves today's call count. Call this AFTER all callouts (no DML before callouts).
    public static void saveUsage() {
        if (callsThisRun == 0) {
            return;
        }
        LLM_Settings__c s = settings();
        s.Calls_Today__c = callsUsedToday(s);
        s.Last_Call_Date__c = Date.today();
        upsert s;
        callsThisRun = 0;
    }

    // Gemini puts the model answer in candidates[0].content.parts[0].text
    @TestVisible
    private static String extractText(String json) {
        try {
            Map<String, Object> data = (Map<String, Object>) System.JSON.deserializeUntyped(json);
            Map<String, Object> cand = (Map<String, Object>) ((List<Object>) data.get('candidates'))[0];
            Map<String, Object> content = (Map<String, Object>) cand.get('content');
            Map<String, Object> part = (Map<String, Object>) ((List<Object>) content.get('parts'))[0];
            return (String) part.get('text');
        } catch (Exception e) {
            throw new ScorerException('Unexpected Gemini response: ' + json.left(500));
        }
    }

    @TestVisible
    private static FitResult parse(String json) {
        Map<String, Object> data = (Map<String, Object>) System.JSON.deserializeUntyped(json);
        FitResult r = new FitResult();
        r.summary = (String) data.get('summary');

        Object raw = data.get('fit_score');
        Integer s = raw == null ? 0 : Integer.valueOf(String.valueOf(raw).substringBefore('.'));
        // model sometimes goes out of range, clamp it
        r.score = Math.max(0, Math.min(100, s));
        return r;
    }
}
