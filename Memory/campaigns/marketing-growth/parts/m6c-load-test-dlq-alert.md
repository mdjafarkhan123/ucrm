# M6c: Load test + DLQ alert

## Approved behavior

- Jafar picked (2026-09-23): app-level DLQ alert now (email + in-app, reusing `raiseOwnerAlert`); a
  direct CloudWatch/SNS alarm is deferred as a low-priority later item, not built now.
- Jafar picked: load test burst size > 500 recipients (using AWS SES mailbox simulator `success+<id>@simulator.amazonses.com`
  plus-addressing -- confirmed real AWS pattern, an official AWS sample repo load-tests SES this exact way).

## DLQ alert plan

- Add `sesEventDlqUrl(env)` next to `sesEventQueueUrl` in `src/lib/server/communications/ses-env.ts` (same
  region/account, queue name `ucrm-ses-events-dlq`).
- In `runMonitoredMarketingEventsWake` (`src/lib/server/marketing/event-consumer.ts`), after draining the main
  queue, call `GetQueueAttributesCommand` (`ApproximateNumberOfMessages`) on the DLQ.
- If depth > 0: check for an existing unread `platform_owner_notifications` row with
  `kind = 'marketing_ses_dlq_message'` created in the last 24h (no new table needed) -- only call
  `raiseOwnerAlert` if none exists, so it doesn't spam every minute while stuck messages remain.
- Add `marketing_ses_dlq_message` to `EMAIL_ALERT_KINDS` in `src/lib/server/jafar/owner-alerts.ts` so it emails
  too.
- Known pre-existing gap (not caused or fixed by this part): both marketing wake pg_cron jobs fail every
  minute today because their Vault target-URL secrets are unset, so this route only runs when manually
  invoked (same limitation M5's real send already worked around). Verify by manually POSTing to
  `/api/internal/communications/marketing-events-worker` with a real stuck DLQ message, same as prior
  verification. Flag the cron/Vault wiring to Jafar as separate, pre-existing, production-cutover-scoped work.

## Load test plan

- Baseline: trigger ~10-20 real operational emails (e.g. invoice/quote send) in Raad LTD, record end-to-end
  latency (send-triggered to provider-accepted) as the pre-burst target.
- Seed >500 synthetic customers in Raad LTD via real `POST /api/customers` calls (a script, not raw SQL), each
  emailed `success+loadtest-<n>@simulator.amazonses.com`, marketing-consented, clearly named/tagged
  "load test (safe to delete)".
- Build one customer group matching them; launch one real campaign via the real launch API.
- While the dispatcher works through the burst, fire the same operational-email batch again and remeasure
  latency; poll recipient status counts / dispatcher claim timestamps for throughput, queue age, and error rate.
- Compare burst-time operational latency against baseline; report per the performance-review verify template.
- Clean up: cancel test campaign, delete synthetic customers/group afterward.

## DLQ alert: DONE 2026-09-23, real end-to-end proof

Built exactly as planned: `sesEventDlqUrl` (`ses-env.ts`), `checkDlqAndAlert` + `DlqClientLike` in
`event-consumer.ts`, `marketing_ses_dlq_message` added to `EMAIL_ALERT_KINDS`. 14 unit tests pass
(3 new: alerts once, suppressed while unread, no-op at depth 0).

Real bugs found and fixed along the way (not synthetic):
1. The real `ucrm-ses-events-dlq` already held 2 stuck messages nobody knew about -- AWS's own
   "Successfully validated SNS topic for Amazon SES event publishing." confirmation text, sent once per
   contractor sender setup, is never JSON, so it silently poisoned the queue and dead-lettered after 5
   receives. Fixed: `recordOneMessage` now recognizes and discards this exact string (new `ignored`
   outcome) before it ever reaches the DLQ, so future contractor onboarding won't trigger false alerts.
2. The app's AWS IAM user (`ucrm-marketing-ses-worker`, policy `UcrmMarketingSesEventsQueueAccess`) had
   `sqs:GetQueueAttributes` scoped only to the main queue ARN, not the DLQ. Jafar approved (2026-09-23)
   adding the DLQ ARN as a second resource on that same policy (now v2) -- read-only, no send/receive/delete
   rights added.

Live-verified against the real AWS account: triggered `/api/internal/communications/marketing-events-worker`
manually (bearer secret, same route M5 used) with the 2 real stuck messages present -- got one real urgent
`platform_owner_notifications` row and one real `owner_alert` email queued and sent to
dev.jafarkhan@gmail.com. Triggered a second time immediately after: zero new notifications (dedupe by
unread-in-last-24h confirmed). DLQ still holds those 2 harmless messages -- cleanup (deleting them) was
blocked mid-session by the auto-mode classifier (scripted bulk delete) and then AWS SSO token expiry; ask
Jafar to either clear them via the AWS console himself or approve individual (non-looped) deletes next
session.

Known pre-existing gap, not fixed here (flagged to Jafar, out of scope): both marketing pg_cron wake jobs
still fail every minute because their Vault target-URL secrets are unset, so this whole pipeline -- draining
the main queue, and now the DLQ check riding on it -- only runs when someone manually triggers the route,
not automatically every minute. That wiring is production-cutover-scoped work, not M6c's.

## Next action

Load test not started. Plan above stands: baseline operational-email latency, seed >500 synthetic
customers via real `POST /api/customers` calls with `success+loadtest-<n>@simulator.amazonses.com`
addresses, launch one real campaign, remeasure operational latency during the burst, compare, clean up.
