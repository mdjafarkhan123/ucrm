# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** Parts 5 and 7 Done (2026-09-28) — details in ROADMAP. Part 6 split after checking its notes
against the real code; 6A Done.

**Exact next action:** **6B, client archive and restore** (Opus) — read the part note
`parts/part6-protect-customer-history.md`, which also holds the design for 6C, the destructive property
cascade delete. Separately (Sonnet, Part 9): the `non-admin-email-correction-browser-verification-part-7` deferred
note's trigger is now satisfied — Raad LTD's office/sales/finance test-role members exist (`dev.jafarkhan+office@gmail.com`
etc.). Reached the Jafar Panel → Organizations → Raad LTD → Team tab → office row → "Fix profile" dialog
(Name/Email/Correction reason fields) but did not submit a change — stopped before live-testing the PATCH
round-trip to avoid leaving a mutated login email unverified. Next session: fill Email with a test value,
Save correction, confirm it round-trips (re-open Fix profile, check the new value persisted), then change it
back to `dev.jafarkhan+office@gmail.com` before finishing, and delete the deferred note.

**Answered 2026-09-28:** finance's missing invoice permissions are fixed and browser-verified on Raad LTD —
finance sees the list and all three write buttons, office sees the list and amounts with none.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). The CLI runs as `npx --no-install supabase`.
Browser testing needs the tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`; after a
dev-server restart the page can go blank — hard-reload (Ctrl+Shift+R).

**Known unrelated failure:** `src/routes/api/team/invitations/[invitationId]/resend/resend.spec.ts` fails
(mock call arguments) — pre-existing.

**Pointers:** Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 6
