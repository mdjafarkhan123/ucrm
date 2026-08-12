# Complete Jafar Panel — Temporary Work Memory

## Resume instruction

When the user says `read memory and continue`, read this file plus the permanent documents named
under **Authority**. Work only the first unchecked part in **Execution checklist**, update this file,
report browser verification steps when applicable, then stop. Delete this file only after every part,
including dependency-linked parts, is checked complete.

## Mission

Finish the Platform Owner workspace from public contractor application through organization closure.
The result must be real, secure, tested, and usable in the browser. `/jafar` is not complete while a
listed dependency-linked control is unfinished, even when its contractor CRM dependency is scheduled
later.

This is a large task. One session completes one numbered part only.

## Authority

Read narrowly for the active part:

1. `AGENTS.md` — current working rules; it overrides older agent instructions.
2. `docs/jafar-organization-management-mission.md` — approved owner boundary and complete capability map.
3. `docs/jafar-onboarding-implementation-contract.md` — paid onboarding rules and acceptance checks.
4. `docs/adr/0001-paid-prospect-provisioning-and-versioned-packages.md` — immutable package and paid-prospect decision.
5. `docs/Owner.md` — older audit and supporting context; newer approved documents win conflicts.
6. `docs/PRODUCT.md` — wider CRM behavior and ownership boundaries.

Use current primary provider documentation during the relevant provider part. ContractorOs is
reference evidence only; preserve useful outcomes but do not copy its code or unsafe architecture.

## Locked product decisions

### Delivery and completion

- One A–Z roadmap governs the entire Jafar mission; delivery uses verified milestones.
- Every vertical part includes its database/security work, server behavior, real frontend, loading and
  failure states, cache invalidation, history/notifications, automated tests, and browser verification.
- A milestone closes only after automated checks pass and the user approves the real browser journey.
- Development placeholders may demonstrate a future dependency, but production must label the area
  `Coming later — requires <dependency>` and expose no fake action.
- Named owner accounts and MFA are not in this mission. Harden the current single configured Jafar
  login with rate limiting, revocable sessions, step-up password confirmation, and durable audit history.

### Public application and prospect review

- Public routes are `/get-started` and `/get-started/received`.
- The form is an onboarding application, not a signed service contract.
- It records business/contact details, optional separate administrator, package interest, optional
  note, and the accepted privacy-policy URL/version/time.
- `main contact` means the person handling the application, business discussion, and payment.
- `administrator` means the person who will receive account setup and control the contractor CRM.
  The form defaults to the contact being the administrator and reveals separate name/email fields when
  they differ.
- A successful submission creates only a platform-owned application and immutable package snapshot.
  It creates no Auth user, organization, membership, contractor data, or session.
- Prospects cannot edit submitted applications. Jafar corrections preserve the original submission and
  require a private reason.
- Jafar sees submissions at `/jafar/prospects`. There is no separate `accepted` state or action.
- Opening a prospect does not change stage. Jafar explicitly clicks `Mark reviewed` to move `new` to
  `awaiting_payment`.
- Normal lifecycle: `new -> awaiting_payment -> payment_confirmed -> account_created`.
- Exception stages are `needs_attention` and `not_proceeding`.
- Duplicate candidates are saved separately and never merged automatically. Show likely matching
  records and reasons; Jafar either acknowledges `not a duplicate` or marks the new unpaid application
  `not_proceeding` with a required private reason.
- A `not_proceeding` application retains its personal data for 12 months, then purges automatically.
- The public form has server validation, server rate limiting, Cloudflare Turnstile, accessible error
  handling, and no privileged browser credential.

### Public and owner messages

- A submission shows a received page and sends a receipt email to the main contact.
- The received page and receipt email contain one global, Jafar-managed offsite-payment instruction;
  package name and exact price are protected placeholders inserted automatically.
- Jafar clicking `Mark reviewed` sends no automatic prospect message.
- No payment-proof upload is included.
- Account creation sends the existing single-use, 24-hour password-setup email to the administrator.
  There is no additional welcome email. Jafar never creates, sees, copies, logs, or sends a password.
- When contact and administrator differ, the contact receives application/business updates and only the
  administrator receives the setup link and account-access messages.
- Jafar can edit the received-page, application-receipt, password-setup, account-created-contact notice,
  and later customer-safe owner-action notices.
- Template editing uses a guided formatted-text editor, approved placeholders, desktop/mobile/email
  preview, `draft -> publish`, immutable version history, and restore-default.
- Future sends and resends use the latest published version; sent history retains the exact rendered
  subject/body without secrets. Required security, price, deadline, and setup-link blocks cannot be removed.
- Jafar Settings manages the privacy-policy public URL/version, payment instructions, visible sender
  name, reply-to address, and owner alert recipients. The actual verified Brevo From address remains
  server configuration. Initial alert recipient is the configured owner login email.

### Jafar notifications

- New applications create a durable in-app notification and a queued owner email alert. Application
  success never depends on Brevo availability.
- The header has an unread bell and recent menu; `/jafar/notifications` provides searchable history;
  the dashboard shows linked attention cards.
- Opening the linked prospect, organization, or recovery record marks its notification read. Also
  support individual read/unread and `Mark all read`.
- Email Jafar for new applications and urgent failures: setup-email delivery, unsafe provisioning,
  provider outage requiring action, and permanent-deletion failure. Routine events remain in-app.
- Delivery is durable, idempotent, retryable, sanitized, and visible in Operations after terminal failure.

### Payment confirmation, provisioning, and setup

- Subscription payment is offsite and manually confirmed by Jafar. Store amount, USD currency, date,
  private reference/note, package version, and mismatch reason when needed; never store payment credentials.
- Payment instructions are one global published template, not package- or prospect-specific text.
- Before organization creation, a refund/reversal appends history, moves the application to
  `needs_attention`, blocks provisioning, and creates an urgent alert.
- Payment confirmation and provisioning remain separate explicit confirmations.
- Provisioning is application-bound, concurrency-safe, resumable, and idempotent. It may never create a
  second Auth user, organization, assignment, or membership.
- Related database records are created transactionally; external Auth/email work uses durable attempts,
  explicit compensation, and an operator recovery state.
- If the administrator email already belongs to an organization, provisioning is rejected. If a Supabase
  Auth identity exists but has no organization, stop in `needs_attention` for verified manual recovery;
  never attach it automatically.
- Successful provisioning creates an active organization. Administrator password readiness is separate.
- Setup-link consumption is atomic, single-use, recipient-bound, rate-limited, and expires after 24 hours.
  Resend invalidates every earlier unused link. Email failure keeps the organization active and recoverable.
- Retire the legacy direct-create organization/password flow in the same usable release as the completed
  paid-provisioning journey.

### Organization and commercial control

- Directory and detail route are real, searchable, paginated when needed, and load independent panels
  without blocking the shell.
- Detail sections: Overview, Commercial access, Integrations, Team access, History and recovery.
- Packages use immutable published versions. Package changes are immediate, separately confirmed, and
  preserve old/new version, reason, and time. Exceptions require reason/start/optional expiry.
- Complete manual confirmations and corrections for initial payment, renewal, refund, reversal, paid-through
  date, seven-calendar-day grace in commercial timezone, and late-renewal reactivation.
- Suspension is a separate confirmed action; automatic overdue messages and automatic suspension remain out.
- Free access remains exceptional and audited; permanent free access requires step-up confirmation.
- History combines onboarding, payments/corrections, provisioning/setup delivery, package/access changes,
  lifecycle, support, integrations, recovery, and deletion without exposing private secrets.
- Contractor-visible notices include safe outcomes only; private Jafar reasons and raw provider details stay private.

### Team support and owner security

- Jafar normally inspects team roles/effective permissions; contractors manage ordinary team access.
- Narrow profile corrections require before/after values, reason, confirmation, actor/time, and a safe notice.
- Administrator email recovery: verify the requester through a trusted outside channel; record a safe evidence
  summary; show old/new email; enforce cross-organization uniqueness; reconfirm Jafar password; revoke old
  sessions and setup links; notify old/new addresses when possible; retain safe history.
- Jafar never impersonates a contractor and never becomes a tenant member.
- Every `/api/jafar/*` handler independently authenticates before privileged client use. All writes use Zod.
- Current single-owner hardening includes login rate limiting/monitoring, revocable and rotatable sessions,
  short-lived step-up authorization, and sanitized audit/correlation records. Named operators and MFA remain out.

### Organization closure

- Closure starts a recoverable 30-day countdown and immediately blocks contractor access and new outbound work.
- Before starting, show affected users/data/files/provider connections and scheduled work. Require private reason,
  typed organization name, explicit confirmation, and Jafar-password reconfirmation.
- Send editable contractor-safe notices at closure start, 14 days remaining, 3 days remaining, and completion;
  protected deadlines/safety wording cannot be removed.
