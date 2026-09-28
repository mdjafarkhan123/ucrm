# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** Parts 5 and 7 are both Done (2026-09-28). Part 5: billing-contact email parity
browser-verified on Raad LTD. Part 7: all five Jobber-parity slices (7a–7e) built and merged; 7e's price-list
photo is data-verified everywhere but stays a placeholder image because of the known files-processing-worker
gap (see `Memory/deferred/background-jobs-have-no-production-scheduler-decision.md`) — same as Parts 3, 8A, 8B.
Worktree `deferred-sweep-part7b` removed, fully merged.

**Exact next action:** Start Part 6 (Opus) — Protect customer history. See ROADMAP.md Part 6 line for its
four tasks. Separately (Sonnet, Part 9): the `non-admin-email-correction-browser-verification-part-7` deferred
note's trigger is now satisfied — Raad LTD's office/sales/finance test-role members exist (`dev.jafarkhan+office@gmail.com`
etc.). Reached the Jafar Panel → Organizations → Raad LTD → Team tab → office row → "Fix profile" dialog
(Name/Email/Correction reason fields) but did not submit a change — stopped before live-testing the PATCH
round-trip to avoid leaving a mutated login email unverified. Next session: fill Email with a test value,
Save correction, confirm it round-trips (re-open Fix profile, check the new value persisted), then change it
back to `dev.jafarkhan+office@gmail.com` before finishing, and delete the deferred note.

**Question for Jafar (not yet asked):** the office and finance roles have no invoice permissions in the baseline
permission matrix (`supabase/migrations/20260101000200_baseline_reference_data.sql`), so a role named "finance"
can't open Invoices. Should they get some before launch?

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). The CLI runs as `npx --no-install supabase`.
Browser testing needs the tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`; after a
dev-server restart the page can go blank — hard-reload (Ctrl+Shift+R).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:** Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 6
