# Marketing First-Release Implementation Plan (M0)

**Status:** Approved by Jafar 2026-09-18 — implementation and provider setup remain separately gated
**Product truth:** `docs/marketing-product-blueprint.md` (approved 2026-09-15). This plan changes no approved
behavior except where §2 asks Jafar to confirm the delivery provider and its technical boundary.
**Authority:** Approval starts M1 only. Each schema, RLS, permission, provider-account, or package change still
needs its normal explicit approval.

Current provider evidence: `docs/research/amazon-ses-marketing-campaign-architecture-2026-09-18.md`.

## 1. What already exists and will be reused

| Need | Existing foundation | Reuse |
| --- | --- | --- |
| Queue, claim, retry, lease, wake ledger | Email outbox: `claim_communication_outbox_event`, `runBoundedDrain`, `runMonitoredEmailWake` | Same pattern for a separate Marketing dispatcher with its own worker name, lease, and rate budget |
| Suppressions, reputation pause, warm-up | `communication_email_suppressions`, `..._reputation_state`, `..._warmup_stages` | Read as-is at claim time; Marketing never weakens them |
| Allowance periods and usage | `communication_email_allowance_periods`, `..._usage_events` | Mirror shape for a separate Marketing allowance |
| Consent-evidence pattern | `communication_sms_consent_events` / `..._consent_state` | Same event + current-state shape for Marketing email consent |
| Customer contact policy | `clients.contact_policy` (`allow`/`no_marketing`/`do_not_disturb`) | Exclusion reasons |
| Package + role gating | `features`, `feature_overrides`, `requireOrganizationPermission` (`automations` precedent) | New `marketing` feature + three permissions |
| Call-to-action destination | Public forms at `/forms/[orgSlug]/[formSlug]` | Recipient-bound tracked link |
| Replies | Unified inbox + inbound email routing | Campaign as message origin |
| Sender identity | Verified organization senders + domain health | Marketing sender picked from these |

Not reused, deliberately: the operational send queue. Contractor Marketing and operational email both use SES, but
each keeps a separate queue, worker budget, configuration set, and reputation/readiness controls.

## 2. Approved delivery boundary — Amazon SES

**Finding (verified 2026-09-18 against Brevo docs):** in one Brevo account, a contact is one email address; an
unsubscribe, complaint, or hard bounce blocklists that address from **every** campaign in the account; campaigns
must use Brevo's own unsubscribe link; personalization reads that shared contact record. UCRM runs one
platform-owned Brevo account for all contractors. So with the blueprint as written, one contractor's customer who
unsubscribes would silently stop receiving every other contractor's marketing, and a customer's name saved by one
contractor could appear in another contractor's email.

| Option | How it works | Trade-off |
| --- | --- | --- |
| **A. Brevo sub-account per contractor** (recommended first) | Brevo's own multi-brand feature: each contractor's Marketing runs in an isolated sub-account with its own contacts, blocklist, and API key. Campaigns released in UCRM-controlled batches. | Keeps one provider and the blueprint unchanged. Needs Brevo Enterprise (price set by Brevo sales) and confirmation that a contractor's domain can be authenticated in its sub-account while operational mail stays in the main account. One reply-to address per campaign batch. |
| **B. Second provider built for per-message bulk sending** (fallback) | Per-recipient sends through a provider that permits marketing over its API with separate streams (e.g. Postmark broadcast streams or Amazon SES). UCRM owns unsubscribe and pacing, reusing the existing outbox worker. | Exact per-recipient recheck, results, and reply aliases. Adds a second provider, extra DNS records during domain activation, and a small blueprint wording change. |
| C. Shared Brevo account as-is | — | Rejected: cross-contractor unsubscribe and personal-data leakage cannot be patched in UCRM. |

**Approved provider boundary 2026-09-19:** use **Amazon SES for contractor CRM operational and Marketing email** in
the dedicated production workload account; Brevo is only for UCRM/Jafar platform email. Use one SES Tenant per
organization, a contractor-specific verified identity and configuration set,
tenant-scoped bounce/complaint suppression, and the standard automatic reputation policy. Start on shared IPs;
dedicated IPs are not a launch dependency and would need measured, regular volume to be worthwhile.

