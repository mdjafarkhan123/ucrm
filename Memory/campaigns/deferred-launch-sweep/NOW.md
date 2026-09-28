# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** Part 5 paused mid-work 2026-09-28 (Sonnet) — billing-contact email parity: schema, migration
applied, all app code (Zod/duplicates/API/UI/routes) written; a follow-up fix migration is drafted+committed
but blocked (see Blockers). `npm run check` and browser verification still needed. See
Memory/campaigns/deferred-launch-sweep/parts/part-5.md for exact remaining steps. Part 7 is held by another
session (worktree, not yet merged).

**Exact next action:** Resume Part 5 from its part note's unchecked steps (starts with checking whether
Part 7 has merged). Then do Part 6 (Opus).

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
