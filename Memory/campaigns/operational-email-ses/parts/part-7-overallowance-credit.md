# Part 7: Over-allowance email credit -- 7A done, 7B/7C remain

Contract: `docs/contractor-email-contract.md` "Package allowances and counting" (approved 2026-08-15,
amended 2026-09-24).

## 7A -- done 2026-09-26

Migration `supabase/migrations/20260926233000_operational_email_overallowance_credit.sql` is live on the
remote database. It widens `communication_sms_credit_reservations` to also hold an email over-allowance
credit hold (channel = 'email'), adds `communication_email_retail_rates` +
`communication_email_effective_retail_rate`/`communication_email_set_retail_rate`, converts the essential-
reserve-exhaustion alert from a trigger to a plain function, and rewrites `claim_communication_outbox_event`
/ `finalize_communication_outbox_event` so essential email never queues (alert once, then send) and optional
email over its allowance funds itself from the shared Communication Balance, deferring with
`email_balance_insufficient` when the balance is too low. Full design/logic lives in the migration file's
own comments -- read it there, not here, if you need the mechanism.

Caught and fixed while building this: the packet's original design was drafted against a stale copy of
`claim_communication_outbox_event` (the pre-2026-09-25 baseline). The live function had since gained
`organization_id`/`sender_provider` output columns (migration `20260925191000`), which made every bare
`organization_id` column reference in the new credit code ambiguous against that OUT parameter (PL/pgSQL
`variable_conflict = error`). Fixed by table-qualifying every such reference and using
`on conflict on constraint communication_sms_credit_accounts_pkey` instead of a bare column list. Verified
by a full local `supabase db reset` + manual SQL exercise of all four scenarios (essential-alert-then-send,
published-rate charge, insufficient-balance defer, retry-releases-and-re-reserves) before pushing.

Also updated `supabase/tests/database/communications_email_allowance_usage_and_reserve_alerts.sql`, whose
assertions encoded the old (pre-Part-7) essential-queues-on-exhaustion behavior and the now-removed trigger;
it now asserts the trigger is gone and that essential mail past its reserve is claimed and sent.

Not yet verified live against a real SES send (no rate has ever been published on the real database, so no
organization has actually gone over-allowance yet) -- the local manual SQL exercise is the only proof so far.

## 7B -- Jafar price-setting UI -- done 2026-09-26

Built `src/lib/components/jafar/EmailRetailRateActions.svelte` +
`src/routes/api/jafar/communications/email/retail-rates/+server.ts` (GET/POST), mirroring the SMS pair but
without SMS's destination/sender/message-unit dimensions -- one price per currency. Added
`communicationEmailRetailRateSchema` to `owner.schema.ts`. Wired into
`src/routes/jafar/(protected)/communications/+page.svelte` under Email sending capacity. Shows the contract's
required reference copy (SES ~$0.10/1,000; HighLevel ~$0.675/1,000 from a wallet; Mailchimp overage blocks;
Jobber no limit).

Caught while building: `SmsRetailRateActions.svelte`'s exact pattern (`let retailRateMajor = $state('')` then
`providerCostMajor.trim()`) throws `TypeError: $.get(...).trim is not a function` at submit time, because
`Input` with `type="number"` binds back a JS `number | null`, never a string -- confirmed live in the browser
against the real Jafar panel (the click silently did nothing, no network request fired, until fixed). Fixed
in both the new email component and the pre-existing `SmsRetailRateActions.svelte` (now `$state<number |
null>`, no `.trim()`/`Number()` conversion needed). The SMS fix is inferred correct from the identical,
now-verified-working email code path -- not independently re-tested live, to avoid publishing an unwanted
real SMS price as a side effect of testing.

Verified live end-to-end in the browser as Jafar: published a real $0.675 USD / 1,000 recipients rate
(matching HighLevel, provider cost $0.10 noted) with Jafar's explicit go-ahead -- confirmed in
`communication_email_retail_rates` and `platform_audit_events` via SQL. A real rate is now live on the
production database.

## 7C -- contractor-facing "add credit" messaging -- done 2026-09-26

Found `failure_message` already rendered verbatim in the Communications inbox (both SMS and email outbound
notices, `src/routes/(app)/communications/+page.svelte`), with no CTA. Flagged the settings-page-rename
question to Jafar; he approved both the rename and a clickable CTA.

Built: renamed `settings/communications/sms-usage` to `settings/communications/balance`
(`src/routes/(app)/settings/communications/balance/+page.svelte`), retitled "Communication Balance", and
relabeled its still-SMS-only sections ("SMS messaging health", "SMS usage this month") so the page stays
honest about what data is per-channel vs. shared. Updated the two references (`+layout.svelte` warm list,
`settings/+page.svelte` card) and un-gated that settings card from `home.readiness.sms_registration` --
email-only contractors need to reach it too. Added `failure_code` to the outbound select in
`api/communications/email-history/+server.ts` and to `InboxEmail` (`$lib/communications/inbox.ts`); the
email failure notice now shows an "Add credit" link to the balance page when
`failure_code === 'email_balance_insufficient'`. Left the SMS notice branch untouched -- no confirmed
per-message SMS balance-insufficient failure_code exists to key off, so nothing was added there.

Flagged usage-summary mixing bug -- fixed 2026-09-26 (approved by Jafar, citing GHL/HighLevel's own wallet
page: one shared balance, usage broken out per channel underneath it -- confirmed by web search of
HighLevel's Wallet & Transactions help docs). `api/settings/communications/sms/usage/+server.ts` now filters
`communication_sms_credit_reservations` to `channel = 'sms'` for the SMS summary, and joins
`communication_sms_credit_ledger_entries` back through the reservation it settled (via the
`communication_sms_credit_ledger_entries_reservation_fk` embed) to filter charge totals by channel too
(ledger entries carry no channel column of their own). Added a parallel `email_usage_summary`
(recipients + retail charge, channel = 'email') and a matching "Email usage this month" KPI card on the
Balance page. Verified: unit test extended to assert SMS and email totals stay separate
(`sms-usage-contractor.spec.ts`), `svelte-check`/prettier clean, browser-verified live on Raad LTD (renders
$0.00 / 0 recipients, correctly zero since no organization has gone over-allowance for real yet).

Verified: `npx prettier --check`, `NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check` (only the 3
pre-existing unrelated errors), `vitest run inbox.spec.ts` (24 passed), and browser-verified live as the
Raad LTD contractor owner -- renamed page loads/labels correctly, settings card links to the new URL and
shows without SMS registration, Request top-up dialog still works. The "Add credit" CTA itself was not
seen live (no real `email_balance_insufficient` message exists in test data yet) -- code-reviewed only,
mirrors the already-working "Related work: View quote" notice pattern in the same file.

## Notes that still apply

- Another agent works a different campaign in this same repo folder; commit only operational-email files.
- `npm run check` OOMs; use `NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check --tsconfig
  ./tsconfig.json`. Three pre-existing "union type too complex" errors are not ours.
- A rebuilt local database has no real Vault webhook secret, so any insert into
  `communication_outbox_events` fires `trigger_communication_email_outbox_wake` and aborts the transaction.
  For local pgTAP/manual verification of anything touching the outbox, wrap the check in
  `set local session_replication_role = replica;` first -- never disable the trigger in a real migration.
