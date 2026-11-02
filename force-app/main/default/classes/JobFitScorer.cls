/**
 * Calls an LLM endpoint to summarize a job and give a fit score (0-100).
 * Endpoint + auth live in the Named Credential LLM_API, nothing hardcoded here.
 *
 * Expected response body:
 *   { "summary": "...", "fit_score": 72 }
 */
public with sharing class JobFitScorer {

    public class FitResult {
        public String summary;
        public Integer score;
    }

    public class ScorerException extends Exception {}

    // TODO: move my profile text to a custom metadata type so it's not in code
    private static final String MY_PROFILE =
        'Junior Salesforce developer. Apex, SOQL, Flows, LWC basics. ' +
        'Based in Brazil, open to remote.';

    public static FitResult score(Job_Application__c app) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LLM_API/v1/score');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(20000);

        Map<String, Object> body = new Map<String, Object>{
            'company' => app.Company__c,
            'role' => app.Role__c,
            'job_url' => app.Job_Url__c,
            'candidate_profile' => MY_PROFILE
        };
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new ScorerException('LLM_API returned ' + res.getStatusCode() + ': ' + res.getBody());
        }
        return parse(res.getBody());
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
