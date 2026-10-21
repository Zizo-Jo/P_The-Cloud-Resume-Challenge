# Runbook

What to do when something alerts. Every alarm email links to a section here.
All commands assume `export AWS_PROFILE=zihao-admin AWS_REGION=us-east-1 AWS_PAGER=""` after `aws sso login --sso-session zihao`.
`AWS_PAGER=""` matters: without it, output opens in a pager (`(END)`, press `q`), the command looks stuck, and running it again can apply a change twice (Game Day 2026-10-21).

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

**Means:** `counter-dev` raised an **unhandled** exception: a crash, a timeout, an import error. Visitors see no counter (the page itself still loads).

> **This alarm does NOT fire for DynamoDB errors** such as `AccessDeniedException`: the handler catches them and returns 500/503, so Lambda counts the run as a success. Those show up as [api-5xx](#api-5xx) and [site-down](#site-down). (Found in Game Day 2026-10-21.)

1. **Read the error.** The Lambda logs the full stack trace and returns only a generic message:
   ```
   aws logs tail /aws/lambda/counter-dev --since 30m --filter-pattern "ERROR"
   ```
2. **Typical causes**
   - A code bug from the latest deploy (syntax error, bad import) -> step 3.
   - Timeout -> check X-Ray (step 4) for the slow call.
   - DynamoDB errors are handled in the code, see [api-5xx](#api-5xx).
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

**Means:** API Gateway returned a 5xx to a visitor. This is the **first** alarm for most backend problems, including the ones the Lambda catches itself (Game Day 2026-10-21: detected a removed IAM permission in 3 minutes).

1. Which route and when? The access log has one JSON line per request:
   ```
   aws logs tail /aws/vendedlogs/apigateway/api-dev --since 30m --filter-pattern '{ $.status = 5* }'
   ```
2. Read `integrationStatus` correctly:
   - `integrationStatus` **200** + `status` 500/503 = the Lambda **ran** and returned an error on purpose (it caught an exception). The reason is in the Lambda log, step 3.
   - `integrationStatus` 5xx or missing = the Lambda crashed or timed out -> [lambda-errors](#lambda-errors).
   - No Lambda log line at all for that request = API Gateway itself (check the AWS Health Dashboard).
3. **The real error is in the Lambda log:**
   ```
   aws logs tail /aws/lambda/counter-dev --since 30m --filter-pattern ERROR
   ```
   - `AccessDeniedException ... dynamodb:GetItem/UpdateItem` -> the Lambda role lost its permission. **Who changed it, when:**
     ```
     aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=PutRolePolicy --max-results 3 \
       --query 'Events[].[EventTime,Username]' --output text
     ```
     Fix: re-run the deploy (`gh workflow run deploy.yml --ref main`); Terraform puts the reviewed policy back. Do not re-type the policy by hand: it is easy to drop the `LeadingKeys` condition.
   - `ResourceNotFoundException` -> the table is missing; [restore the counter table](#restore-the-counter-table).
4. Cause found in the code -> [roll back a bad deploy](#roll-back-a-bad-deploy).

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

The bucket is versioned, so a bad `index.html` can be restored in minutes.

**Which version is the good one?** Not the latest (that is the bad one). Pick the newest version that is **older than the incident** and has a **normal size** (the real page is ~45 KB; Game Day 2026-10-21's broken upload was 70 bytes). Version IDs are random strings: identify versions by time and size.

If the restored version is the one in `main`, Terraform sees no difference (same ETag). If it is not, follow up with a normal PR. If the bad file never came from the repo, **re-running the deploy** also fixes it (`gh workflow run deploy.yml --ref main`), just slower.

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

# 3. Add it back to the live table, ATOMICALLY (admin credentials; the Lambda cannot do this)
#    Visits keep arriving after the damage, so the right value is BACKUP + CURRENT.
#    Do not read, add in your head and put-item: a visit in between is lost.
#    ADD is not idempotent: running it twice adds twice. The condition makes a
#    second run fail instead (CURRENT_MAX = the live value right now + a margin).
aws dynamodb update-item --table-name visitors-dev --key '{"id":{"S":"count"}}' \
  --update-expression "ADD visitor_count :backup" \
  --condition-expression "visitor_count < :max" \
  --expression-attribute-values '{":backup":{"N":"<VALUE>"},":max":{"N":"<CURRENT_MAX>"}}' \
  --return-values UPDATED_NEW

# 4. Check the live value, THEN clean up (the restored table costs money while it exists).
#    Read the table name twice: visitors-RESTORED, not visitors-dev.
aws dynamodb delete-table --table-name visitors-restored
```
Expect 5–20 minutes for the restore even for one item. `LatestRestorableDateTime` lags about 5 minutes behind now.
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
