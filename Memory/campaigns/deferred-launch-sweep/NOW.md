# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** none started — Part 4 is Done (2026-09-28). Next: Part 5, Complete customer documents (Sonnet).
Part 7 is held by another session (worktree, not yet merged).

**Exact next action:** Part 5 — the one item left is `invoice-email-sends-to-primary-only-not-billing-contact`
(deferred note holds the spec); it was waiting on Part 4, which is now done. Then do Part 6 (Opus).

**Question for Jafar (not yet asked):** the office and finance roles have no invoice permissions in the baseline
permission matrix (`supabase/migrations/20260101000200_baseline_reference_data.sql`), so a role named "finance"
can't open Invoices. Should they get some before launch?

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). The Part 7 session's migration
`20260928180000` is applied to the database but not yet in this folder, so `supabase db push` refuses until
Part 7 merges; the CLI runs as `npx --no-install supabase`. Browser testing needs the tunnel
`cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`; after a dev-server restart the page can go
blank — hard-reload (Ctrl+Shift+R).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:** Memory/campaigns/deferred-launch-sweep/ROADMAP.md Parts 5–6
