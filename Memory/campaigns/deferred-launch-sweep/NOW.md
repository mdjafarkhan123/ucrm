# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** 4 — Fixing money mistakes (Opus). Decisions approved: D6–D9 in
docs/invoice-behavior-contract.md. Part 3 may still be running in another session; it owns only its roadmap
line and its own files (invoice counts, money overview migration) — commit only your own paths.

**Exact next action:** 4a–4c done (`4d96acd1`, `f6f95e39`; DB proven in rolled-back transactions, screens not yet
clicked through — Chrome extension was offline). Build 4d: Correct invoice (prepare → edit draft → "Replace invoice"
dialog showing difference + carried payments → activate) and Rebill on a voided invoice. activate_invoice_replacement
must carry the original's live allocations (payments and deposits) onto the replacement, capped at its total (D6);
issue_invoice must refuse a replacement draft (today a plain Send would leave both bills live). Then browser-check
4a–4d and close Part 4.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 4
