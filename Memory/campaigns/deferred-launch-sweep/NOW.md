# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** 4 — Fixing money mistakes (Opus). Decisions approved: D6–D9 in
docs/invoice-behavior-contract.md. Part 3 may still be running in another session; it owns only its roadmap
line and its own files (invoice counts, money overview migration) — commit only your own paths.

**Exact next action:** build slice 4a (void cancellation email), then 4b, 4c, 4d per ROADMAP Part 4. Delete
each task note + deferred INDEX row once its slices are done.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 4
