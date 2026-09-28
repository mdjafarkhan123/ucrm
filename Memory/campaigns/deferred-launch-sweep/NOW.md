# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** 4 — Fixing money mistakes. Note: `parts/part-4.md`. Decisions D6–D9 in
docs/invoice-behavior-contract.md. Part 7 is held by another session (worktree, not yet merged).

**Exact next action:** Jafar must decide the database-guard fix in `parts/part-4.md` (Rebill on a voided
invoice fails). After his answer: apply it as one new migration, retest Rebill on Raad LTD, then close Part 4.

**Blockers:** waiting on Jafar (the guard fix above). Do not touch packages (Jafar, 2026-09-27).
Browser testing needs the tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`; after a
dev-server restart the page can go blank — hard-reload (Ctrl+Shift+R).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:** Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 4
