# Runbook

What to do when something alerts. Every alarm email links to a section here.
All commands assume `export AWS_PROFILE=zihao-admin AWS_REGION=us-east-1` after `aws sso login --sso-session zihao`.

**The first rule: do not fix production by hand.** Fix it with a pull request (a `git revert` is a perfectly good PR). A change made in the console is caught by the nightly drift check and overwritten by the next deploy.

## Quick map

| Alarm | Means | Section |
|---|---|---|
| `zihao-cv-lambda-errors` | the counter function threw an error | [lambda-errors](#lambda-errors) |
| `zihao-cv-lambda-throttles` | Lambda refused a call (limit: 10 concurrent) | [lambda-throttles](#lambda-throttles) |
| `zihao-cv-api-5xx` | visitors got a server error | [api-5xx](#api-5xx) |
| `zihao-cv-api-latency-p99` | 1 in 100 requests is slower than 1 s | [api-latency](#api-latency) |
| `zihao-cv-site-down` | the external check failed twice in a row | [site-down](#site-down) |
| GitHub issue labelled `drift` | AWS differs from the code | [drift](#drift) |
| AWS Budgets / Cost Anomaly email | money | [cost](#cost) |

Every alarm also emails when it recovers (state `OK`). If you see the recovery mail and nothing else is wrong, it was a blip: note the time and move on.

---

## lambda-errors

**Means:** `counter-dev` raised an exception. Visitors see no counter (the page itself still loads).

1. **Read the error.** The Lambda logs the full stack trace and returns only a generic message:
   ```
   aws logs tail /aws/lambda/counter-dev --since 30m --filter-pattern "ERROR"
   ```
2. **Typical causes**
   - `AccessDeniedException` -> the Lambda role lost its DynamoDB permission (someone edited it, or a bad change). The nightly drift check will also report it.
   - `ResourceNotFoundException` -> the table is missing; go to [restore the counter table](#restore-the-counter-table).
   - A code bug from the latest deploy -> step 3.
3. **Was it the last deploy?** `gh run list --workflow deploy.yml --limit 3`. If the error started right after one: [roll back a bad deploy](#roll-back-a-bad-deploy).
4. **Need the timeline of one request?** X-Ray: CloudWatch -> X-Ray traces -> filter `service(id(name: "counter-dev"))`.

## lambda-throttles

**Means:** Lambda refused to start the function because the account limit (10 concurrent executions) was reached. A reserved-concurrency cap is impossible on this account (AWS keeps 10 unreserved), so API throttling (10 req/s, burst 20) is the protection.

1. Is it real traffic or abuse? Count requests per minute:
   ```
   aws logs filter-log-events --log-group-name /aws/vendedlogs/apigateway/api-dev \
     --start-time $(( ($(date +%s) - 900) * 1000 )) --query 'length(events)'
   ```
2. A few throttles during a traffic spike: nothing to do, visitors retry.
3. Sustained abuse: tighten `throttling_rate_limit` / `throttling_burst_limit` in `infra/modules/backend/main.tf`, or block the source in Cloudflare (WAF rule / "Under attack" mode) — Cloudflare sits in front and is free.

## api-5xx

**Means:** API Gateway returned a 5xx to a visitor. Usually the Lambda failed, so look at [lambda-errors](#lambda-errors) first.

1. Which route and when? The access log has one JSON line per request:
   ```
   aws logs tail /aws/vendedlogs/apigateway/api-dev --since 30m --filter-pattern '{ $.status = 5* }'
   ```
2. `integrationStatus` 5xx (or missing) = the Lambda; `status` 5xx with `integrationStatus` 200 = API Gateway itself (check the AWS Health Dashboard).
3. Cause found in the code -> [roll back a bad deploy](#roll-back-a-bad-deploy).

## api-latency

**Means:** for three 5-minute periods in a row, 1% of requests took over 1 second. (The check uses p99 because an average hides the slow tail.)

1. `responseLatency` vs `integrationLatency` in the access log: if they are close, the Lambda is slow; if `responseLatency` is much larger, it is API Gateway.
2. X-Ray trace of a slow request shows whether the time went to DynamoDB or to Lambda start-up.
3. A cold start after a quiet period is normal (a few hundred ms). Only investigate if it repeats under steady traffic.

## site-down

**Means:** the external check (every 5 minutes) failed twice in a row: the page did not load / lost its content, or `/health` did not say `ok`. It also fires if the checker itself stops reporting.

1. **What failed?**
   ```
   aws logs tail /aws/lambda/uptime-dev --since 30m
   ```
   `failed checks: site` = page. `failed checks: api` = health endpoint. No recent lines at all = the checker is dead (check the EventBridge rule `uptime-dev-schedule`).
2. **Page down?**
   - `curl -I https://zihao-cv.site` — Cloudflare error (52x) -> CloudFront/origin; check the CloudFront distribution status and that `index.html` exists in the bucket.
   - **Certificate or DNS?** An expired ACM certificate or a changed Cloudflare record shows as a TLS/connection error. ACM renews itself only while the DNS validation record exists in Cloudflare.
   - **Domain expired?** `zihao-cv.site` expires 2027-02-02 — check the registrar.
   - Page loads but the content is wrong (blank / wrong file) -> [roll back the website](#roll-back-the-website).
3. **API down?** `curl -s https://ubnjbwuf9e.execute-api.us-east-1.amazonaws.com/health` and continue with [lambda-errors](#lambda-errors).

---

## Procedures

### Roll back a bad deploy

Preferred, and always safe: revert through the pipeline.
```
git checkout main && git pull
git revert <merge-commit-sha>          # creates the opposite change
git checkout -b revert/<name> && git push -u origin HEAD
gh pr create --fill                    # checks + plan comment, then squash-merge
```
The deploy workflow applies the revert and runs the smoke test.

### Roll back the website

The bucket is versioned, so a bad `index.html` can be restored in minutes. This is an **emergency** measure: Terraform will notice the file no longer matches the code, so follow it with a normal PR.

```
B=zihao-resume-dev-2026-v99
aws s3api list-object-versions --bucket $B --prefix index.html \
  --query 'Versions[].[VersionId,LastModified,IsLatest]' --output table
aws s3api copy-object --bucket $B --key index.html \
  --copy-source "$B/index.html?versionId=<GOOD_VERSION_ID>" --content-type text/html
aws cloudfront create-invalidation --distribution-id E32881U4Y5ZDYR --paths "/*"
```
Then fix the cause in the repo; the next deploy re-uploads `src/website/index.html`.

### Restore the counter table

DynamoDB point-in-time recovery restores into a **new table**; it never overwrites the original. The table has `prevent_destroy`, and the Lambda points at `visitors-dev`, so for this one-item table the simplest recovery is to copy the value back.

```
# 1. Restore to a moment before the damage (window: last 35 days)
aws dynamodb restore-table-to-point-in-time \
  --source-table-name visitors-dev --target-table-name visitors-restored \
  --restore-date-time 2026-10-20T10:00:00Z          # or: --use-latest-restorable-time
aws dynamodb wait table-exists --table-name visitors-restored

# 2. Read the good value
aws dynamodb get-item --table-name visitors-restored --key '{"id":{"S":"count"}}'

# 3. Write it into the live table (admin credentials; the Lambda cannot do this)
aws dynamodb put-item --table-name visitors-dev \
  --item '{"id":{"S":"count"},"visitor_count":{"N":"<VALUE>"}}'

# 4. Clean up (the restored table costs money while it exists)
aws dynamodb delete-table --table-name visitors-restored
```
If `visitors-dev` itself was deleted: restore it under the original name instead, then `terraform import` it (see the import block pattern in `bootstrap/`).

### Confirm the alert subscription

After the first deploy of the monitoring module, AWS emails a confirmation link to the alert address. Until it is clicked the subscription is `PendingConfirmation` and **no alarm email is sent**. Check:
```
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:us-east-1:030342421998:zihao-cv-alerts \
  --query 'Subscriptions[].SubscriptionArn'
```
`PendingConfirmation` = not confirmed yet. Test the whole path by forcing an alarm:
```
aws cloudwatch set-alarm-state --alarm-name zihao-cv-lambda-errors --state-value ALARM --state-reason "alert test"
```
An email arrives within a minute; the alarm returns to `OK` by itself at the next evaluation.

### Drift

A GitHub issue labelled `drift` means AWS no longer matches `main`: the issue contains the plan. Either someone changed a resource by hand (revert it in AWS, or write the change into the code), or a deploy only half-applied (re-run it: `gh run rerun <id> --failed`). The issue closes itself on the next clean nightly run.

### Cost

- **Budget email:** open Billing -> Cost Explorer, group by *Service*, last 7 days, and find the line that grew.
- **Anomaly email:** it names the service and the root cause AWS found.
- Usual suspects on this account: API Gateway or Lambda requests (abuse -> [lambda-throttles](#lambda-throttles)), CloudWatch Logs ingestion, a forgotten restored DynamoDB table, X-Ray beyond the free tier.

## Where things are

| Thing | Name |
|---|---|
| Site / API | https://zihao-cv.site · `ubnjbwuf9e.execute-api.us-east-1.amazonaws.com` |
| Lambdas | `counter-dev`, `uptime-dev` |
| Table | `visitors-dev` (point-in-time recovery on) |
| Website bucket / distribution | `zihao-resume-dev-2026-v99` · `E32881U4Y5ZDYR` |
| Log groups | `/aws/lambda/counter-dev`, `/aws/lambda/uptime-dev`, `/aws/vendedlogs/apigateway/api-dev` (30 days) |
| Alert topic | `zihao-cv-alerts` |
| Terraform state | `s3://zihao-tfstate-030342421998/` (`prod/…` and `bootstrap/…`) |
