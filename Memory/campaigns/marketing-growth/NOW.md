# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. Provider boundary: Brevo for Jafar/platform email only; Amazon SES for contractor CRM
operational + Marketing email. Marketing stays disabled globally until M6.

**SES event pipeline: built and proven** (sandbox, account `881776924275`, `us-east-1`). Detail in plan §2. AWS CLI
access = IAM Identity Center SSO profile `ucrm` (`aws sso login --sso-session ucrm`).

**M1 committed so far:** `37f8268` (consent ledger + feature/permissions + public-form opt-in + staff-recorded
consent) and `43c9e53` (unsubscribe). Both applied to dev `lgerqoeyusspmgzecwjs` and browser-verified.

**Allowance slice: DONE.** Migration `20261014110000_marketing_allowance_limit.sql` (applied to dev, checks pass):
new limit key `marketing_email_recipients`, unset on all packages; no separate period table (reuses the monthly window).

**Unsubscribe slice: DONE, committed `43c9e53`.** Migration `20261014100000_marketing_unsubscribe_links.sql`.
Approved by Jafar 2026-09-20: confirm-button page (not act-on-open, because mail scanners prefetch links) plus
RFC 8058 one-click headers; schema addition approved. Routes `/u/[token]` (page + form action) and
`/u/[token]/one-click` (POST only, 200, never a redirect). Helper `$lib/server/marketing/unsubscribe-links.ts`
owns the token, the two URLs, and `marketingUnsubscribeHeaders()` — the header builder has no caller until the
M3 footer renders it. Verified: confirm→done, reopen shows already-unsubscribed, unknown token is unavailable,
one-click POST 200 with GET 405, two POSTs wrote one event, Customer page reads "Opted Out · via unsubscribe
link". Dev data now has three opted-out test addresses (Dana Whitfield, Tobias Lindqvist, Ingrid Van Der Berg).

## Active part

M1 — next slice: Marketing readiness read (blueprint §6).

## Exact next action

Build the readiness read: one server function returning the blocking reasons (domain, business address, sender,
pause, allowance, consent) with fix links. Allowance reason reads `private.effective_marketing_email_limit`
(state `not_included` = "Marketing allowance not configured"). Then the Growth → Marketing nav + home shell.
Still owed before M3 launch: a Jafar packages-page field + org-exception field for the Marketing allowance (writer
`manage_platform_package_marketing_allowance` and the override key already exist, no UI yet), and the legacy
`marketing` column drop (needs schema approval). Usage counting/reservation arrives with M3 launch. See plan §3 M1.

## Blockers

M4 needs SES production access (still sandbox 200/day). M9 blocked until Communications A2 passes live SMS gates.

## Open side question

Delete unused `.claude/skills/aws-mail-manager` skill? (unanswered)

## Essential pointers

- Plan: `docs/marketing-first-release-plan.md` (§2 pipeline; §3 M1 slices)
- Consent/link patterns mirrored: `20261014090000_...consent_ledger.sql`,
  `20260821035539_quote_customer_access_links.sql`

Resume: `continue marketing growth` — next slice is the Marketing readiness read.
