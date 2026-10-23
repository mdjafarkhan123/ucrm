# Stage 10 Part 7 — Monthly number renewal

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 7
**Stage:** plan approved 2026-10-23 (Jafar: texting balance pays; 14-day grace; receive-only while unpaid).
Next: Pencil design. Nothing built yet.
**Done when:** each number is charged once a month from the bought balance; a short balance starts a 14-day
receive-only grace with warnings; a top-up pays and resumes sending; grace end releases the number (off while live SMS is off); merged to main.

## Pencil (next session, one board in `concept.pen`, light only)

Read the live screens first; add only renewal states:
- Business number card: "Renews <date> · <price>"; unpaid: "Couldn't renew — add <amount> by <date> or this number
  is released. Replies still arrive; sending is paused." + Add money; released state.
- Inbox composer notice while sending is paused.
- Control Room: Texting setup number cards and the business Texting card show "Unpaid · released in N days" and
  released; To do queue item "Unpaid number".

## Build notes (after approval, own branch/worktree)

- Today only the first month is charged: `communication_sms_open_number_order` /
  `communication_sms_record_number_purchased` in `supabase/migrations/20261222120000_sms_number_purchase.sql`
  (ledger key `number_order:<id>`; settled − reserved balance).
- Renewal state on `communication_sms_sender_identities` (paid through, next renewal, grace ends, state
  paid/unpaid/released) + a renewal-attempts table; `private.renew_sms_numbers()` on pg_cron every 15 min, modelled on
  `private.enforce_package_grace()` (`20260930140000_package_grace_pause_and_free_access.sql`).
  Ledger key `number_renewal:<number>:<period>`; rate = `communication_sms_effective_number_rate` on renewal day.
- Top-up confirmation retries unpaid renewals first.
- Sending gate in `private.communication_sms_route_check` (enqueue + claim); inbound untouched.
- Release worker under `src/routes/api/internal/communications/` via `getSubaccountAccess`
  (`twilio-provisioning.ts`); stays off with the SMS wake cron.
- Warnings: email + notification bell 3 days before renewal when short, on failure, 3 days before release.
- Checks: vitest date math (31st, leap year), charge-once, grace → release, top-up pays; rolled-back live-DB run; live
  Chrome light + dark vs the board with a temporary row removed after. No real charge or Twilio release.
