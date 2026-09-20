# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

Paused 2026-09-20 at a clean boundary. Provider boundary: Brevo for Jafar/platform email only; Amazon SES for contractor CRM
operational + Marketing email. Marketing stays disabled globally until M6 (feature `marketing` is in no package).
SES event pipeline is built and proven in sandbox (plan §2; AWS access = SSO profile `ucrm`).

M1 complete and committed (`8ef77f7`).

M2a (server) done: `marketing_customer_groups`, the whitelist rule compiler, and the two preview functions,
with 17 pgTAP checks and 8 unit tests passing. Applied to dev; `npm run check` clean.

## Active part

M2 customer groups. M2a (server) closed; M2b (Customer groups UI) is next.

## Exact next action

Build M2b: the Marketing → Customer groups view (saved-group list with counts, rule builder, live count,
"View customers" preview split). Load the `design` and `svelte` skills first. The API is
`/api/marketing/customer-groups` (GET/POST), `/[id]` (PATCH/DELETE), `/preview` (POST, `view: counts |
recipients`). Browser-verify the whole M2 path there, since M2a has no UI of its own yet.

## Blockers

M4 needs SES production access (sandbox 200/day). M9 blocked until Communications A2 passes live SMS gates.

## Open side questions

- Delete unused `.claude/skills/aws-mail-manager` skill? (unanswered)
- Two Customers in one organization cannot share an email address today (a unique index forbids it), so the
  blueprint's "duplicate email destinations" number is always 0. The preview still computes it. Tell Jafar
  if he ever wants shared household emails allowed.

## Pointers

Part packet: `Memory/campaigns/marketing-growth/parts/m2-customer-groups.md` (holds the performance design
verdict and the evidence M2's verification must still collect).
Plan: `docs/marketing-first-release-plan.md` (§3 M2). Blueprint: `docs/marketing-product-blueprint.md` (§8).

Resume: `continue marketing growth`
