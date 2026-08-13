# Jafar A-Z Completion Contract

## Status and authority

**Approved.** This document promotes the newest locked Platform Owner decisions from the completed
audit and decision campaign. It owns the A-Z completion behavior. It works with the onboarding
implementation contract, ADR 0001, and the supporting organization-management mission. This
document wins where an older owner document differs.

Execution order and current progress live in `Memory/campaigns/jafar-panel/`; implementation truth
lives in code, migrations, and tests.

## Delivery and completion

- One A-Z campaign governs the complete Jafar mission and delivers independently verified parts.
- Each vertical part includes database and security work, server behavior, real UI, loading and
  failure states, cache invalidation, history and notifications, automated checks, and browser
  verification relevant to that part.
- A milestone closes only after its automated checks pass and Jafar approves the real browser journey.
- A future dependency may appear as `Coming later: requires <dependency>`, with no fake production action.
- Named owner accounts and MFA are outside this mission. Harden the current configured owner login
  with rate limiting, revocable sessions, short-lived password reconfirmation, and durable audit history.

## Public application and prospect review

- Public routes are `/get-started` and `/get-started/received`.
- The form is an onboarding application, not a signed service contract.
- It records business and contact details, an optional separate administrator, package interest, an
  optional note, and the accepted privacy-policy URL, version, and time.
- `main contact` is the person handling the application, business discussion, and payment.
- `administrator` is the person receiving account setup and controlling the contractor CRM. The
  form defaults to the contact and reveals separate name and email fields when they differ.
- Submission creates only a platform-owned application and immutable package snapshot. It creates
  no Auth user, organization, membership, contractor data, or session.
- Prospects cannot edit a submitted application. Jafar corrections preserve the original and require
  a private reason.
- Jafar reviews submissions at `/jafar/prospects`. Opening one does not change its stage. `Mark
  reviewed` explicitly moves `new` to `awaiting_payment` and sends no automatic prospect message.
- Normal lifecycle is `new -> awaiting_payment -> payment_confirmed -> account_created`; exception
  stages are `needs_attention` and `not_proceeding`.
- Duplicate candidates remain separate and are never merged automatically. Jafar acknowledges `not
  a duplicate` or marks an unpaid application `not_proceeding` with a required private reason.
- A `not_proceeding` application retains personal data for 12 months, then purges automatically.
- Server validation, rate limiting, Cloudflare Turnstile, accessible errors, and a server-only
  privileged credential boundary protect the public form.

## Public and owner messages

- Submission shows a received page and sends a receipt email to the main contact.
- The page and email use one global Jafar-managed offsite-payment instruction. Package name and exact
  price are protected placeholders.
- Account creation sends one single-use 24-hour password-setup email to the administrator. There is
  no extra administrator welcome email, and Jafar never handles a password.
- When contact and administrator differ, the contact receives business updates and only the
  administrator receives setup and account-access messages.
- Jafar can edit the received-page, receipt, password-setup, account-created contact notice, and
  later contractor-safe owner-action notices.
- Templates use guided formatted text, approved placeholders, desktop/mobile/email preview,
  `draft -> publish`, immutable version history, and restore-default.
- Future sends and resends use the latest published version. Send history keeps the exact rendered
  subject and body without secrets. Protected security, price, deadline, and setup-link blocks remain.
- Settings owns the privacy-policy URL/version, payment instructions, visible sender name, reply-to,
  and owner alert recipients. The verified Brevo From address stays in server configuration. The
  initial alert recipient is the configured owner login email.

## Jafar notifications

- New applications create a durable in-app notification and queued owner email alert. Application
  success does not depend on Brevo availability.
- The header shows an unread bell and recent menu. `/jafar/notifications` supplies searchable
  history, and the dashboard shows linked attention cards.
- Opening a linked prospect, organization, or recovery record marks its notification read. Individual
  read/unread and `Mark all read` are also supported.
- Email Jafar for new applications and urgent setup delivery, unsafe provisioning, provider outage,
  and permanent-deletion failures. Routine events remain in-app.
- Delivery is durable, idempotent, retryable, sanitized, and visible in Operations after terminal failure.

## Payment, provisioning, and setup

- Payment is offsite and manually confirmed. Store amount, USD currency, date, private reference or
  note, package version, and a mismatch reason when required. Store no payment credentials.
- Payment instructions are one global published template.
- Before organization creation, a refund or reversal appends history, moves the application to
  `needs_attention`, blocks provisioning, and creates an urgent alert.
- Payment confirmation and provisioning are separate explicit confirmations.
- Provisioning is application-bound, concurrency-safe, resumable, and idempotent. It cannot create a
  second Auth user, organization, assignment, or membership.
- Related database records are transactional. External Auth and email work uses durable attempts,
  explicit compensation, and an operator recovery state.
- Reject an administrator email already belonging to an organization. If an Auth identity exists
  without an organization, stop in `needs_attention` for verified recovery and never attach it automatically.
- Successful provisioning creates an active organization; administrator password readiness is separate.
- Setup-link consumption is atomic, single-use, recipient-bound, rate-limited, and expires after 24
  hours. Resend invalidates every earlier unused link. Delivery failure leaves the organization active
  and recoverable.
- Retire the legacy direct-create organization and password flow in the same usable release.

## Organization and commercial control

- The directory and detail route are searchable and paginated when needed. Independent panels do not
  block the shell.