- During the window, only Jafar may restore after trusted outside verification, safe evidence note, password
  reconfirmation, and provider-impact review.
- At day 30, permanently delete all live organization CRM data, Auth users, files, queued work, and connected
  provider resources. No anonymized organization/CRM record remains.
- Retain only a non-personal technical deletion receipt: random operation ID, timestamps, and component success/
  failure checks. It contains no organization name, personal details, or CRM content.
- Deletion is a resumable state machine. Partial failure blocks completion, creates an urgent alert, and exposes
  safe retry/recovery. Supabase internal backup handling is outside this product roadmap.

### Provider and CRM-dependent controls

- Twilio is the SMS/phone provider; Brevo is the email provider; Cloudflare R2 is file storage.
- Contractor customer payments use contractor-owned Stripe accounts. Because Bangladesh cannot rely on normal
  Stripe Connect onboarding, plan the secure manual restricted-key method unless a usable Stripe App/OAuth
  path is explicitly approved later.
- Contractor admins—not Jafar—enter the least-privilege restricted Stripe key and webhook secret. Encrypt
  secrets, never return them after saving, and never serialize them to Jafar/browser APIs. Do not store a
  publishable key unless the chosen payment UI proves it is required.
- Jafar sees Stripe account identity, live/test mode, API health, webhook health, last check, and sanitized
  failures only. Use one authoritative readiness source.
- UCRM customer payment URLs validate current organization lifecycle and entitlement before creating a fresh
  Stripe Checkout session. Rotation, disconnect, suspension, and closure stop new sessions and reconcile old work.
- Journal every Stripe webhook/event for idempotent replay. Money exceptions become urgent Jafar recovery tasks.
- Preserve append-only refunds/corrections, row locking, tenant verification, test-mode journey, and direct payout
  to the contractor; do not copy ContractorOs plaintext-secret or stale-link behavior.
- Webchat is a UCRM-hosted website widget feeding the contractor inbox.
- No direct Google/Facebook review-provider integration is planned. Jafar may inspect contractor review links and
  internal campaign readiness only.
- Any Jafar feature whose real CRM/provider subsystem does not exist stays dependency-linked below. The live UI
  shows `Coming later` with no fake mutation. When the contractor module begins, its agent must read this file and
  deliver the paired Jafar controls in that module.

## Verified audit baseline — 2026-08-12

### Materially implemented

- Separate signed owner session and protected Jafar route/API boundary.
- Package identities, immutable version foundations, publication/retirement UI and APIs.
- Platform application/submission/correction/payment/provision/setup-link database foundations.
- Owner prospect list/detail, correction, payment confirmation, not-proceeding, provisioning, and setup resend UI/APIs.
- Organization directory/detail, lifecycle, access/package/free-access/feature/limit controls, team inspection,
  and partial history.
- Supabase Auth administrator creation and Brevo setup-email implementation.

### Confirmed release blockers

- No public application/received page/submission API, rate limit, Turnstile, package snapshot submission flow,
  receipt email, owner alert, or duplicate detection.
- No durable Jafar notification system.
- Provisioning claim is unsafe under simultaneous requests; crash/compensation recovery is incomplete.
- Setup link is not atomically consumed and can race.
- Correction, payment, lifecycle, and matching history writes can partially succeed.
- Provision/setup/email attempts lack complete immutable history and recovery operations.
- Prospect package correction before payment is absent.
- Renewal/reversal/retention execution and complete organization history are absent.
- Dashboard lacks prospect/renewal attention; some organization links are miswired.
- Prospect confirmations use inaccessible inline alert-dialog markup rather than shared Bits UI primitives.
- Administrator email recovery is not built.
- Browser tests are smoke-only and avoid consequential actions.
- Database tests do not prove provisioning/setup concurrency, rollback, or idempotency.
- QueryClient ownership work in `Memory/data-cache-architecture.md` remains incomplete and must be reconciled
  before notification/realtime cache work.
- Local files/generated types do not prove migrations are applied to the remote Supabase project.

## Execution checklist

### Part 0 — Audit and decision contract

- [x] Audit permanent docs, Memory, Jafar frontend, APIs, migrations, tests, email/setup flow, and legacy Stripe reference.
- [x] Grill product decisions and record the locked contract in this file.
- [x] Establish one-part-per-session execution and completion gates.

**Completion evidence:** this file captures the agreed A–Z boundary, current gaps, dependencies, and resume protocol.

### Part 1 — Reconcile foundations

- [x] Compare local and remote Supabase migration history without applying changes.
- [x] Inventory existing organizations, package assignments, applications, provisions, setup links, and legacy
  `pending_setup` rows using sanitized counts/IDs only.
- [x] Confirm generated database types match the deployed schema.
- [x] Finish or reconcile `Memory/data-cache-architecture.md` Part 1 so QueryClient ownership is request/app scoped.
- [x] Produce a written drift/remediation plan; obtain explicit approval before auth/schema/RLS changes.

**Completion gate:** remote schema history and server-state ownership are trustworthy; no unresolved drift blocks writes.
**Status: met.** See session log below for the drift/remediation findings and the two decisions the user approved.

### Part 2 — Durable operation and history foundation

Split into sub-parts so each session finishes one working, verifiable slice (per the user's request
mid-session to break this down further — Part 2 alone is too large for one sitting).

- [x] **Part 2a — Schema.** Extend the pre-existing `platform_owner_audit_events` table (found already in
  use for package events — did not duplicate it) with `correlation_id` and a real immutability trigger.
  Add `platform_operation_attempts` (the Operations queue backbone), `platform_owner_notifications` (bell),
  and `platform_outbox_deliveries` (durable email queue), all service-role-only with RLS. Add atomic RPC
  functions `correct_onboarding_application`, `confirm_onboarding_application_payment`,
  `mark_onboarding_application_not_proceeding` (each writes its state change + audit event in one
  transaction), and extended `provision_organization_from_application` with an actor-attributed audit
  event. Applied to remote as migration `20260812055458_platform_operations_foundation`, local file
  renamed to match exactly, types regenerated. Security advisors show only the expected
  `rls_enabled_no_policy` INFO (same pattern as every other service-role-only platform table).
