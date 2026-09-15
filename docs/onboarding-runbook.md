# Assisted onboarding runbook

Internal steps for whoever moves a new contractor into the CRM. Follow this order every time so every
contractor gets the same treatment and nothing gets skipped. This is the "white-glove" half of Part 5 of the
onboarding-and-data-portability campaign; the other half is the automatic **Getting started** checklist the
contractor's owner/admin sees on their own dashboard (`src/lib/components/dashboard/GettingStartedCard.svelte`),
which tracks the same four milestones without anyone having to tick a box.

## Before the call

1. Confirm the contractor's package/plan and that their organization already exists (created via the normal
   signup or platform-owner provisioning flow — never by hand in SQL).
2. Ask what they're moving from (spreadsheet, another CRM export, paper) so you know which import path applies.

## During the assisted move-in

1. **Business profile** — have them confirm business name, timezone, and currency in
   Settings → Business Profile. Required before anything else, since invoices and quotes read these.
2. **Price Book** — import their products/services via Settings → Price Book → Import (the wizard built in
   Part 3: upload → map → review → commit). If they have only a handful of items, adding them by hand is fine
   too — the checklist only checks that at least one exists.
3. **Clients** — import their client list via the Clients import wizard (Part 1: upload → map → review →
   commit). Re-running the same file is safe; it will not create duplicates.
4. **Team** — send invitations to the teammates who'll use the CRM (Settings → Team). Confirm each person
   received their invite email.
5. **Opening balances** — not available yet (blocked on the launch financial-reconciliation audit, Part 4 of
   this campaign). Tell the contractor this is coming; do not attempt a manual workaround.

## Wrap-up

1. Log into the contractor's dashboard (or have them share their screen) and confirm the **Getting started**
   card shows all steps complete, or explain to them what's left and that they can finish it themselves.
2. Note anything unusual (large data set, rejected import rows, a custom request) so the next session
   doesn't have to rediscover it.
