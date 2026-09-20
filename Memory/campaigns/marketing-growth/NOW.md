# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. Provider boundary: Brevo for Jafar/platform email only; Amazon SES for contractor CRM
operational + Marketing email. Marketing stays disabled globally until M6 (feature `marketing` is in no package).

M1 complete and committed (`8ef77f7`). M2 (server + UI) complete: M2a committed (`a3f13ca`); M2b browser-verified
end to end against the real managed Supabase project (Raad LTD, `jafarkhaninupwork@gmail.com`) — create, every
condition type, live count, View customers, save, reopen/edit with correct label hydration, delete — and ready
to commit. One real bug was found and fixed during that verification: see ROADMAP.md's M2 entry.

The `marketing` feature override granted to Raad LTD for testing (`18f0d717-904e-48d8-bd99-9df7e3844cda`)
expires automatically ~2026-09-20 11:31 UTC; no cleanup needed unless testing resumes after that.

## Active part

M2 closed. M3 (drafts, goals, templates, editor, test email) is next, per
`docs/marketing-first-release-plan.md` §3.

## Exact next action

1. Commit the M2b changes (marketing UI components, `lead-sources.ts` extraction, labels endpoint,
   `AsyncMultiPicker` `SvelteMap` fix) — not yet committed as of this checkpoint.
2. Read `docs/marketing-first-release-plan.md` §3 M3 and `docs/marketing-product-blueprint.md` for M3's
   approved shape, then follow Non-Negotiable Rule 3 (research how mature products handle campaign drafts,
   goals, templates, and a branded email editor) before planning implementation.

## Blockers

None for starting M3. M4 needs SES production access (sandbox 200/day) — unrelated, later. M9 blocked until
Communications A2 passes live SMS gates — unrelated, later.

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§3 M3). Blueprint: `docs/marketing-product-blueprint.md`.

Resume: `continue marketing growth` — go straight to "Exact next action" above.
