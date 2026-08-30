# A1-D Managed Email-Domain Activation

Status: approved 2026-08-29. This prerequisite pauses A1 live verification; it does not create a separate
campaign.

## Outcome

From the Jafar organization page, one **Activate email** action starts a resumable workflow that preserves the
contractor's normal root mailbox, reconciles `mail.contractor.com` for sending and
`reply.contractor.com` for receiving, writes only UCRM-owned DNS records through Cloudflare, verifies Brevo,
registers the receiving-domain webhook, and exposes truthful progress/recovery. Contractors never handle DNS.

Use the standard desired-state controller/saga pattern: each provider step is idempotent, durable state records
what is complete, and Recheck safely resumes after DNS propagation or partial provider failure. Never hold a
database transaction across Brevo or Cloudflare calls.

## Implementation sequence

1. **Preflight and model.** Verify current Brevo API behavior and remote schema. Reuse
   `communication_email_domains` for both purposes; add only the smallest state needed to persist the receiving
   domain's opaque webhook id. Load Postgres best practices before any migration.
2. **Provider adapters.** Add a server-only Cloudflare DNS adapter and the missing Brevo inbound-webhook
   management calls. Use a token limited to Zone Read + DNS Edit on managed zones. No provider secret or raw
   credential enters a browser response.
3. **Reconciler and route.** Add an owner-only, Zod-validated, rate-limited activation/recheck command. Resolve
   the exact Cloudflare zone, preserve root MX/mailbox auth, refuse occupied/conflicting prefixes, create or
   reuse both Brevo domains, upsert only exact expected records, authenticate when resolvable, create or reuse
   the domain webhook, and finalize verified rows. Record an owner audit event and support idempotent replay.
4. **Owner UI.** Extend the existing `EmailDomainActions` surface rather than add a new page. Show mailbox
   protection, sending domain, receiving domain, webhook and canary readiness; expose records under Technical
   details for diagnosis. The contractor Email Settings page remains sender-identity management only.
5. **Verification.** Cover authorization, tenant isolation, replay, pre-existing provider resources, DNS
   propagation, conflicts, partial failure, duplicate prevention, root-record preservation, replacement and
   cleanup. Run focused server/database/UI checks, then the live fixture below.

## Live reconciliation fixture

- Existing sending domain: `test.upliftcontractor.com`.
- Existing Brevo receiving registration: `reply.test.upliftcontractor.com` (provider id
  `6a926295628c23a1d7062d73`); its current provider-issued authentication records plus two inbound MX records
  are not yet in Cloudflare.
- `BREVO_INBOUND_WEBHOOK_TOKEN` exists in `.env`; the app must restart before the live webhook test.
- No Cloudflare DNS token exists yet. Live activation waits for a server-only token scoped to
  `upliftcontractor.com`; no broader permission is approved.

The workflow must discover/reuse this partial setup, not duplicate it. Passing means Cloudflare records are
active, Brevo reports the receiving domain authenticated, exactly one domain webhook points to the secured
shared endpoint, the verified receiving row exists, and a new outbound intent mints a reply alias.

## Failure and safety rules

- Never overwrite or delete root MX, root mailbox authentication, or an unexpected DNS record.
- CNAME and mail-related records stay DNS-only. Record counts and values come from Brevo at runtime.
- Unknown/occupied `mail.` or `reply.` names stop for owner review; do not invent another prefix silently.
- A provider timeout remains retryable/unknown, never reported as success. Cleanup deletes only exact resources
  UCRM can prove it owns and keeps the webhook id for retryable cleanup.
- No throughput or 40,000-tenant claim follows from this part; evidence covers the exercised launch workflow.

## Completion and continuation

Completion gate: the live fixture passes through the same owner workflow intended for contractors, with tests
and a rehearsed retry after one partial failure. Then resume A1-V at the reply canary, followed by attachment,
bounded backlog and one-day soak.

## Preflight findings (2026-08-29)

- SCHEMA already models receiving domains fully. `communication_email_domains` has `purpose`
  CHECK('sending','receiving'), `inbound_mx_status`, and constraints: `purpose_health_check` (receiving keeps
  dkim/dmarc/spf='unchecked' + provider_authenticated=false; sending keeps inbound_mx_status='unchecked') and
  `verified_state_check` (receiving 'verified' needs provider_verified + ownership_status='passing' +
  inbound_mx_status='passing'). So "reuse the table for both purposes" is already done.
- ONLY MISSING STATE = the opaque Brevo inbound-webhook id (contract §Suspension/closure requires persisting it
  per receiving domain for retryable cleanup). MIGRATION DESIGN (additive, NOT yet applied — apply next session
  with the adapter/reconciler + tests): `alter table public.communication_email_domains add column
  provider_inbound_webhook_id text;` + CHECK `(provider_inbound_webhook_id IS NULL) OR (purpose='receiving')`.
  No other columns needed. Base any fn changes on remote pg_get_functiondef, not migration files.
- AUTH PATTERN CORRECTION: the LIVE transactional webhook (id 2148798) authenticates with Brevo's native
  `auth:{type:'bearer',token}` (sends `Authorization: Bearer <token>`), NOT custom `headers`. The reconciler's
  inbound-webhook create must use `auth:{type:'bearer',token:BREVO_INBOUND_WEBHOOK_TOKEN}` to match our route,
  which reads the Authorization header. (Earlier plan to use headers[] is superseded.)
- LEGACY CRUFT to reconcile/clean (do NOT clobber): Brevo already has verified+auth domains `test.` (test org
  sending), plus platform `contact.`, `notifications.`, and `replies.upliftcontractor.com`. `replies.` has an
  OLD inbound webhook (id 2021984) using a token-IN-PATH url `/api/webhooks/brevo/inbound/<tok>/replies…`, which
  the current fixed `/api/webhooks/brevo/inbound` route would 404 — orphaned, no DB row, a later cleanup target.
  `reply.test.upliftcontractor.com` (id 6a926295628c23a1d7062d73) is auth=false/verified=false (DNS not added).
- Reconciler must discover/reuse all of the above idempotently; globally-unique domain claim is enforced by
  `communication_email_domains_provider_id_key UNIQUE(provider,provider_domain_id)`.
