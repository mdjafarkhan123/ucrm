# Brevo return-path production patterns

Research date: 2026-08-28

## Question

Does the proposed R1 callback worker plus R2 inbound-reply setup follow mature production patterns for Brevo, and what must change before approval?

## Verdict

The sequence is sensible: finish delivery-event handling before turning on client replies. The plan should **not be approved verbatim**, however.

1. The transactional webhook's durable raw-event table is a **webhook inbox / ingress journal**, not an outbox. An outbox reliably publishes an event after an application database change; AWS defines it around the database-write-plus-outbound-notification dual-write problem. The mature inbound shape is authenticate, validate, durably record with a unique key, return success quickly, then process asynchronously. Stripe's official webhook guidance explicitly calls for duplicate handling, asynchronous processing, and a quick `2xx`. [AWS transactional outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html), [Stripe webhook best practices](https://docs.stripe.com/webhooks)
2. A new HTTP callback-worker is not the first fix indicated by the repository. The committed migration already schedules `process_communication_provider_callbacks(500)` every two minutes through `pg_cron` ([migration](../../supabase/migrations/20260906180000_communications_email_suppression_and_callback_processing.sql#L527)). Supabase supports running database functions directly as Cron jobs and records runs in `cron.job_run_details`. If the managed database has the function but not the job, first determine whether this is migration drift, a disabled job, or a failed Cron installation/run. Restore and verify the declared scheduler unless there is an approved architecture decision to replace it; adding an HTTP route and a second scheduler creates two control paths for the same pure-SQL consumer. [Supabase Cron](https://supabase.com/docs/guides/cron), [Supabase pg_cron debugging](https://supabase.com/docs/guides/troubleshooting/pgcron-debugging-guide-n1KTaz)
3. Brevo's current webhook API documents optional `auth` and custom `headers` on the same create-webhook request that supports `type: "inbound"` and a receiving `domain`. Brevo separately documents bearer-token and custom-header webhook authentication. It does not document an inbound-only exclusion. Therefore header authentication is the supported first choice; a secret embedded in `/inbound/[secret]/...` is a fallback only if an account-level create/update test proves Brevo rejects `auth` for this inbound webhook. OWASP advises keeping security tokens out of URLs because URLs are commonly logged. [Create webhook](https://developers.brevo.com/reference/create-webhook), [secure webhook calls](https://developers.brevo.com/docs/secured-webhooks), [OWASP REST security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html)
4. The inbound route is not currently durable end to end. It inserts a callback row, calls `record_communication_inbound_message`, logs an RPC failure, and still returns `2xx`; on a retry, the duplicate callback insert exits before re-running the failed RPC ([route](../../src/routes/api/webhooks/brevo/inbound/+server.ts#L27)). That can permanently strand a valid reply. R2 needs either one atomic database operation for receipt plus message creation or an inbox row with processing state, retry attempts, and a worker that can resume after partial failure.
5. "Validate SPF/DKIM from the payload" is not a safe hard gate as written. Brevo documents `Headers` and a spam score in the inbound payload, but no first-class `SPFCheck` or `DKIMCheck` field. `Authentication-Results` is only trustworthy when the consumer has established the producing mail system's trust boundary and trusted `authserv-id`; the RFC also warns that even a legitimate pass does not make a message trustworthy. SPF authenticates the SMTP `MAIL FROM`/HELO identity, not the visible author, and DMARC is what checks alignment with the RFC5322 `From` domain. Treat trustworthy, receiver-added DMARC/SPF/DKIM results as risk signals, not as webhook authentication or an unconditional reply-rejection rule. [Brevo inbound payload](https://developers.brevo.com/docs/inbound-parse-webhooks), [RFC 8601 trust and forged headers](https://www.rfc-editor.org/rfc/rfc8601.html), [RFC 7208 SPF identities](https://www.rfc-editor.org/rfc/rfc7208.html), [RFC 7489 DMARC alignment](https://www.rfc-editor.org/rfc/rfc7489.html)

## R1: durable delivery-event processing

### Receiver and scheduling

Keep the existing separation between receipt and processing:

- Authenticate the webhook before accepting the body. Prefer Brevo bearer/custom-header authentication plus Brevo IP allowlisting at the edge; rotate a long random endpoint-specific token. Brevo does not document a signed-body/timestamp scheme, so static-token authentication does not itself prevent replay; durable deduplication remains required. [Brevo secure webhooks](https://developers.brevo.com/docs/secured-webhooks)
- Validate a bounded request body and persist the original provider payload before returning `2xx`. The transactional route already follows this basic shape ([route](../../src/routes/api/webhooks/brevo/transactional/+server.ts#L14)).
- Process bounded batches idempotently and continuously. A manual invocation proves the function, but it does not complete concerns 2-4 in production. The production gate is an enabled recurring trigger, successful run history, bounded callback age/backlog, and an alert when the oldest unprocessed item or failed-run count crosses an agreed threshold. Supabase records Cron status and history for this purpose. [Supabase Cron](https://supabase.com/docs/guides/cron)
- Add reconciliation against Brevo's transactional event API/export because provider retries are not a durable queue. Brevo currently says most `4xx` responses and **all `5xx` responses stop retries and discard the webhook event**; only an unresponsive endpoint and `429` enter its four-retry schedule. Its transactional event API can retrieve recent provider activity. [Brevo retry mechanism](https://developers.brevo.com/docs/retry-mechanism), [transactional event report API](https://developers.brevo.com/reference/get-email-event-report)

If the team deliberately replaces database Cron with an application worker, make it one approved owner: remove/unschedule the database job in the same cutover, run the application worker recurrently (not manually), and preserve the same backlog/run monitoring.

### Idempotency, correlation, and ordering

The proof should cover more than one happy-path hard bounce:

- Redeliver the identical event and prove one raw inbox record and one set of effects.
- Deliver two different events for one message out of order and prove an older `deferred`/soft-bounce event cannot overwrite a newer `delivered` or terminal result. Mature webhook consumers cannot assume delivery order; Stripe explicitly documents this constraint. [Stripe event delivery behavior](https://docs.stripe.com/webhooks)
- Do not use Brevo's email-event `id` alone as the deduplication key: Brevo describes it as the **webhook ID**, not a unique event ID. Use a documented stable provider identifier where available, otherwise a tested composite/hash including message identity, event kind, and the provider event time at its highest supplied precision. [Brevo transactional webhook schema](https://developers.brevo.com/docs/transactional-webhooks)
- Correlate by the application's tag and stored provider message ID, with quarantine/retry for unresolved events. Brevo's documented `unsubscribed` sample exposes a serialized singular `tag`, while other events commonly expose `tags`; the current parser only uses `tags` ([parser](../../src/lib/server/communications/brevo-webhook.ts#L5)). A missing or temporarily unresolved correlation should not be marked processed and forgotten.
- Record attempts, last error, next-attempt time, and a terminal review/dead-letter state. Processing should be safe after a crash between any two effects.

### Event policy and suppression scope

Use an explicit event matrix:

| Brevo event | Production action |
| --- | --- |
| `hard_bounce`, `invalid_email` | Mark the message permanently failed and suppress that bad address locally. Brevo automatically blocklists hard-bounced addresses. |
| `deferred`, `soft_bounce` | Show a temporary failure; do not immediately create a permanent transactional suppression. Brevo retries deferred email for up to 36 hours, then marks a soft bounce, and does not apply its five-consecutive-soft-bounce marketing rule to transactional email. |
| `spam` | Record a complaint and immediately stop optional/promotional mail. Surface that the email channel may be provider-blocked even for otherwise essential sends, so the operator can correct consent or use another channel. |
| `blocked` | Mark the attempt blocked, do not blindly retry, and reconcile the provider blocklist with local state. |
| `unsubscribed` | Record and enforce the exact opt-out scope. A Brevo transactional unsubscribe is sender-specific by default; a marketing campaign unsubscribe is a different suppression scope. |
| `error` or unknown | Preserve the raw value and reason, surface it for review, and quarantine rather than silently normalize it to an innocuous event. |

Brevo's official definitions support this hard/soft distinction and its separate campaign versus transactional blocklists. [Brevo bounce handling](https://help.brevo.com/hc/en-us/articles/209435165-What-are-soft-bounces-and-hard-bounces-in-email), [Brevo blocklist scopes](https://help.brevo.com/hc/en-us/articles/209458705-FAQs-What-are-the-different-types-of-blocklisted-contacts), [Brevo event types](https://developers.brevo.com/docs/transactional-webhooks)

The current database does **not** yet justify the plan's claim that R1 enforces unsubscribes. Its suppression reason constraint allows only `complaint` and `hard_bounce` ([migration](../../supabase/migrations/20260906180000_communications_email_suppression_and_callback_processing.sql#L21)); the processor normalizes `unsubscribed` but creates suppression rows only for complaints and hard bounces ([current function](../../supabase/migrations/20260906200100_communications_email_reputation_sweep_queue.sql#L82)). Before implementing unsubscribe suppression, approve a scope model capable of at least organization, address, stream/purpose (marketing versus operational), and transactional sender/category where applicable. A marketing opt-out must not silently disable valid essential operational mail, while a sender-specific transactional opt-out must not be widened accidentally.

"Failure visibility" also needs the provider reason and operational health, not only a normalized label. The current processor sets `delivery_outcome_detail` to the event name rather than Brevo's `reason` ([current function](../../supabase/migrations/20260906200100_communications_email_reputation_sweep_queue.sql#L104)). The acceptance proof should show the recipient-facing message status/reason, the blocked-address entry when appropriate, and the callback backlog/worker failure to an operator.

## R2: inbound replies

### Domain and Reply-To

This part of the proposal matches Brevo's supported model:

- Use a dedicated receiving subdomain different from the sending domain, verify it with Brevo, and point MX priority 10 and 20 to `inbound1.sendinblue.com` and `inbound2.sendinblue.com`. Register an inbound webhook with `type: "inbound"`, `inboundEmailProcessed`, and that receiving domain. Brevo accepts any local part at the delegated domain. [Brevo inbound parse setup](https://developers.brevo.com/docs/inbound-parse-webhooks)
- Create an opaque per-conversation or per-client alias on that verified receiving domain and pass it through Brevo's `replyTo` send parameter. RFC 5322 defines `Reply-To` as the suggested destination for replies; without it, clients normally reply to `From`. [Brevo send API](https://developers.brevo.com/reference/send-transac-email), [RFC 5322 Reply-To](https://www.rfc-editor.org/rfc/rfc5322.html)
- Onboard the subdomain in the application's existing `purpose = 'receiving'` model rather than pretending it is a sender-authentication domain ([reply-alias model](../../supabase/migrations/20260825120000_communications_reply_alias_foundation.sql#L3)).

### Routing and security

- Authenticate the **webhook call** with Brevo-configured bearer/custom headers and IP allowlisting. Constant-time comparison is appropriate for the token, but it does not improve a token's storage location. If an account-level API test forces a URL secret, use a high-entropy endpoint-specific value, exclude/redact the path from access logs and error reporting, and document rotation.
- Resolve the tenant and alias from the actual SMTP envelope recipient. Brevo documents `Recipients` as the `RCPT TO` recipients, while `To` and `Cc` are message header fields. The current parser does not model `Recipients`, and `candidateRecipients` only walks `To` and `Cc` ([parser](../../src/lib/server/communications/inbound-email.ts#L15), [routing](../../src/lib/server/communications/inbound-email.ts#L50)). Validate that the envelope recipient's domain is an active, verified receiving domain and that the opaque alias belongs to it. [Brevo inbound payload](https://developers.brevo.com/docs/inbound-parse-webhooks)
- Prefer Brevo's inbound UUID as the provider receipt identity. Brevo exposes that UUID through its inbound-event API; `MessageId` is explicitly the sender-supplied `Message-ID` header and should not be the sole primary dedupe authority. The current helper prefers `MessageId` over `Uuid` ([dedupe helper](../../src/lib/server/communications/inbound-email.ts#L147)). [Brevo inbound event API](https://developers.brevo.com/reference/get-inbound-email-events), [inbound event history API](https://developers.brevo.com/reference/get-inbound-email-events-by-uuid)
- Keep unknown aliases, authentication anomalies, and parsing failures in a bounded review/quarantine path. Do not attach a message to a client merely because its visible `From`, `To`, SPF, or DKIM field looks plausible.

### Required proof before enabling replies

1. A new outbound canary contains the expected opaque `Reply-To` alias and the alias domain's MX records reach Brevo.
2. A Gmail reply appears once in the correct client's communication history, including text and a safe attachment case.
3. Replaying the same inbound payload creates no duplicate, while a forced failure after durable receipt is retried internally and eventually creates the message.
4. Invalid authentication, an inactive/wrong receiving domain, an unknown alias, and a forged visible `To` address cannot cross organizations; the real `Recipients`/`RCPT TO` value controls routing.
5. SPF/DKIM/DMARC pass, fail, none, and forwarding cases are observed and classified without silently dropping legitimate mail. Any hard rejection rule is approved only after the exact Brevo-added authentication header and trusted `authserv-id` have been proven from real payloads.
6. Inbound backlog age, failed processing attempts, and Brevo's inbound event history are visible enough to detect a lost reply. Brevo's inbound API records `webhookFailed` and `webhookDelivered` lifecycle events, which can support reconciliation. [Brevo inbound event history](https://developers.brevo.com/reference/get-inbound-email-events-by-uuid)

## Recommended approval response

Approve the two-slice order, but return R1/R2 for these amendments before coding:

- diagnose and restore the already-declared `pg_cron` callback job instead of adding a second worker route unless the scheduling architecture is intentionally replaced;
- add idempotent retry/quarantine, out-of-order tests, reconciliation, backlog/run monitoring, and provider failure reasons;
- define and implement sender/purpose-scoped unsubscribe behavior before claiming unsubscribe enforcement;
- use Brevo bearer/custom-header authentication for inbound unless an account-level API test disproves the documented support;
- route using `Recipients`/`RCPT TO`, fix the current partial-failure reply-loss path, and treat SPF/DKIM/DMARC only as authenticated message-risk signals.

The stale legacy webhook can be deleted only after its ID, account ownership, subscribed events, and lack of recent deliveries are recorded and the surviving endpoint has passed the duplicate/failure tests. That deletion is operational cleanup, not part of the durability design.
