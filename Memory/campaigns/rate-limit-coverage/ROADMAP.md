# Roadmap — Rate-limit coverage (DRAFT, unverified)

Everything below is one session's first-pass research/scan, not an approved plan. Re-research and
re-verify from scratch before building anything — do not build straight from this file.

## Origin

Memory/deferred/authenticated-reads-and-pipeline-writes-are-not-rate-limited.md: quote/invoice/payment
writes already share one rate-limit bucket per organization (`enforceOrganizationWriteRateLimit`, 20
writes/60s, live-verified). Everything else — every authenticated GET/list read, and writes on jobs,
clients, requests, team, settings, pipeline, collaboration, checklists, signatures — has none.

## Draft finding: centralize instead of per-route

A scan of `src/routes/api` (487 route files) found 354 with no rate-limit call at all. Editing each route
individually was the original framing, but most organization-scoped routes already funnel through one of
two shared gates:

- `requireOrganizationPermission` / `requireOrganizationAdmin` (`src/lib/server/access/permission.ts`) —
  276+ direct call sites, reaches Jobs, Clients, Requests, Pipeline, Properties, Team, Settings,
  Collaboration, Checklists, Signatures, Quotes, Invoices, Payments.
- `getOwnerSession` / `ownerUnauthorized` (`src/lib/server/access/owner.ts` + `src/lib/server/auth/owner.ts`)
  — 96 of the Jafar Panel routes.

Draft idea: add the rate-limit check inside those two gates once, instead of touching hundreds of files,
so current and future routes are covered automatically. Mirrors the "single enforcement point" pattern
used by GitHub/Stripe/Cloudflare-style APIs.

## Draft parts (unapproved, re-derive before use)

1. **Core organization gate** — read + write limiting inside `requireOrganizationPermission` /
   `requireOrganizationAdmin`. Reuse the existing fixed-window `check_rate_limit` mechanism and the
   existing write ceiling (20/60s per org per domain); add a separate, higher read ceiling. Retire the
   now-redundant standalone quote/invoice/payment write-limit calls once the central gate covers them.
2. **Jafar Panel gate** — same shape inside the owner-session gate, covering the ~96 admin routes.
3. **Leftover sweep** — routes that reach neither gate: some `public/*` token routes, `internal/*` worker
   routes, `webhooks/*`. Most already have their own protection (signature/secret/IP); confirm and close
   any real gap, leave the rest with a one-line reason.
4. **Close-out** — delete the deferred note, remove dead code.

## Known risk

Both gates are the busiest code paths in the app. A mistake here has app-wide (Part 1) or
Jafar-Panel-wide (Part 2) blast radius. Re-verify this is still true and test under more than one role
before treating any part as done.

## Not yet decided (needs the redo)

- Exact read-limit numbers (a reasoned default was floated, not confirmed).
- Whether "domain" bucketing should derive from the permission-key prefix or from something else.
- Full inventory/disposition of the leftover sweep (Part 3) — only spot-checked, not exhaustive.
