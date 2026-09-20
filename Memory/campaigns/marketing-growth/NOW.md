# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. Provider boundary: Brevo for Jafar/platform email only; Amazon SES for contractor CRM
operational + Marketing email. Marketing stays disabled globally until M6 (feature `marketing` is in no package).
SES event pipeline is built and proven in sandbox (plan §2; AWS access = SSO profile `ucrm`).

M1 done and committed: consent ledger, feature/permissions, public-form opt-in, staff-recorded consent (`37f8268`),
unsubscribe (`43c9e53`), allowance limit (`62fe54d`).

Readiness slice committed (`a2d363a`).

Allowance UI committed and browser-verified (packages page Marketing field; org Communications tab card). Saving a
package/exception with a real value was not exercised live (API spec covers the call).

## Active part

M1 — remaining: legacy `marketing` column drop only.

## Exact next action

Show Jafar a read-only count of the legacy `marketing` column and get schema approval before dropping it. Usage
counting/reservation arrives with M3 launch. After M1: M2 customer groups (performance design branch first).

## Blockers

M4 needs SES production access (sandbox 200/day). M9 blocked until Communications A2 passes live SMS gates.

## Open side question

Delete unused `.claude/skills/aws-mail-manager` skill? (unanswered)

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§3 M1). Blueprint: `docs/marketing-product-blueprint.md`.

Resume: `continue marketing growth`
