# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** Parts 5, 7, 8 and 6B Done (2026-09-28) — details in ROADMAP.

**Exact next action:** **6C, property cascade delete** (Opus) — read `parts/part6-protect-customer-history.md`.
After it, Part 11 (speed on client pages, Opus) and Part 10 (merge clients, Opus). Part 9 waits on Jafar for
a throwaway org and a Stripe test key.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). The CLI runs as `npx --no-install supabase`.
Browser testing needs the tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`; after a
dev-server restart the page can go blank — hard-reload (Ctrl+Shift+R). When the Chrome extension is not connected, a headless Playwright script
against `localhost:5173` works — wait ~8 s after opening a login page before submitting, or it posts natively.

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:** Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 6
