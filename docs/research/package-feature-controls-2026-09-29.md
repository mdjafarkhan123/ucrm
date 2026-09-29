# Package feature controls

Read-only code and primary-source review, 2026-09-29. Candidate controls, not a completed readiness audit or approved product behavior.

## Industry pattern

Jobber differentiates plans by included users and features, with marketing available as an add-on. [Jobber subscription guide](https://help.getjobber.com/en/articles/how-to-subscribe/). Chargebee distinguishes on/off features from numerical quantities and bounded ranges. [Chargebee feature types](https://www.chargebee.com/docs/billing/2.0/entitlements/features-overview). Adopt feature switches and explicit, typed limits rather than free-text feature promises.

## Current application evidence

- `supabase/migrations/20260101000200_baseline_reference_data.sql`: catalog includes core CRM, scheduling, team, pipeline, communications, portal, automations, marketing, reputation, reporting, dispatch, and integrations.
- `src/lib/server/access/effective.ts`: runtime mappings cover pipeline, inbox, portal, automations, marketing, reputation, reports, and team. A mapping alone does not prove complete enforcement.
- `src/lib/server/validation/package.schema.ts` and `access.schema.ts`: existing configurable values cover employee seats, operational and essential email recipients, marketing email recipients, website widgets and accepted conversations, and seven automation settings.
- Automation settings include active recipes, conditions, steps, message count, minimum message spacing, maximum delay, and enrollment duration. Separate sellable allowances from safety protections before exposing the new controls.
- Dispatch and API integrations appear in the catalog without matching literal runtime references found in the source audit. Treat readiness as unverified, not as absent functionality or completed features.

## Proposed feature round

1. Separate selectable extras: sales pipeline, shared inbox, website chat, marketing email, review requests, custom automations, and advanced reports. Show only verified capabilities as publishable; dependency requirements remain visible.
2. Tune business limits: team size, email allowances, website chat allowances, and active automations. Exact values, counting rules, reset periods, and exhaustion behavior need later decisions. Existing controls are evidence, not a ceiling on the design.
3. Include normal scheduling and essential customer quote/invoice access in the CRM basics; reserve advanced extras for optional selection.
4. Show required supporting features and let Jafar add them explicitly; prevent publishing a broken combination. Keep safety protections separate from sellable limits and enforce them for every package.

All four proposals await Jafar. Provider readiness and enforcement must be checked before any capability is sold; this research did not access the remote database or verify live screens.
