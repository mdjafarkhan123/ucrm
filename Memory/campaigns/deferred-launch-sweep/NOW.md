# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** 4 — Fixing money mistakes (Opus). Decisions approved: D6–D9 in
docs/invoice-behavior-contract.md. Part 3 may still be running in another session; it owns only its roadmap
line and its own files (invoice counts, money overview migration) — commit only your own paths.

**Exact next action:** finish slice 4d. DB is done and live (`444935b5`, migration 20260928160000). Screens are
committed as WIP, lint-clean but NOT yet svelte-checked: run svelte-check (3 "union type too complex" errors in
OpportunityBriefDrawer, (app)/+layout, invoices/new are pre-existing — ignore), fix anything new, then
browser-check all of 4a–4d on Raad LTD (Chrome extension was offline all session): void #30 with the email box
(goes to Jafar's +part8 inbox); split a payment; Fix payment + Mark never received; Correct invoice → edit →
Replace invoice (carries payments), and Rebill on a voided bill. Then delete
`issued-invoices-cannot-be-corrected-from-the-browser` + its deferred INDEX row, mark Part 4 Done in ROADMAP,
move to Part 5.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 4
