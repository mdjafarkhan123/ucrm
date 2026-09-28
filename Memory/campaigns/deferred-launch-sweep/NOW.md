# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** Part 5 is Done (2026-09-28) — billing-contact email parity browser-verified on Raad LTD
(Greenfield Property Group, invoice #35 and quote #44 both sent to primary + billing addresses, both access
links opened their document). Part 7e (price-list item picture) is built and merged to `main` (`572d7936`);
only its own browser verification is left — see Memory/campaigns/deferred-launch-sweep/parts/part-7.md.

**Exact next action:** Finish Part 7's remaining browser verification (see part-7.md Exact next action), then
do Part 6 (Opus).

**Question for Jafar (not yet asked):** the office and finance roles have no invoice permissions in the baseline
permission matrix (`supabase/migrations/20260101000200_baseline_reference_data.sql`), so a role named "finance"
can't open Invoices. Should they get some before launch?

**Blockers:** none for Part 6. Part 5's fix migration `20260928212000` is blocked on Part 7's
`20260928211000` landing on `main` first (see part-5.md Notes) — do not touch that worktree/branch. Do not
touch packages (Jafar, 2026-09-27). The CLI runs as `npx --no-install supabase`. Browser testing needs the
tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`; after a dev-server restart the page can
go blank — hard-reload (Ctrl+Shift+R).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:** Memory/campaigns/deferred-launch-sweep/ROADMAP.md Parts 5–6