- Detail sections are Overview, Commercial access, Integrations, Team access, and History and recovery.
- Package changes are immediate, separately confirmed, and retain old/new version, reason, and time.
  Exceptions require a reason, start date, and optional expiry.
- Support immutable confirmations and corrections for initial payment, renewal, refund, reversal,
  paid-through date, seven-calendar-day grace in the commercial timezone, and late-renewal reactivation.
- Suspension remains a separate confirmed action. Automatic overdue messaging and suspension remain out.
- Free access is exceptional and audited; permanent free access requires password reconfirmation.
- History combines onboarding, payments and corrections, provisioning and setup delivery, package and
  access changes, lifecycle, support, integrations, recovery, and deletion without exposing secrets.
- Contractor-visible notices contain safe outcomes only. Private reasons and raw provider details stay private.

### Commercial control decisions

- Jafar explicitly confirms the resulting paid-through date, or explicitly confirms no change, for
  every renewal, correction, refund, and reversal.
- Existing valid operational timezones become the one-time imported commercial-timezone baseline.
  Later operational changes never move a commercial timezone.
- A commercial-timezone change preserves the current deadline unless Jafar explicitly confirms
  recalculation.
- Contractor-safe events are stored separately from private history and written atomically with it.
- Commercial adjustments reference the original initial-payment or renewal confirmation.
- Late renewal may reactivate in one transaction while keeping the renewal and lifecycle records distinct.
- Legacy `pending_setup` review may span sessions. Resolving one to active requires a published
  version, paid-through eligibility or active free access, an owner or admin membership, safe login
  readiness, and a reconciliation reason.
- Existing reasonless exceptions stay effective as marked legacy imports until they are reviewed.
- Suspension categories are `nonpayment`, `payment_dispute`, `security`, `support`, and `other`.
- Commercial reactivation requires restored eligibility. Noncommercial reactivation requires a
  resolution reason and never invents payment history.
- Free access permits at most one active grant and one non-overlapping future grant.
- Protected directory search covers organization name, slug, and primary administrator email.
  Pagination uses `created_at, id` with a default page size of 50.

## Team support and owner security

- Jafar normally inspects team roles and effective permissions; contractors manage ordinary team access.
- Narrow profile corrections record before and after values, reason, confirmation, actor and time, and
  create a safe notice.
- Administrator email recovery uses trusted outside verification, a safe evidence summary, old/new
  email preview, cross-organization uniqueness, password reconfirmation, old-session and setup-link
  revocation, old/new address notices when possible, and retained safe history.
- Jafar never impersonates a contractor or becomes a tenant member.
- Every `/api/jafar/*` handler authenticates independently before privileged client use. Every write uses Zod.
- Current single-owner hardening includes login rate limiting and monitoring, revocable and rotatable
  sessions, short-lived password step-up, and sanitized audit and correlation records.

## Organization closure

- Closure starts a recoverable 30-day countdown and immediately blocks contractor access and new outbound work.
- Before starting, show affected users, data, files, provider connections, and scheduled work. Require
  a private reason, typed organization name, explicit confirmation, and password reconfirmation.
- Send editable contractor-safe notices at closure start, 14 days remaining, 3 days remaining, and
  completion. Protected deadlines and safety wording cannot be removed.
- During the window, only Jafar may restore after trusted outside verification, a safe evidence note,
  password reconfirmation, and provider-impact review.
- At day 30, permanently delete all live organization CRM data, Auth users, files, queued work, and
  connected provider resources. No anonymized organization or CRM record remains.
- Retain only a non-personal technical deletion receipt with a random operation ID, timestamps, and
  component success or failure checks. It contains no organization name, personal details, or CRM content.
- Deletion is resumable. Partial failure blocks completion, creates an urgent alert, and exposes safe
  retry and recovery. Supabase internal backup handling is outside this product mission.

## Provider and CRM-dependent controls

- Twilio is the SMS and phone provider, Brevo is the email provider, and Cloudflare R2 stores files.
- Contractor customer payments use contractor-owned Stripe accounts. Bangladesh cannot rely on normal
  Stripe Connect onboarding, so plan a secure manual restricted-key method unless a usable Stripe App
  or OAuth path is approved later.
- Contractor administrators enter the least-privilege restricted Stripe key and webhook secret.
  Encrypt secrets, never return them after saving, and never serialize them to Jafar or browser APIs.
  Store no publishable key unless the approved payment UI proves it is required.
- Jafar sees Stripe account identity, live/test mode, API health, webhook health, last check, and
  sanitized failures only, backed by one authoritative readiness source.
- Customer payment URLs recheck organization lifecycle and entitlement before creating a fresh Stripe
  Checkout session. Rotation, disconnect, suspension, and closure stop new sessions and reconcile old work.
- Journal Stripe events for idempotent replay. Money exceptions become urgent recovery tasks. Preserve
  append-only corrections, locking, tenant verification, test-mode journeys, and direct contractor payout.
- Webchat is a UCRM-hosted website widget feeding the contractor inbox.
- Jafar may inspect contractor-owned review links and campaign readiness. No direct Google or Facebook
  review-provider integration is planned.
- A Jafar feature whose contractor or provider subsystem does not exist remains dependency-linked and
  exposes no fake mutation. The agent building that subsystem also delivers its paired Jafar controls.
