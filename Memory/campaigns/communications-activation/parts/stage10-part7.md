# Stage 10 Part 7 — Monthly number renewal

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 7
**Design:** Pencil board `QiDBX` approved B (Jafar 2026-10-23). Rules: `.claude/skills/design/layout.md` § Number
readiness (Renewal strip) and § Texting setup (Unpaid number task), `inbox.md` § Reply box.
**Stage:** Building — branch `claude/stage10-part7-build`, worktree `.worktrees/stage10-part7`, claim
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

## Next (exact)

1. `TaskQueue.svelte`: add an `unpaidTasks` prop → rows "Unpaid number · <name>", meta "<business> · since <date> ·
   released in N days", chip "Unpaid number" with `wallet`.
2. `texting-setup/+page.svelte`: add unpaid tasks to `AnyTask` / `ordered` (`'sender_id' in task`); render
   `UnpaidNumberPanel` (pass `businessHref(task)`); don't pin them and keep them out of the `shown` result logic.
3. Release worker: in `sms-worker.ts` `runMonitoredSmsWake`, after the drain, read
   `communication_sms_due_number_releases`, DELETE `IncomingPhoneNumbers/{sid}.json` via `getSubaccountAccess`
   (look up the SID with `findOwnedPhoneNumber` when it's missing; a 404 counts as released), then
   `communication_sms_record_number_released`. Add `releasePhoneNumber` to `twilio.ts` next to the purchase client. Vitest with fake Twilio.
4. Compile check through the dev server, svelte-autofixer on the changed components, focused vitest.
5. Live Chrome check at 1440 light + dark against `QiDBX`: add a temporary unpaid state to the test number, check
   card / reply box / Control Room, then put the row back. No real charge or Twilio release.
6. Commit, merge to main (integration claim), update NOW.md, release the claim.

Known, not touched (needs Jafar's yes): `number-readiness.spec.ts` "toll-free … action toBeNull" was already failing
before this part (Part 4c added the action).
