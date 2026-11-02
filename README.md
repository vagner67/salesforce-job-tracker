# salesforce-job-tracker

Small Salesforce DX project I'm using to track my job applications inside a dev org.
It's also my first try at doing Apex callouts to an external API.

## What it does

- `Job_Application__c` object: company, role, status (Applied / Interview / Offer / Rejected), applied date, job URL, fit score and an AI summary.
- `JobApplicationService`: SOQL helpers (`getOpenApplications`, `countByStatus`) and `markStaleAsRejected()`, which moves anything still "Applied" after 21 days to "Rejected".
- `JobFitScorer`: sends company/role/URL to an LLM endpoint through the Named Credential `LLM_API` and reads back `{"summary": "...", "fit_score": 0-100}`.
- `JobApplicationTrigger` (after insert) enqueues `JobFitScoreQueueable`, since triggers can't make callouts.
- Flow `Job_Application_Set_Applied_On` (before save): if status is Applied and Applied On is empty, sets it to today.

## Deploy

You need the Salesforce CLI (`npm i -g @salesforce/cli`) and a Developer Edition org or scratch org.

```
sf org login web --alias jobdev
sf project deploy start --target-org jobdev
sf apex run test --target-org jobdev --code-coverage --result-format human
```

## LLM setup (Google Gemini free tier)

`JobFitScorer` calls `POST callout:LLM_API/v1beta/models/gemini-2.5-flash:generateContent`.
The Named Credential `LLM_API` points to `https://generativelanguage.googleapis.com` and has no secrets.

The API key lives only in the org, in the protected hierarchy custom setting `LLM_Settings__c`:

1. Get a key from Google AI Studio (don't commit it anywhere).
2. Setup > Custom Settings > LLM Settings > Manage > New (org default), fill **Api Key**.
   Or with the CLI, reading the key from a local file so it doesn't show up on screen:
   `sf data create record -o <alias> -s LLM_Settings__c -v "SetupOwnerId=<OrgId> Api_Key__c=$(cat ~/.secrets/gemini_key) Max_Calls_Per_Day__c=2"`
3. Assign the `Job_Tracker_User` permission set to your user.

Daily cap: `Max_Calls_Per_Day__c` (default 2). `Calls_Today__c` / `Last_Call_Date__c` are updated by the queueable.
When the cap is hit, no callout is made and `AI_Summary__c` gets a short note instead. Raise the number in the setting if you need more.

## TODO

- Schedulable job to run `markStaleAsRejected()` every week
- Move my candidate profile text out of `JobFitScorer` into custom metadata
- Chain queueables when inserting more than 100 records (callout limit)
- Simple LWC to show counts by status

## Status

Deployed to a Developer Edition org with RunLocalTests: 14/14 tests passing, ~98% coverage.

MIT license.
