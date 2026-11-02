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

## LLM endpoint setup

The Named Credential in `force-app/main/default/namedCredentials/LLM_API.namedCredential-meta.xml`
only has a placeholder URL (`https://llm-api.example.com`) and no secrets. After deploying:

1. Setup > Named Credentials > LLM_API: change the URL to your real endpoint.
2. Add the API key as an External Credential / custom header (don't commit it).
3. Named Credentials don't need a Remote Site Setting. If you change the code to call a raw URL instead of `callout:LLM_API`, you'll need to add one under Setup > Remote Site Settings.

The code calls `POST {url}/v1/score`. If your provider has a different format you'll probably need a small proxy (I used a tiny serverless function for that).

## TODO

- Schedulable job to run `markStaleAsRejected()` every week
- Move my candidate profile text out of `JobFitScorer` into custom metadata
- Chain queueables when inserting more than 100 records (callout limit)
- Simple LWC to show counts by status

## Status

The metadata was checked locally (XML parse + `sf project convert source`). Tests are written but I still have to run them in an org, so no coverage numbers yet.

MIT license.