SES is the delivery pipe, not UCRM's campaign database. UCRM owns consent evidence, the immutable recipient
snapshot, immediate one-click unsubscribe, pacing, cancellation, and recipient results. A bounded Marketing
worker sends one personalized recipient at a time through the SES v2 API. SES events flow through SNS to an SQS
queue and dead-letter queue, then an idempotent UCRM worker records the real outcome. This replaces the blueprint's
provider-campaign wording without changing the approved contractor experience: the contractor still confirms one
campaign once and UCRM delivers it gradually.

New AWS accounts begin in the SES sandbox. Production access, live quotas, pricing, the AWS Region, and tenant and
identity quota increases must be confirmed from the real account before any launch promise. The first pilot should
be one approved US contractor sending only to a small, recent, explicit-opt-in US audience. Other countries remain
disabled until the required legal review and customer terms are approved. No bought, scraped, or third-party list
is accepted.

**Approved 2026-09-19:** this SES boundary, the US-only controlled pilot, the dedicated production workload account,
US East (N. Virginia), the SES/SNS/SQS topology, and sandbox testing spend. This does not authorize DNS changes or
M1 schema/permission changes; those remain separately gated.

**Provisioned and proven 2026-09-20 (sandbox, account `881776924275`, `us-east-1`):** the event pipeline exists
and is verified end to end. Identity `mail.upliftcontractor.com` is fully verified (DKIM SUCCESS, custom MAIL FROM
`bounce.mail.upliftcontractor.com` SUCCESS). Config set `ucrm-internal-test-events` has event destination
`sns-all-events` for all seven event types (Send, Delivery, Bounce, Complaint, Reject, Delivery Delay, Rendering
Failure) → SNS topic `ucrm-ses-events` → SQS `ucrm-ses-events` (SSE-SQS on, raw message delivery, redrive
maxReceiveCount 5) → DLQ `ucrm-ses-events-dlq`. SNS topic policy allows only `ses.amazonaws.com` to publish (scoped
by `aws:SourceAccount`); the queue accepts only that topic. Three simulator sends produced the expected seven
events (success→Send+Delivery, bounce→Send+Bounce, complaint→Send+Delivery+Complaint); DLQ stayed empty. CLI access
is IAM Identity Center SSO, profile `ucrm` (short-lived, no long-lived keys on disk); re-auth with
`aws sso login --sso-session ucrm`. SNS topic is not KMS-encrypted (SSE-SQS only) — acceptable for internal test,
revisit before production.

**Original recommendation (superseded):** ask Brevo two factual questions now (Enterprise sub-account price at our
scale; domain authentication across main and sub-account). Choose A if both answers work; otherwise B. M1–M3 do
not depend on this choice and can proceed meanwhile.

## 3. Build slices

Each slice is one focused session, independently verifiable, and ends with its own browser/role check.

### M1 — Access, consent evidence, sender, and allowance
- **Feature and permissions (permission change — needs approval):** feature `marketing`; permissions
  `marketing.view`, `marketing.draft`, `marketing.launch`. Owner/admin get all three; no other role gets any by
  default (blueprint §14). `marketing.launch` is enforced in the launch command, not only the UI.
- **Consent evidence (schema — needs approval):** `client_marketing_consent_events` (append-only: email method,
  granted/withdrawn, source `public_form`/`staff`/`unsubscribe`/`complaint`, disclosure text version, occurred_at,
  actor) plus a current-state row per email method. Eligibility reads only this. The old `marketing` boolean holds
  no evidence and is not treated as consent; it is retired after one read-only count shown to Jafar.
- **Fix the dropped tick:** the public form already collects `email_marketing_consent` but never saves it. Record
  a `public_form` grant with the exact disclosure text shown.
- **Staff-recorded consent:** one Customer-page action recording a real verbal/written preference with source and
  date; no bulk grant.
- **Marketing unsubscribe:** UCRM-owned signed per-organization link and one-click `List-Unsubscribe`; records a
  withdrawn event immediately; never blocks operational email.
- **Allowance:** Marketing allowance periods mirroring the operational table; package values start **unset**, and
  launch stays disabled with "Marketing allowance not configured" until Jafar sets them. Launch reserves the
  eligible count atomically.