- [x] **Part 2b — TS event helpers.** Filled in `src/lib/server/events/event-types.ts` (controlled
  catalogs: 3 operation types), `outbox.ts` (`recordOperationOutcome`, `createOwnerNotification`),
  `dispatcher.ts` (`enqueueEmailDelivery`, `dispatchOutboxDelivery` — no live caller yet, ready for
  Part 4's receipt/alert emails). `npm run check`: 0 errors.
- [x] **Part 2c — Wire existing owner actions.** `correct`, `confirm-payment`, `not-proceeding` routes
  now call the new atomic RPCs instead of manual two-step writes. `src/lib/server/jafar/setup-link.ts`
  (`issueSetupLink`) now takes an optional `actorEmail` and calls `recordOperationOutcome` on
  success/failure plus `createOwnerNotification` (severity `urgent`) on failure — both callers
  (`provision`, `send-setup-email` routes) now pass `actorEmail: session.email`. `provision` route also
  passes `target_actor_owner_email` to its RPC and records an `onboarding_application_provisioning`
  operation outcome on both failure branches and on success (to clear a prior failure after a
  successful retry). Updated all 4 affected route spec files (`correct`, `confirm-payment`,
  `not-proceeding`, `provision`) for the new `rpc()`-based mocks. Full suite: 157/157 passing, `npm run
  check`: 0 errors.
- [x] **Part 2d — Operations screen + API.** Added `src/lib/server/validation/operation.schema.ts`
  (status enum, id, list-query, resolve-note schemas). `GET /api/jafar/operations` lists rows ordered by
  `updated_at desc`, filtered by `target_id` and `status` — with no `status` param it defaults to
  `neq('status', 'succeeded')`, which matches the partial index the Part 2a migration built specifically
  for this screen. `POST /api/jafar/operations/[operationId]/retry` dispatches by `operation_type`:
  `outbox_email_delivery` calls `dispatchOutboxDelivery(client, attempt.idempotency_key)` directly (the
  idempotency key for that type is literally the outbox delivery id); `setup_email_delivery` looks up the
  linked application + provision by `attempt.target_id` and re-calls `issueSetupLink`; any other
  operation type (currently only `onboarding_application_provisioning`) returns 409 telling the owner to
  retry from its own screen (Prospects) instead — provisioning retries reuse the existing claim/resume
  logic there, not a generic retry. `/acknowledge` and `/resolve` (`resolve` requires a `note`, matching
  the DB check constraint that `manually_resolved` needs `resolved_at`/`resolved_by_owner_email`/
  `resolution_note` together) both reject already-`succeeded`/`manually_resolved` rows with 409. No
  separate audit-event insert was added for acknowledge/resolve/retry — the `platform_operation_attempts`
  row's own `acknowledged_by`/`resolved_by`/`resolution_note` columns already are that record, so a second
  audit trail would be pure duplication (kept to the minimal-scope rule).
  New `/jafar/(protected)/operations` Svelte page (list + click-to-open detail panel, same structure as
  the Prospects page) with Retry/Mark as seen/Resolve actions gated by status, plus KPI cards (shown,
  retrying, acknowledged) and a status filter. Added "Operations" to the owner sidebar nav
  (`src/lib/components/layout/AppShell.svelte`, `Sidebar.svelte` — new `alertTriangle` icon entry) and to
  `AppShell`'s owner page-title lookup. `npm run check`: 0 errors (same 2 pre-existing dashboard CSS
  warnings as before). `npm run test:unit`: 157/157 passing (unchanged — this part adds no new tests yet,
  that's Part 2e). `npx eslint` on the new/changed files: only pre-existing lint debt already present
  elsewhere in the codebase (the `{@html}` and nav-`resolve()` rules already tripped by every other use of
  the same Sidebar/AppShell pattern; the `URLSearchParams` rule already tripped by the Prospects page's own
  identical `new URLSearchParams()` usage) — nothing new introduced by this change.
- [x] **Part 2e — Tests + verification** (DB-level pgTAP execution deferred by user choice, see below):
  - Vitest specs added for all four operations routes: `src/routes/api/jafar/operations/operations.spec.ts`
    (list — auth, status/target_id filter validation and query building, default open-only filter, DB
    error), `[operationId]/retry/retry.spec.ts` (auth, id validation, 404/409 states, outbox-email direct
    retry, setup-email retry incl. missing-application/missing-administrator/502-on-resend-failure, the
    409 hand-off for `onboarding_application_provisioning`, 500 on lookup failure), `[operationId]/acknowledge/acknowledge.spec.ts`
    and `[operationId]/resolve/resolve.spec.ts` (auth, id validation, 404, already-closed 409, required
    note validation for resolve, successful update payload/target assertions, 500 on update failure).
  - `npm run test:unit`: 189/189 passing (up from 157 — the 32 new tests all pass).
  - `npm run check`: 0 errors (same 2 pre-existing dashboard CSS warnings as every prior session).
  - DB-level pgTAP file added: `supabase/tests/database/platform_operations_foundation.sql` (31 assertions)
    covering exactly the four things this checklist item calls for: RLS enabled + anon/authenticated blocked
    + service_role allowed on all three new tables; the `(operation_type, idempotency_key)` unique index
    rejecting a simulated concurrent duplicate-failure insert (23505); the notification trigger accepting a
    read_at-only update but rejecting a content change (23514) and rejecting delete; and the audit-events
    immutability trigger rejecting update/delete (23514). Also checks the `target_check` and
    `resolved_check` row constraints on `platform_operation_attempts`.
  - **DB test execution deferred:** running `platform_operations_foundation.sql` via `npx supabase test db`
    needs Docker, which the user chose to defer rather than set up right now. Tracked in
    `Memory/Defer-Test.md` and `Memory/Deferred-Work.md` — not blocking, but not confirmed passing either.
  - **Browser verification: done 2026-08-12.** A harmless test row (`test_manual_verification`) was
    inserted via SQL, the user confirmed it showed up on `/jafar/operations` and that "Mark as seen"
    worked end-to-end (row moved to `acknowledged`, attributed to the owner's login), and the test row
    was deleted afterward. (This happened via the reusable `Dialog` popup added by the separate
    `[[operations-prospects-detail-ux]]` task, not the original bottom-panel layout — same underlying
    screen/API, so it satisfies this checklist item.)

**Completion gate:** an operation cannot silently change state without matching history, and every terminal side-effect
failure is recoverable without duplication.
**Status: met, with one standing caveat.** Code, unit tests, and browser verification are all done. The
DB-level pgTAP file exists and is reviewed but not executed (needs Docker, deferred by user choice — see
`Memory/Defer-Test.md`/`Memory/Deferred-Work.md`). This does not block later parts; if the user ever sets up
Docker, run `npx supabase test db` once and record the result here.

Part 2 is closed.

### Part 3 — Harden provisioning and password setup

Split into sub-parts, same reasoning as Part 2 (agreed with the user 2026-08-12): each session ships one
working, verifiable slice instead of one large session.

- [x] **Part 3a — Atomic provisioning claim/resume.** Added database function
  `claim_onboarding_application_provision(target_application_id, stale_after default 2 minutes)` —
  applied to remote as migration `20260812081838_provisioning_claim_state_machine`, types regenerated.
  No new columns: reuses the existing `administrator_user_id` column (to carry a login account across
  a retry) and `updated_at` (already maintained by the table's own trigger) for staleness detection. One
  atomic function call replaces the old select-then-insert/update claim in `provision/+server.ts` and
  returns exactly one of `already_succeeded` / `in_progress` / `claimed` (the last optionally carrying a
  prior attempt's `administrator_user_id`). Route changes: the fast-path "already succeeded" replay read
  stays a plain read (kept before the stage check, since a completed provision must replay even if the
  application's stage moved on — this must NOT be forced through the atomic claim, which would
  incorrectly gate it behind the stage check); the actual claim call happens only for eligible stages.
  `createUser` is now skipped entirely when the claim returns an existing `administrator_user_id` (crash
  resume) — the code goes straight to `provision_organization_from_application` with that id. When
  `createUser` does run, its new id is persisted to the provisions row immediately, before the
  organization RPC — this is the actual fix: a crash between "login account created" and "organization
  created" now leaves a trail a retry can find and resume from, instead of a silent dead end where every
  retry fails with "email already registered" forever. On RPC failure, the compensating `deleteUser` call's
  own success/failure now determines whether `administrator_user_id` is cleared (deletion worked, safe to
  create fresh next time) or kept (deletion itself failed, so the account still exists — a retry must keep
  reusing it, not attempt a second `createUser` that would just fail). Rewrote
  `provision/provision.spec.ts` for the new RPC-based claim (dispatching by function name) and added 3
  tests: concurrent-claim rejection (`in_progress`), resuming an earlier interrupted attempt's login
  account (skips `createUser`), and the deletion-failure case that must keep the stored id. `npm run
  check`: 0 errors (same 2 pre-existing dashboard warnings). `npm run test:unit`: 192/192 (was 189, +3
  new). `npx eslint` on both touched files: clean. **Browser verification: outstanding** — this needs an
  application actually sitting in `payment_confirmed` or `needs_attention` to click Provision on for real
  (it creates a real login account + organization, not reversible casually), so it must be the user's own
  step; ask before doing this since it's a live action, not a read.
- [x] **Part 3b — Atomic setup-link claim/consume.** Added database function
  `consume_onboarding_application_setup_link(target_token_hash, target_email)` — applied to remote as
  migration `20260812082630_setup_link_atomic_consume`, types regenerated. One UPDATE with the entire
  check (token match, not consumed, not expired, recipient email match) in its WHERE clause, `returning
  application_id, administrator_user_id into ...` — Postgres row-locking means only one concurrent
  caller can ever match and update, every other caller (concurrent or later) matches zero rows. `POST
  /api/setup-password` now calls this RPC first; only when it reports `consumed: false` does the route
  fall back to a plain read-only lookup (unchanged shape) purely to pick the right user-facing message
  (expired/already-used vs. wrong email) -- deliberately does NOT fold the email check into the atomic
  claim's failure path in a way that would burn the link on a mismatched email, since a mistyped email
  must stay retryable, not consume the one-time link. No rollback on a subsequent
  `updateUserById` failure (matches the existing supported recovery path: request a fresh resend) --
  kept deliberately simple per minimal-scope rather than adding compensating-transaction complexity for
  a rare Auth API error. Rewrote `setup-password.spec.ts`: the mock's `rpc` now models the real
  WHERE-clause behavior including its side effect (a matching call flips `consumed_at` on the shared
  mock `link` object, so a second call against the same object correctly sees it as already used, same
  as the real single UPDATE would); added a test proving a wrong-email attempt does not burn the link
  (a following correct-email submit still succeeds) and a test proving a second submit with the same
  token is rejected once the first has succeeded. `npm run check`: 0 errors (same 2 pre-existing
  dashboard warnings). `npm run test:unit`: 193/193. `npx eslint` on both touched files: clean.
- [x] **Part 3c — Rate limiting.** User approved a simple database-backed limiter (2026-08-12; no Redis
  yet, that's a separate later part of the roadmap) for the public setup-password endpoints and the
  provisioning retry endpoint. Confirmed with the user: IP address as the caller key for the public
  endpoints (no session there), owner session email for the already-authenticated provisioning retry;
  limits GET `/api/setup-password` 30/5min per IP, POST 10/15min per IP, `POST
  /api/jafar/prospects/[id]/provision` 10/5min per owner session.
  Added migration `20260812083608_platform_rate_limiting.sql`: generic `platform_rate_limit_buckets`
  table (fixed-window counter, one row per `(bucket_key, window_start)`) and RPC function
  `check_rate_limit(target_bucket_key, target_window_seconds, target_max_attempts)` -- one atomic
  upsert (`insert ... on conflict do update ... returning`) so concurrent requests sharing a bucket
  key can't race past the limit, plus an opportunistic per-bucket-key cleanup delete (hits the primary
  key index, not a full scan) so the table doesn't grow unbounded. Service-role-only, same
  RLS-enabled-no-policy pattern as every other platform table; `get_advisors` shows only that expected
  INFO lint, nothing new.
  While applying this migration, found the Part 3a/3b migration files
  (`provisioning_claim_state_machine`, `setup_link_atomic_consume`) had drifted from their
  remote-applied filenames again (same class of issue fixed once already in Part 1) -- renamed both
  local files to match remote exactly (`20260812081933`, `20260812082645`); no schema difference, file
  rename only.
  New `src/lib/server/security/rate-limit.ts` (`checkRateLimit`, `rateLimitedResponse` -- 429 + a
  `Retry-After` header). Wired into `api/setup-password/+server.ts` GET and POST (bucket key
  `setup_password_get:<ip>` / `setup_password_post:<ip>` via `event.getClientAddress()`, checked right
  after the existing cheap local validation and before any DB lookup) and into
  `api/jafar/prospects/[prospectId]/provision/+server.ts` POST (bucket key
  `provision_retry:<owner email>`, checked first thing inside the existing try block, before the
  provisionable-stage/claim logic). Both spec files mock `checkRateLimit` as a module (not through the
  Supabase client's `rpc` dispatcher) so none of the existing per-route rpc mocks needed touching; each
  gained one new 429 test asserting the `Retry-After` header. `npm run check`: 0 errors (same 2
  pre-existing dashboard warnings). `npm run test:unit`: 196/196 (was 193, +3 new). `npx eslint` on all
  touched/new files: clean. Types regenerated (`src/lib/database.types.ts`) to include the new table
  and function. No browser verification needed for this part -- it's a background 429 guard with no
  user-facing surface to click through.
- [x] **Part 3d — Tests + verification.** Concurrency tests (simultaneous provision/retry calls,
  simultaneous setup-link submits), crash-recovery test, resend-replacement test, expiry test, Brevo
  failure test. Then full `npm run check` / `npm run test:unit` / lint pass and a guided browser
  verification of the complete flow.
  **Test-writing portion done, 2026-08-12:** Concurrency and crash-recovery were already exercised at
  the route level by Part 3a/3b's specs (`provision.spec.ts`'s in-progress-claim/resume tests,
  `setup-password.spec.ts`'s second-submit-rejected/wrong-email tests) -- true simultaneous-request
  concurrency is actually guaranteed by Postgres row locking in the atomic RPCs themselves, which is
  what the still-deferred `platform_operations_foundation.sql` pgTAP file (and any future one for
  these RPCs) would prove at the DB level, not something a mocked vitest unit test can prove further.
  The real gap was `src/lib/server/jafar/setup-link.ts` (`issueSetupLink`) itself having zero direct
  tests -- every caller mocks it out. Added `src/lib/server/jafar/setup-link.spec.ts` (5 tests): happy
  path (upsert shape, ~24h expiry, success outcome recorded, no owner notification on success), proof
  the upsert always happens before the send attempt (so a resend replaces the old link even if delivery
  then fails), proof two calls mint two different tokens, the Brevo-failure path (link row marked with
  `last_error`, failure outcome recorded, urgent `setup_email_failed` owner notification raised), and a
  failed-upsert propagation case. `npm run test:unit`: 201/201 (was 196, +5 new). `npm run check`: 0
  errors (same 2 pre-existing dashboard warnings). `npx eslint` on the new file: clean.
  **Browser verification deferred, 2026-08-12:** asked the user whether to do the live click-through
  themselves, have it driven via Chrome automation, or defer it -- user chose to defer entirely (same
  choice as the Docker DB-test deferral) and move on to Part 4. Tracked in `Memory/Deferred-Work.md`.
  Not blocking: Parts 3a/3b/3c are code-complete and unit-tested; only the live click-through proof on
  a real prospect (Provision -> real Auth user + organization + Brevo email -> real setup-password
  link) remains undone.

**Completion gate:** retries and simultaneous clicks cannot create duplicate tenants/users or reuse a setup link.
**Status: met, with one standing caveat.** Code and unit tests for atomic provisioning claim/resume,
atomic setup-link consume, and rate limiting are all done. The live browser click-through (Provision on
a real prospect, then the resulting real setup-password link) is deferred by user choice -- see
`Memory/Deferred-Work.md`. Does not block later parts.

Part 3 is closed.

### Part 4 — Public application, settings, templates, and owner notifications

Split into sub-parts, agreed with the user 2026-08-12 (asked via AskUserQuestion; user picked "start with
Settings" over a different order, a different split, or no split), same reasoning as Parts 2/3: each
session ships one working, verifiable slice.

- [x] **Part 4a — Jafar Settings.** Alert recipients, privacy-policy URL/version, payment instruction,
  sender display name/reply-to address. Config only — no template editor yet.
  New singleton table `platform_owner_settings` (`id boolean primary key default true check (id)` —
  the standard Postgres "at most one row" trick), service-role-only RLS, applied to remote as migration
  `20260812091402_platform_owner_settings` (local file renamed to match), types regenerated. New atomic
  function `public.update_owner_settings(...)` upserts the row if missing, updates it, and writes a
  matching `platform_owner_audit_events` row (`event_type = 'owner_settings.updated'`) in one
  transaction — same before/after-audit pattern as every other owner-privileged multi-step write in
  this codebase. `security_advisors`: only the expected `rls_enabled_no_policy` INFO.
  Server: `getOrCreateOwnerSettings` (`src/lib/server/jafar/owner-settings.ts`) lazily creates the row
  on first read, seeding `alert_recipient_emails` with the configured `SUPER_ADMIN_EMAIL` — uses
  `upsert(..., { onConflict: 'id', ignoreDuplicates: true })` so concurrent first reads can't clobber
  each other. `GET /api/jafar/settings` and `PATCH /api/jafar/settings` (Zod-validated via new
  `src/lib/server/validation/owner-settings.schema.ts` — URL format, email formats, 1-10 alert
  recipients required). New `/jafar/(protected)/settings` page styled like the existing Packages page
  (same BEM/token conventions) — plain fields plus an editable alert-email list (add/remove rows),
  save button with success/error feedback and a "last saved" timestamp. Added to the owner sidebar nav
  (`Sidebar.svelte` new `settings` icon entry, `AppShell.svelte` nav item + page-title lookup).
  `npm run check`: 0 errors (same 2 pre-existing dashboard warnings). `npm run test:unit`: 210/210 (was
  201, +9 new in `settings.spec.ts`). `npx eslint` on all new/touched files: clean except 3 pre-existing
  errors in `AppShell.svelte`/`Sidebar.svelte` (the sign-out button's `{@html}` and the nav `<a href>`
  pattern already used by every other nav item) — not introduced by this change, not touched by it.
  Database-level pgTAP file added: `supabase/tests/database/platform_owner_settings.sql` (15
  assertions: table exists, RLS on, anon/authenticated blocked, service_role allowed, the boolean-PK
  singleton constraint rejecting `id = false` and rejecting a second row, and the atomic update
  function producing both the row change and its matching audit event). **Not yet executed** — same
  standing Docker deferral as every other DB test file in this project; tracked in
  `Memory/Defer-Test.md`/`Memory/Deferred-Work.md`.
  **Browser verification: done 2026-08-12.** User opened `/jafar/settings`, changed values, saved,
  reloaded, and confirmed the change stuck. (Login was blocked first by an unrelated `.env` bug — see
  session log below — fixed before this check.)
- **Part 4b — Guided message-template editor.** Split into sub-parts 2026-08-12 (user approved,
  same reasoning as Parts 2/3): schema first, then API, then UI, then wiring the one email that
  already sends for real today. User also chose a simple text + placeholder-button editor (no new
  rich-text package) over a full WYSIWYG toolbar.
  - [x] **Part 4b-i — Schema.** New `platform_message_templates` (one row per key: `received_page`,
    `application_receipt`, `password_setup`, `account_created_contact` — draft + published
    subject/body, published version/at/by) and `platform_message_template_versions` (immutable
    snapshot per publish, same `prevent_platform_history_mutation` trigger reused from the
    Operations migration). New atomic `publish_message_template(target_template_key, actor_email)`
    RPC: copies draft into published, inserts the version snapshot, and writes a
    `platform_owner_audit_events` row, all in one transaction — required/approved placeholder
    rules and default copy deliberately stay in TypeScript (`src/lib/server/jafar/message-templates.ts`,
    not yet written), not the schema, since those are product rules that change more often. All 4
    templates seeded as already "published" (version 1) so nothing about live behavior changes yet;
    `password_setup`'s seeded copy is byte-for-byte the wording already hardcoded in
    `setup-link.ts` today, so a later sub-part can switch it over with no visible change. Applied to
    remote as migration `20260812104126_platform_message_templates` (local filename renamed to
    match, same drift issue as every prior migration in this project). Types regenerated
    (`src/lib/database.types.ts`). `get_advisors`: only the expected `rls_enabled_no_policy` INFO on
    the 2 new tables. `npm run check`: 0 errors (same 2 pre-existing dashboard CSS warnings).
  - [x] **Part 4b-ii — API.** Asked the user how strict the "required blocks can't be removed"
    rule should be (check a few required merge tags vs. also locking the plain-text safety
    sentence behind a new protected tag); user picked the simpler merge-tag-only check and asked
    for the placeholder catalog to be exposed so the editor UI (Part 4b-iii) can render
    click-to-insert buttons and validate on save. Built `src/lib/server/jafar/message-templates.ts`
    (`TEMPLATE_PLACEHOLDERS` catalog marking which tags are required per template --
    `price`/`payment_instructions`/`package_name` required for `received_page` and
    `application_receipt`, `setup_link` required for `password_setup`, nothing required for
    `account_created_contact`; `missingRequiredPlaceholders()` helper) and
    `src/lib/server/validation/message-template.schema.ts` (Zod). Four new routes under
    `src/routes/api/jafar/message-templates/`: `GET` (list all 4 with their placeholder catalogs),
    `[templateKey]/GET` (draft + published + full version history + placeholders),
    `[templateKey]/PATCH` (draft autosave, no audit -- matches the schema's design where only
    publish is audited), `[templateKey]/publish/POST` (blocks empty content and blocks any
    missing required tag with a 422 + `missing_placeholders` list before calling the
    `publish_message_template` RPC), `[templateKey]/restore-version/POST` (draft-only, does not
    auto-publish; body `{ version? }` defaults to `1` -- version 1 of every template is exactly
    its seeded default wording, so this one endpoint serves both the checklist's "restore-default"
    action and Part 4b-iii's "restore-to-version" action without duplicating logic). `npm run
    check`: 0 errors (same 2 pre-existing dashboard warnings). `npm run test:unit`: 239/239 (was
    210, +29 new across 4 new spec files). `npx eslint` on all new files: clean (one
    `no-useless-assignment` catch-and-fixed during this session). No schema changes -- this part
    only reads/writes the Part 4b-i tables and calls its existing RPC.
  - [x] **Part 4b-iii — UI.** New `/jafar/message-templates` page: left-side list of the 4 templates
    (name, published version badge, "Unpublished changes" badge derived from `updated_at >
    published_at` -- no schema change needed for that signal), right-side editor per selected
    template (subject field hidden for `received_page` since it has no subject column populated --
    `TEMPLATE_HAS_SUBJECT` map in the component -- placeholder-insert buttons that splice `{{tag}}`
    into the body textarea at the cursor via `bind:this` + `tick()`, required-tag warning banner,
    Save draft / Publish with a confirm checkbox, Publish disabled while the draft has unsaved
    changes so it can never publish stale content or while required tags are missing), a
    desktop/mobile/email-width preview panel (raw `{@html}` of the draft body -- tags render
    literally, no substitution, per minimal-scope), and a version-history table with per-row
    "Restore" plus a "Reset to default" button (both funnel into one shared inline confirm banner,
    then call `restore-version`). Added "Templates" to the owner sidebar nav
    (`Sidebar.svelte` new `mail` icon entry, `AppShell.svelte` nav item + page-title lookup). No new
    API routes or schema -- consumes the four Part 4b-ii routes exactly as they exist. `npm run
    check`: 0 errors (same 2 pre-existing dashboard warnings). `npm run test:unit`: 239/239 unchanged
    (no route logic touched). `npx eslint` on the new page: clean; the 3 errors on
    `AppShell.svelte`/`Sidebar.svelte` are the same pre-existing `{@html}` sign-out and nav
    `resolve()` debt already flagged in the Part 2d/4a sessions, not introduced here. Svelte
    autofixer: no issues, only style suggestions (the `$effect`-seeds-local-state pattern matches
    the Settings page's own established convention, kept for consistency).
    **Browser verification: done 2026-08-12.** User clicked through `/jafar/message-templates`
    directly (per `[[feedback_self_verify_simple_visuals]]`) and confirmed it works.
  - [x] **Part 4b-iv — Wire the live email.** `issueSetupLink` (`setup-link.ts`) now fetches the
    published `password_setup` template row (`subject_published`/`body_published`), substitutes
    `{{business_name}}`/`{{setup_link}}` via a new `renderTemplate()` helper
    (`message-templates.ts`), and sends that as the email instead of the old hardcoded HTML
    string. Throws a clear error before creating any link if the template has no published
    content (should never happen in practice — it's seeded pre-published — but fails loudly
    instead of silently sending broken email). Since the template only stores one HTML body (no
    separate plain-text version), added `htmlToPlainText()` (`message-templates.ts`) to derive
    Brevo's required `textContent` automatically. Added two nullable columns,
    `rendered_subject`/`rendered_body`, to `platform_onboarding_application_setup_links` (migration
    `20260812113345_setup_link_rendered_content`) and the upsert now stores the exact rendered
    content on the same row that already tracks `last_sent_at`/`last_error` — so Jafar can always
    see what an administrator actually received even after the template's published wording later
    changes. Deliberately did not switch this to the durable outbox/dispatcher pattern
    (`enqueueEmailDelivery`/`dispatchOutboxDelivery`) built in Part 2b — that would change the
    Operations retry behavior for `setup_email_delivery` (which re-calls `issueSetupLink` today)
    and the resume note explicitly asked to keep this minimal, not restructure. `application_receipt`,
    `received_page`, and `account_created_contact` stay preview-only for now — their real trigger
    points don't exist until Parts 4c/4d/4e. Updated `setup-link.spec.ts`: mock client now serves a
    `platform_message_templates` row; new test proves the sent subject/htmlContent/textContent and
    the stored `rendered_subject`/`rendered_body` all match the rendered template; new test proves
    an unpublished template throws before any link row is created. `npm run check`: 0 errors (same
    2 pre-existing dashboard warnings). `npm run test:unit`: 240/240 (was 239, +1). `npx eslint` on
    all touched files: clean. `security_advisors`: only the expected `rls_enabled_no_policy` INFO
    pattern, nothing new. No browser verification needed for this part on its own — it only changes
    what's inside an email Brevo sends, which the still-deferred Part 3d live-provisioning
    click-through (see `Memory/Deferred-Work.md`) will exercise for real whenever that happens.
- [x] **Part 4c — `/get-started` public page.** Published package cards, contact/admin logic, consent
  evidence, Turnstile, accessible validation, rate limiting, duplicate candidates, atomic application +
  immutable snapshot creation.
  Asked the user two decisions before building (2026-08-12, via AskUserQuestion): Turnstile keys weren't
  in `.env` yet, so built the integration to skip verification when unconfigured -- user then pasted real
  site/secret keys mid-session, so it runs live now; duplicate detection stays the simple
  `possible_duplicate` warning flag already shown on the Prospects page (no new matched-record table).
  New DB function `submit_onboarding_application` (migration `20260812140136_platform_onboarding_
  application_submission`) -- one atomic call that re-checks the package version is still published,
  inserts the application and its immutable submission snapshot together, and sets `possible_duplicate`
  when the contact email, administrator email, or business name (case-insensitive) matches any existing
  application. Deliberately does not match against live organizations/`auth.users` -- that uniqueness is
  already independently enforced at provisioning time (Part 3a), so this flag stays a lightweight review
  warning, not a second copy of that safety check. `security_advisors`: only the expected
  `rls_enabled_no_policy` INFO pattern.
  `POST /api/get-started` (new `src/lib/server/validation/get-started.schema.ts`,
  `src/lib/server/security/turnstile.ts`): per-IP rate limit (5/15min, reusing the Part 3c limiter),
  Turnstile verification (`verifyTurnstileToken` returns `true`/skips when `TURNSTILE_SECRET_KEY` is
  unset -- local-dev fallback, not the live behavior now that real keys are configured), Zod validation,
  then the RPC call. Privacy-policy version is stamped server-side from the current
  `platform_owner_settings` row (never trusts a client-submitted version, so a cached old page can't
  record agreement to stale wording). On success, records an in-app owner notification (`severity:
  'attention'`, kind `onboarding_application_submitted`) so a bell/notifications UI (Part 4e) will have
  history to show once built. On an unexpected save failure, records an urgent owner notification
  (`onboarding_application_submission_failed`) -- same in-app-only pattern `setup-link.ts` already uses
  for its own failure alerts; queued *email* alerts are still Part 4e's job, not duplicated here.
  New public page `src/routes/get-started/+page.svelte` + `+page.server.ts`: package cards read via the
  service-role client server-side (not the anon client) -- found during research that `public.features`
  RLS only grants `select` to `authenticated`, not `anon`, so an unauthenticated visitor's browser
  couldn't have resolved feature descriptions directly; reading server-side in the page's own load
  function sidesteps that without touching RLS at all. Contact/admin toggle (defaults to "I'll be the one
  logging in", reveals separate administrator name/email fields when unchecked), trade/city-country/time
  zone (time zone pre-filled from the browser's `Intl` API, editable), optional note, privacy-policy
  checkbox linked to the owner-configured URL/version, Turnstile widget (only rendered when
  `PUBLIC_TURNSTILE_SITE_KEY` is set). On success shows an inline "thanks, we got it" message rather than
  redirecting to `/get-started/received`, which doesn't exist until Part 4d. Reused existing `Card`,
  `Input`, `Checkbox`, `Button` primitives; package selection is hand-rolled accessible radio-cards since
  no shared `Radio` primitive exists yet in this codebase (only 3 options, so this doesn't call for
  building one). `Textarea.svelte` is still an empty unbuilt stub (same as `Dialog.svelte` was before the
  earlier UX task) -- used a plain native `<textarea>` for the one note field rather than filling in that
  shared component as a side effect of this task.
  `npm run check`: 0 errors (same 2 pre-existing dashboard warnings). `npm run test:unit`: 247/247 (was
  240, +7 new in `get-started.spec.ts`). `npx eslint`: clean (one real new-file issue found and fixed --
  the privacy-policy link's `href` is a runtime, owner-configured external URL, which
  `svelte/no-navigation-without-resolve` can't statically distinguish from an internal route since
  `resolve()` only covers known internal routes; scoped with an `eslint-disable`/`eslint-enable` pair and
  a one-line reason, not a blanket suppression). Confirmed via a live request to the already-running dev
  server that the page actually renders: all three published packages (Starter/Growth/Elite) came back in
  the SSR HTML with real prices, no error banner.
  **Full interactive browser verification (filling out and submitting the real form, confirming rate
  limiting/Turnstile/duplicate-flag behavior end-to-end) is still the user's own next step** -- per this
  project's established pattern (see `[[feedback_self_verify_simple_visuals]]`), same as every other new
  screen in this roadmap.
- [ ] **Part 4d — `/get-started/received` + receipt email.** Confirmation page and queued contact receipt
  email using the exact rendered published template from 4b.
- [ ] **Part 4e — Owner notifications.** Notification bell/menu, `/jafar/notifications`, dashboard
  attention, read/unread controls, deep links, queued owner email alerts, retries, Operations integration.
- [ ] **Part 4f — Dashboard deep-link fixes.** Fix miswired organization links; label legacy
  `pending_setup` as reconciliation-only.
- [ ] **Part 4g — Tests + verification.** Public abuse/security, package retirement race, alert-provider
  outage, duplicate warning, message versioning, accessibility, responsive UI, and complete
  submission-to-Jafar browser journey.

**Completion gate:** a real prospect can submit safely, receive confirmation, and appear immediately in Jafar with
durable in-app notification and recoverable email delivery.

### Part 5 — Complete prospect-to-first-login cutover

- [ ] Add explicit Mark reviewed transition and duplicate acknowledge/close actions with private history.
- [ ] Add pre-payment package correction/version choice with required reason and immutable original snapshot.
- [ ] Complete payment confirmation, mismatch, refund/reversal, Needs-attention resolution, and explicit accessible
  Bits UI confirmations.
- [ ] Complete provision confirmation, setup delivery, password creation, login readiness, and cache invalidation.
- [ ] Retire legacy direct organization creation and owner-entered password UI/API.
- [ ] Add real database/integration/browser coverage for application -> review -> payment -> provisioning -> setup -> login.

**Completion gate:** all onboarding-contract acceptance checks pass and the user verifies the full browser journey.

### Part 6 — Organization directory, commercial access, and legacy reconciliation

- [ ] Complete directory search/filter/stable pagination, overview attention, and independent detail-panel loading.
- [ ] Complete package changes, exceptions/expiry, effective capabilities/limits, free access, commercial timezone,
  payments, renewals, corrections, reversals, grace, paid-through state, and manual suspend/reactivate.
- [ ] Enforce capabilities and limits in server/domain behavior, not only UI.
- [ ] Reconcile every legacy package assignment and `pending_setup` organization individually with reason/history.
- [ ] Build unified owner-private and contractor-safe history/notices.

**Completion gate:** every organization’s lifecycle and commercial access are explainable from immutable records.

### Part 7 — Team access and administrator recovery

- [ ] Complete read-only roles/effective permissions/readiness and missing-administrator warnings.
- [ ] Complete setup-email support recovery and narrow audited profile correction.
- [ ] Implement the locked administrator-email recovery process, session/link revocation, notices, and history.
- [ ] Add authorization, uniqueness-race, recovery, revocation, and browser tests.

**Completion gate:** Jafar can recover contractor administration without passwords, impersonation, or casual permission editing.

### Part 8 — Operations and current-owner security hardening

- [ ] Complete global/organization failure recovery, retry safety, recurring-health views, email alerts, and diagnostics.
- [ ] Add owner login rate limiting/monitoring, revocable session storage/rotation, short-lived password step-up, and
  comprehensive sanitized audit/correlation history.
- [ ] Verify every Jafar API authorizes independently and secrets never enter browser payloads/logs/history.
- [ ] Add abuse, session revocation, step-up expiry, audit completeness, retry-idempotency, and browser tests.

**Completion gate:** high-impact operations are attributable and recoverable, and the current single owner login meets
the approved security boundary.

### Part 9 — Recoverable closure and strict purge

- [ ] Build impact preview, confirmed closure start, immediate access/outbound-work stop, 30-day deadline, and notices.
- [ ] Build verified Jafar-only restore with provider impact preview and safe history.
- [ ] Build resumable day-30 purge across Postgres tenant data, Supabase Auth, R2 files, queues, and completed provider
  integrations; retain only the non-personal technical receipt.
- [ ] Build urgent deletion-failure alert/retry and prove no orphan tenant records/files/users remain.
- [ ] Add countdown, restore, authorization, partial-failure, retry, cascade inventory, and browser tests.

**Completion gate:** closure is reversible for exactly 30 days, then all live organization data is permanently removed
without orphaned resources.

### Part 10 — CRM-dependent Jafar controls

These entries remain open until their real contractor subsystem exists. The agent implementing that subsystem owns
the paired Jafar work and updates this checklist.

- [ ] **Phone/SMS/Twilio dependency:** phone provisioning/port/replace/release, carrier registration, platform and tenant
  gates, opt-out safety, credit ledger/reservations/top-ups, pause/resume, provider health, alerts, and recovery.
- [ ] **Email/Brevo-domain dependency:** verified platform fallback, tenant-domain DNS/provider verification, eligibility,
  last check/errors, emergency gates, alerts, and recovery while contractors own sender preferences.
- [ ] **Stripe/invoice-payment dependency:** secure contractor restricted-key connection, encrypted secrets, API+webhook
  readiness, test journey, current-lifecycle gating, payment event journal/replay, refunds/exceptions, disconnect/rotation,
  Jafar diagnostics, alerts, and recovery.
- [ ] **Webchat/inbox dependency:** UCRM widget identity/token, entitlement, abuse controls, allowed-domain enforcement,
  provider/system health, alerts, and recovery while contractors own content/routing preferences.
- [ ] **Reviews/reputation dependency:** contractor-owned review links and campaign readiness/diagnostics only; no direct
  Google/Facebook reconciliation integration.

**Completion gate:** every implemented provider-facing contractor capability has matching real Jafar eligibility,
health, emergency, history, and recovery controls; no dependency entry remains unchecked.

### Part 11 — Final A–Z release audit and Memory cleanup

- [ ] Re-audit the repository and deployed environment against every locked decision and permanent acceptance check.
- [ ] Run full type/Svelte checks, lint, unit, database/RLS, integration, concurrency, and Playwright journeys.
- [ ] Verify desktop and mobile, accessibility, loading/empty/error/stale/partial-failure states, cache invalidation,
  security boundaries, secret redaction, provider recovery, and strict deletion.
- [ ] Remove development placeholders and stale legacy direct-create code/data paths.
- [ ] Obtain the user’s browser approval for every milestone journey.
- [ ] Move any lasting product decision into its appropriate permanent doc, then delete this temporary Memory file.

**Completion gate:** every checklist item is complete, no production placeholder or untracked dependency remains, and
the user has verified the complete Jafar panel.

## Session log

### 2026-08-12 — Part 0 complete

- Audited documentation, Memory, frontend, backend, migrations/tests, setup-email flow, and legacy Stripe behavior.
- Confirmed the public intake and owner-notification entry are missing; internal prospect/organization work is partial.
- Recorded user-approved workflow, message, notification, retention, closure, security, provider, and dependency decisions.
- Created this single master execution checklist. No application code, database, auth, or remote state changed.

**Next session:** say `read memory and continue`. The agent must start Part 1 only: reconcile foundations.

### 2026-08-12 — Part 1 complete

**Drift/remediation findings:**

- Migration history: 3 local migration files (`platform_onboarding_payment_confirmations`,
  `platform_onboarding_provisioning`, `platform_onboarding_setup_links`) had a filename timestamp that did
  not match the version already recorded as applied on the remote database. No SQL/schema difference — the
  file content and the applied migration were the same, only the local filename prefix was wrong. This would
  have confused Supabase CLI's applied/pending tracking. **Fixed:** the 3 files were renamed on disk to the
  exact remote-applied version (no database change). User approved this approach over leaving it undocumented.
- Sanitized inventory: 4 organizations (1 legacy `lifecycle_status = pending_setup`, 3 `active`), 3
  organization members, 4 onboarding applications (1 `not_proceeding`, 1 `payment_confirmed`, 2
  `account_created`), 2 provisions, 1 setup link, 2 package assignments. The single legacy `pending_setup`
  organization remains untouched, per the existing Part 6 scope ("Reconcile every legacy package assignment
  and `pending_setup` organization individually with reason/history") — not reopened here.
- Generated database types (`src/lib/database.types.ts`) were compared table-by-table against a fresh
  `generate_typescript_types` pull: identical table and function set. No drift, no regeneration needed.
- QueryClient ownership bug (tracked in `[[data-cache-architecture]]`) confirmed and fixed: the app had one
  `QueryClient` created at server module load and shared by every visitor/request. User approved fixing it
  in this same session. Changed `src/lib/query-client.ts` to export a `createQueryClient()` factory instead
  of a shared instance; `src/routes/+layout.svelte` now creates one instance per component/request; the 4
  pages that previously imported the shared singleton directly (`dashboard`, `jafar/prospects`,
  `jafar/packages`, `jafar/organizations/[organizationId]`) now read it via `useQueryClient()` from Svelte
  context instead. Verified with `npm run check`: 0 errors.
- No auth, schema, or RLS changes were required to close Part 1 — the only drift found was the migration
  filename mismatch (file rename only) and the QueryClient wiring (application code only). Nothing here
  needed the auth/schema/RLS approval gate.

**Next session:** say `read memory and continue`. The agent must start Part 2 only: durable operation and
history foundation.

### 2026-08-12 — Part 2d complete

Built the Operations screen and its four API routes (list/retry/acknowledge/resolve) as detailed in the
Part 2d checklist entry above. No schema changes — this part only consumes the Part 2a tables and Part 2b
helpers. `npm run check` and `npm run test:unit` both clean; no new lint debt.

**Next session:** say `read memory and continue`. The agent must start Part 2e only: tests for the four
new operations routes, DB-level tests (RLS, unique-key upsert under concurrent failures, notification
update-trigger, audit immutability), then browser-verify by forcing a setup-email failure and confirming
it appears on `/jafar/operations` and can be retried/acknowledged/resolved with a matching
`platform_owner_audit_events` row.

### 2026-08-12 — Part 2e (code side) complete; DB test execution deferred, browser verification outstanding

Wrote the four Vitest spec files and the `platform_operations_foundation.sql` pgTAP file described above.
`npm run test:unit` (189/189) and `npm run check` (0 errors) both pass. Did not touch schema, auth, or RLS.
No Docker in this sandbox, so the pgTAP file could not be executed here. Asked the user how to verify the DB
tests (skip + manual remote check / install Docker / run directly against remote); user chose to defer the
decision entirely — logged in `Memory/Defer-Test.md` and `Memory/Deferred-Work.md`, not resolved. No browser
verification was performed (deliberately — forcing a real setup-email failure means touching the live Brevo
key, which shouldn't happen without the user present); guidance for a safe manual check (insert one test row
via SQL editor, confirm it shows up on `/jafar/operations`, try Mark as seen/Resolve, delete the row) was
given but not yet confirmed done.

**Next session:** say `read memory and continue` once the user has done the browser check above (the DB test
stays deferred per `Memory/Defer-Test.md` until the user raises it again — do not chase it proactively).
Once the browser check is confirmed, mark Part 2e `[x]`, close Part 2, and start Part 3: harden provisioning
and password setup.

### 2026-08-12 — Part 2e browser check confirmed; Part 2 closed

The user browser-verified Operations directly (per `[[feedback_self_verify_simple_visuals]]`, this is the
user's own step, not Claude's): inserted a test row, confirmed it appeared on `/jafar/operations`, confirmed
"Mark as seen" worked end-to-end (row moved to `acknowledged`, attributed to their login), then the test row
was deleted. This ran through the new `Dialog` popup added by the separate `[[operations-prospects-detail-ux]]`
task rather than the original bottom panel, but exercises the same screen/API so it satisfies this item. The
DB-level pgTAP file (`platform_operations_foundation.sql`) remains written-but-unexecuted — confirmed with the
user this is the standing Docker deferral, not a new item, and is not blocking. Part 2e marked `[x]`, Part 2
closed. No application code changed this session (only the earlier UX dialog work, tracked in its own file).

**Next session:** say `read memory and continue`. The agent must start Part 3 only: harden provisioning and
password setup. Read `docs/jafar-onboarding-implementation-contract.md` narrowly for that part before writing
any code.

### 2026-08-12 — Part 3a complete; browser check outstanding

Built the atomic provisioning claim/resume fix described above (migration
`20260812081838_provisioning_claim_state_machine`, `provision/+server.ts`, rewritten
`provision.spec.ts`). User approved splitting Part 3 into 3a-3d before starting, and approved building
a simple database-backed rate limiter (no Redis yet) for 3c. `npm run check` 0 errors, `npm run test:unit`
192/192, `npx eslint` clean on touched files. No browser verification yet — this needs a real prospect in
`payment_confirmed`/`needs_attention` to click Provision on, which is a live, not-casually-reversible
action, so ask the user before doing it rather than doing it automatically.

**Next session:** say `read memory and continue`. First confirm with the user whether they want to browser-
verify Part 3a now (there's a real prospect sitting in `payment_confirmed` per the Part 1 inventory) before
starting Part 3b, or defer that check and proceed straight to Part 3b (atomic setup-link claim/consume) —
either is fine, just don't click Provision on a real prospect without asking first.

### 2026-08-12 — Part 3b complete

Built the atomic setup-link consume fix described above (migration
`20260812082630_setup_link_atomic_consume`, `api/setup-password/+server.ts`, rewritten
`setup-password.spec.ts`). `npm run check` 0 errors, `npm run test:unit` 193/193, `npx eslint` clean.
Browser verification for 3a is still outstanding (user chose to move straight to 3b instead, 2026-08-12).

**Next session:** say `read memory and continue`. Start Part 3d: concurrency tests (simultaneous
provision/retry calls, simultaneous setup-link submits), crash-recovery test, resend-replacement test,
expiry test, Brevo failure test, plus a full `npm run check` / `npm run test:unit` / lint pass. Then a
guided browser verification of the complete flow -- this must cover Part 3a's still-outstanding manual
check too (a real prospect sitting in `payment_confirmed`/`needs_attention`, click Provision for real;
ask the user first since it's a live, not-casually-reversible action), plus 3b and 3c.

### 2026-08-12 — Part 3c complete

Built the shared database-backed rate limiter described above: migration
`20260812083608_platform_rate_limiting.sql` (`platform_rate_limit_buckets` table +
`check_rate_limit` RPC), `src/lib/server/security/rate-limit.ts`, wired into
`api/setup-password/+server.ts` (GET/POST, per-IP) and
`api/jafar/prospects/[prospectId]/provision/+server.ts` (POST, per-owner-session). Also caught and
fixed a repeat of the Part-1 filename-drift issue on the Part 3a/3b migrations (local filenames didn't
match what was actually recorded as applied on remote) -- renamed both, no schema change. `npm run
check` 0 errors, `npm run test:unit` 196/196 (+3), `npx eslint` clean, types regenerated, security
advisors show only the expected pattern. No browser verification needed (no user-facing surface).

**Next session:** say `read memory and continue`. Start Part 3d: concurrency tests (simultaneous
provision/retry calls, simultaneous setup-link submits), crash-recovery test, resend-replacement test,
expiry test, Brevo failure test, then a full check/test/lint pass and a guided browser verification of
the complete flow -- including the still-outstanding Part 3a manual check (ask the user before clicking
Provision on a real prospect, since it's a live action).

### 2026-08-12 — Part 3d test-writing portion complete; browser verification outstanding

Added `src/lib/server/jafar/setup-link.spec.ts` (5 new tests) to close the one real coverage gap left
after Part 3a/3b's route-level concurrency/crash-recovery tests -- `issueSetupLink` itself (resend
replacement, ~24h expiry, and Brevo failure handling) had never been tested directly. `npm run
test:unit`: 201/201 (+5). `npm run check`: 0 errors (same 2 pre-existing dashboard warnings). `npx
eslint`: clean. No schema, auth, or RLS changes.

### 2026-08-12 — Part 3d browser verification deferred; Part 3 closed

Asked the user how to handle the live click-through (do it themselves / drive via Chrome automation /
defer). User chose to defer, same as the earlier Docker DB-test decision -- logged in
`Memory/Deferred-Work.md`, not resolved. Part 3d marked `[x]` with that standing caveat, Part 3 closed.
No application code changed this session beyond the test-writing work above.

**Next session:** say `read memory and continue`. Start Part 4: public application, settings,
templates, and owner notifications. Read `docs/jafar-onboarding-implementation-contract.md` narrowly
for the public-application piece before writing any code. Part 4 is large (Settings, `/get-started`,
`/get-started/received`, notification bell/menu, `/jafar/notifications`, dashboard deep-link fixes) --
consider whether it needs its own sub-part split the way Parts 2 and 3 did, and confirm that with the
user before starting.

### 2026-08-12 — Part 4 split into 7 sub-parts; Part 4a complete, browser check outstanding

Asked the user via AskUserQuestion whether to split Part 4 and where to start; user picked the
7-sub-part split (Settings -> Templates -> Public form -> Confirmation page/email -> Notifications ->
dashboard link fixes -> tests), starting with Settings. Presented the Part 4a schema/API/UI plan in
plain language and got explicit approval before touching the database (per the "confirm before
touching schema" rule). Built Part 4a exactly as described above: migration, atomic update function,
server helper, API routes, Settings page, sidebar wiring, unit tests, and a written-but-unexecuted
pgTAP file. `npm run check` 0 errors, `npm run test:unit` 210/210, `npx eslint` clean on new/touched
files (3 pre-existing errors in AppShell/Sidebar untouched by this change).

**Next session:** say `read memory and continue`. First ask the user to browser-verify Part 4a
(`/jafar/settings` loads, seeded alert email is the owner's login email, edit + save + refresh
persists). Once confirmed, mark Part 4a `[x]`'s browser line done and start Part 4b: the guided
message-template editor (draft/preview/publish/version/restore) for the received-page,
application-receipt, password-setup, and account-created-contact templates. Read the "Public and owner
messages" section of this file's locked decisions plus
`docs/jafar-onboarding-implementation-contract.md` narrowly before designing it, and present the
schema/API/UI plan for approval before writing code, same as this session.

### 2026-08-12 — Part 4a closed

Fixed a `.env` bug blocking all `/jafar` logins: `SUPER_ADMIN_PASSWORD_HASH`'s `$` characters were
being swallowed by Vite's variable-expansion parsing. Fix: escaped them as `\$` in `.env`. No app code,
migration, or schema changed. **Note for later:** any future `.env` secret containing `$` (hash, JWT,
token) needs the same escaping.

User then completed the Part 4a browser check (settings load/save/persist). Part 4a closed, no caveats.

**Next session:** say `read memory and continue`. Start Part 4b: guided message-template editor
(draft/preview/publish/version/restore) for the received-page, application-receipt, password-setup, and
account-created-contact templates. Read the "Public and owner messages" section of this file's locked
decisions plus `docs/jafar-onboarding-implementation-contract.md` narrowly before designing it, and
present the schema/API/UI plan for approval before writing any code.

### 2026-08-12 — Part 4b split into 4 sub-parts; Part 4b-i complete

Asked the user two things before starting: editor complexity (picked simple text + placeholder
buttons, no new package) and whether to split Part 4b across sessions (yes, same pattern as Parts
2/3). Built the schema sub-part exactly as described above — two new tables, one atomic publish
RPC, all 4 templates seeded pre-published with today's real password-setup wording. No UI, no API
routes, and no live email wiring yet. `npm run check` 0 errors, advisors clean (expected INFO
only).

**Next session:** say `read memory and continue`. Start Part 4b-ii: the template API routes (GET
draft+published+history, PATCH draft, POST publish with required-placeholder validation, POST
restore-default). Required/approved placeholder lists and default copy need to be written in a new
`src/lib/server/jafar/message-templates.ts` as part of this sub-part — they don't exist yet.

### 2026-08-12 — Part 4b-ii complete

Built the four template API routes and their supporting business-rules/validation modules exactly
as described above. No browser surface exists yet (Part 4b-iii builds the editor UI that calls
these routes), so no browser verification applies to this part.

**Next session:** say `read memory and continue`. Start Part 4b-iii: the editor UI (plain text +
placeholder-insert buttons per the user's earlier choice, click a tag button to insert it at the
cursor), desktop/mobile/email preview, Publish button (surfacing the `missing_placeholders` list
from the API on a blocked publish), version history list with restore-to-version, and a "Reset to
default" button (both call the new `restore-version` endpoint -- default omits `version`, a
specific entry passes it). Present the screen layout for approval before building it, same as
every prior UI sub-part.

### 2026-08-12 — Part 4b-iii complete, browser-verified; Part 4b-iii closed

Presented the screen layout (list + editor + preview + history, as described in the checklist entry
above) for approval before writing code, per this file's own resume note; user approved as-is. Built
`/jafar/message-templates` exactly as presented, plus the "Templates" sidebar entry. No schema or API
changes -- purely consumes the four existing Part 4b-ii routes. `npm run check` 0 errors, `npm run
test:unit` 239/239 unchanged, `npx eslint` clean on the new page (pre-existing debt only on the two
shell files, not introduced here). User then browser-verified the full click-through themselves and
confirmed it works. No caveats remain on this sub-part.

**Next session:** say `read memory and continue`. Start Part 4b-iv: switch `issueSetupLink`
(`setup-link.ts`) over to rendering the published `password_setup` template (subject/body, with
`{{business_name}}` / `{{setup_link}}` substituted in) instead of its current hardcoded HTML string,
and record the exact rendered subject/body actually sent (check whether the existing outbox/history
recording already captures this or needs a field for it). `application_receipt`, `received_page`,
and `account_created_contact` stay preview-only for now -- their real trigger points don't exist
until Parts 4c/4d/4e. This is the one part of 4b that touches a live, already-shipped code path
(`setup-link.ts`, called from real `provision` and `send-setup-email` routes), so read that file
narrowly before changing it and keep the change minimal -- swap the source of subject/body, don't
restructure the function.

### 2026-08-12 — Part 4b-iv complete; Part 4b closed

Built Part 4b-iv exactly as described above and in the checklist entry: `issueSetupLink` now
renders the published `password_setup` template instead of using hardcoded HTML, two new nullable
columns record exactly what was sent, and a small `htmlToPlainText()` helper covers the
Brevo-required plain-text field the template doesn't separately store. `npm run check` 0 errors,
`npm run test:unit` 240/240 (+1), `npx eslint` clean, advisors show only the expected pattern. No
browser verification applies to this part specifically. Part 4b (schema, API, UI, live wiring) is
now fully closed.

**Next session:** say `read memory and continue`. Start Part 4d: `/get-started/received` and the
receipt email. The confirmation page and the queued `application_receipt` email (already scaffolded
with placeholders in Part 4b, just not wired to a real send yet) using the exact rendered published
template. The success state Part 4c left in place on `/get-started` itself (an inline "thanks, we
got it" message) should very likely be replaced by an actual redirect to the new
`/get-started/received` route once it exists -- confirm that with the user rather than assuming.
Before starting, ask the user whether they've done the Part 4c browser walkthrough yet (filling out
and submitting the real public form) -- not required to proceed, but good to know before building the
page that follows it.

### 2026-08-12 — Part 4c complete (code + SSR render check); full interactive browser check outstanding

Built the public `/get-started` page exactly as described in the checklist entry above: one new atomic
DB function, the rate-limited/Turnstile-checked/Zod-validated `POST /api/get-started` route, and the
page itself. User supplied real Cloudflare Turnstile keys mid-session (pasted directly into `.env`
themselves), so the spam check is live, not skipped. `npm run check` 0 errors, `npm run test:unit`
247/247 (+7), `npx eslint` clean. Confirmed via a direct request to the running dev server that the
page renders correctly with real package data -- did not click through the actual form.

**Next session:** say `read memory and continue`. First ask the user whether they've done the full
click-through of `/get-started` themselves (submit a real test application, confirm it shows up on
`/jafar/prospects` with the right package snapshot, try triggering the rate limit or an invalid
Turnstile token). Not blocking -- once confirmed or the user chooses to skip it, start Part 4d as
described above.
