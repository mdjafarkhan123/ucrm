# Stage 10 Part 7 — Monthly number renewal

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 7
**Design:** Pencil board `QiDBX` approved B (Jafar 2026-10-23). Rules: `.claude/skills/design/layout.md` § Number
readiness (Renewal strip) and § Texting setup (Unpaid number task), `inbox.md` § Reply box.
**Stage:** Built, waiting to merge — branch `claude/stage10-part7-build`, worktree `.worktrees/stage10-part7`, claim
`6be781d0a40a` (owner `claude-stage10-part7-build`). Not merged.
**Done when:** each number is charged once a month from the bought balance; a short balance starts a 14-day
receive-only grace with warnings; a top-up pays and resumes sending; grace end releases the number (off while live
SMS is off); live-checked against `QiDBX`; merged to main.

## Done (2026-10-23)

- Migration `20270106090000_sms_number_renewal.sql` **applied to the live DB** and recorded. Renewal columns on
  `communication_sms_sender_identities`, `communication_sms_number_renewals` table, `private.charge_sms_number_renewal`,
  `private.renew_sms_numbers()` on pg_cron `communications-sms-number-renewal` (every 15 min), owner alerts
  (`communications.number_renewal`, subject `sms_number`), top-up confirm pays unpaid renewals first, route check
  code `number_unpaid`, pick_sender prefers a paid number, `communication_sms_due_number_releases` /
  `communication_sms_record_number_released`. Rolled-back live run passed every scenario (script was in the
  session scratchpad; the steps are the checks listed below).
- The only existing number (test org, +13613262553) now renews 2026-11-13 at US local $2.00.
- `database.types.ts`: only the renewal parts spliced in (a full regenerate drags in Messenger Part 9's unmerged tables).
- Phone & SMS cards: `number-readiness.ts` (`renewalStrip`, statuses `sending_paused` / `released`, steps `paused` /
  `ended`), readiness API prices each renewal and returns the balance and released numbers for 30 days,
  `NumberReadinessCard.svelte` draws the strip, meter / 14 day blocks, Add money, released look. 6 new unit tests pass.
- Reply box: sms-estimate returns `sender_name` / `can_add_money` for `number_unpaid`; `ConversationComposer.svelte`
  shows the reason line (Add money → Balance, or "Ask an admin to add money").
- Alerts: kind added to `notifications.ts` (href → Phone & SMS), `bell-tiles.ts`, `alerts.ts`, email footer.
- Control Room: `sms-unpaid-number-tasks.ts` + API returns `unpaid_number_tasks` (counted in To do);
  `UnpaidNumberPanel.svelte` written but **not wired yet**.

- Control Room wired: `TaskQueue.svelte` rows "Unpaid number · <name>" (wallet chip), page renders
  `UnpaidNumberPanel`; unpaid tasks are never pinned.
- Release worker: migration `20270107090000_sms_number_release_at_twilio.sql` **applied and recorded** (release is
  recorded here first so a late top-up can't pay a let-go number; `provider_released_at` + retry list).
  `sms-number-release.ts` runs inside `runMonitoredSmsWake` under the lease; `releasePhoneNumber` in `twilio.ts`
  (404 = released). 6 new vitest cases pass.
- Live check (branch dev server, 1440 light + dark) against `QiDBX`: Control Room row + panel and the Phone & SMS
  card strip match. Reply box line not seen live: Raad LTD's plan has no texting and its number is pending setup,
  so the route stops earlier. Test number restored (paid, renews 2026-11-13); no alerts created.

## Next (exact)

1. Merge to main (integration claim), push, update NOW.md, release the claim.

Known, not touched (needs Jafar's yes): `number-readiness.spec.ts` "toll-free … action toBeNull" was already failing
before this part (Part 4c added the action).