- **Readiness read:** one server function returning the blocking reasons in blueprint §6 (domain, business
  address, sender, pause, allowance, consent), shown on Marketing home with fix links.
- **UI:** Growth → Marketing nav entry; Marketing home shell with readiness, forbidden, and not-included states.

### M2 — Customer groups and exact recipient preview
- `marketing_customer_groups` stores rules as JSON validated by Zod against a fixed filter list (blueprint §8
  step 2). Rules compile to parameterized SQL in one database function; no user text becomes SQL.
- One preview function returns matches, eligible, excluded-by-reason, and duplicate-destination counts, plus a
  paged list. Frequency rule: at most one Marketing email per destination per organization in 7 days.
- **Performance design branch runs before building** (grows with Customers × work history per organization):
  EXPLAIN evidence on representative organization sizes, indexes justified by those plans, bounded pages.

### M3 — Drafts, goals, templates, editor
- `marketing_campaigns` (Draft with a revision number; a stale save is refused and reloaded, never overwritten,
  via a security-definer `marketing_update_campaign_draft` RPC mirroring `update_quote_draft`'s P0409 shape) and
  organization-owned `marketing_email_templates` storing blocks as JSON, copied from
  `marketing_platform_templates`' four starter templates on use (schema and seed applied 2026-09-20).
- Five-step full-page journey with explicit Save draft and leave-guard. Block editor: image, heading, text,
  button, divider, service summary. Server renders blocks to email HTML via MJML (the established,
  cross-client-safe library for this, not a hand-rolled table layout) and appends the locked footer (business
  identity, address, unsubscribe). Variables are a fixed allow-list (`customer_first_name`, `business_name`)
  enforced by Zod at save time; per-recipient missing-value handling is M4's job at launch time.
- **Test email moved to M4 (decided 2026-09-20):** research during M3 found that no code path sends contractor
  email via SES yet -- every current send (quotes, invoices, receipts) still goes through Brevo, and the
  approved provider boundary forbids Marketing from using Brevo (the cross-contractor blocklist problem §2
  exists to avoid). Building throwaway SES-calling code just for a test button would duplicate M4's real work
  and could not actually deliver yet anyway (the AWS account is still in SES sandbox, which only reaches
  pre-verified recipient addresses). Test email becomes a thin use of M4's real sender once it exists. The
  block editor's on-screen desktop/mobile preview is M3's stand-in for "see what it looks like" until then.

### M4 — Launch, gradual delivery, cancellation (after §2 decision)
- Builds the real "talk to Amazon SES" sending code for the first time (nothing sends via SES yet; every current
  operational email still goes through Brevo). Once that exists, add the M3 "send me a test email" action as a
  thin use of it: to the signed-in user's verified staff address only, clearly labelled, never counted against
  the Marketing allowance, no Customer address accepted (moved here from M3 -- see M3's note).
- Launch command (owner/admin, idempotency key, required review revision): freezes a campaign version, writes the
  recipient snapshot once, records exclusions, reserves allowance — all in one transaction.
- Separate Marketing dispatcher on its own wake: fair claims (a per-organization cap per wake), rechecks current
  consent, unsubscribe, suppression, contact policy, sender health, reputation pause, org state, cancellation,
  frequency, and allowance immediately before each recipient is released. It submits through SES v2 with the
  organization's Tenant and configuration set. Operational email keeps its own SES queue, worker budget,
  configuration set, and protected-capacity behavior.
- SES events arrive through SNS -> SQS/DLQ, are stored first, then projected idempotently onto recipient results
  (Submitted is never Delivered). Cancel stops unreleased recipients and states how many were already handed off.
- Reputation pause stops new Marketing release; only Jafar resumes; resume reruns eligibility.

**Decided while building M4 (2026-09-22/23, Jafar-approved):**
- Per-contractor verified SES identities, not a shared platform domain. Marketing sends from `news.<root>` with
  MAIL FROM `bounce.news.<root>`, separate from operational `mail.<root>`; domain purpose `marketing_sending`
  (so every `purpose='sending'` query keeps excluding it), and Marketing `verified` also requires SPF passing.
  One SES tenant and configuration set per organization (`communication_ses_tenants`, names derived as
  `ucrm-org-<orgId>` / `ucrm-marketing-<orgId>`).
- From address is `<operational sender local part>@news.<root>` with the same display name; Reply-To is the
  operational sender.
- Marketing reputation is measured on its own (complaints and hard bounces over Marketing recipients, same
  effective thresholds as operational) and engages a pause with `source='auto_marketing_reputation'`,
  `applies_to='marketing'` that never holds operational email. The coupling is one-way: any organization pause,
  including the operational reputation pause, still holds Marketing. Unsubscribes are not a Marketing pause signal.
- Organization-wide holds are filtered in the Marketing claim's candidate query, so one held organization's
  queue cannot starve other organizations.
- Pointing activation at a real contractor's live domain needs Jafar's separate direct go-ahead.

### M5 — Results, replies, attribution
- Paged Recipients tab and Results tab from recipient rows; opens shown as directional.
- Recipient-bound token on the form link records a direct tracked result; staff-declared link; 30-day window
  association labelled as such. Revenue only from real linked Invoices/Payments. Original lead source untouched.
- Replies land in Conversations with Campaign origin.

**Approved by Jafar 2026-09-23 (reviewed against Mailchimp/Klaviyo/SendGrid/Jobber patterns):**
- **M5a — delivery truth.** Render the Step 4 call to action into the sent email (it was stored but never
  rendered); an internal-form link carries an opaque recipient-bound token that reveals no ids. Reply-To becomes
  the customer's own reply alias (`ensure_communication_reply_alias`), falling back to the operational sender
  when the organization has no receiving domain; an inbound reply whose In-Reply-To matches a Marketing message
  is tagged with that campaign. Unsubscribe links carry the campaign recipient so the recipient shows
  Unsubscribed. SES built-in open and click tracking (event types OPEN, CLICK) on each Marketing configuration
  set; recipients store delivered/opened/clicked/unsubscribed times.
- **M5b — attribution.** Tracked (form submitted through a recipient token; the Request belongs to whoever
  submitted, so a forwarded email still credits the campaign) and staff-declared links are stored. The 30-day
  window is computed at read time from delivery: a Request, or a Job created without a Request, by the same
  Customer; last touch only -- the most recent delivered campaign before that work gets the credit, so no work
  is counted twice. A click is engagement only and never earns credit (link scanners click automatically).
  Revenue is real payments on invoices of credited work, never quoted value.
- **M5c — detail and results UI.** Campaign detail with Overview, Recipients (keyset-paged, search, filters),
  Content, Results tabs; list rows gain delivered, clicked, and credited work/revenue. Jobber campaign report
  screens are captured to `Design/` first.
- **Production gate carried to M6:** click tracking goes through a branded tracking domain on the contractor's
  own domain before any real-customer send; the shared `awstrack.me` domain is sandbox/pilot-test only.

### M6 — Integrated proof
Blueprint §19 checks 1–15 in the browser across owner, admin, drafting staff, and a no-access role; tenant
isolation; cancellation race; duplicate launch; callback disorder; worker restart; and a measured Marketing burst
while operational email latency is watched. Capacity statements stay within what is measured.

## 4. Security
- Every write goes through `/api/marketing/*` with Zod; RLS on every new table scoped by organization and
  permission; launch and dispatcher functions are `security definer` with fixed `search_path` and re-derive
  sender/eligibility from stored data, never from the caller.
- Provider keys stay server-side; unsubscribe and tracked-link tokens are signed, opaque, and reveal no IDs.
- Jafar surfaces show counts and states, not Customer lists or message content.

## 5. Migration and rollback
- All migrations are additive. Retiring the old `marketing` boolean happens only after the new consent state is
  live and verified.
- The `marketing` feature is off for every organization until M6 passes; turning it off hides Marketing and
  stops new launches, and the dispatcher's platform pause stops release without losing history.

## 6. Verification per slice
Unit tests for rule compilation, eligibility reasons, and footer/variable safety; SQL tests for RLS and the launch/
claim functions; browser checks per role at desktop and narrow width; `npm run check`; Prettier on touched files.
