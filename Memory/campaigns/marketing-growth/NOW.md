# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

In progress 2026-09-20. M1, M2, M3a complete and committed (`8ef77f7`, `a3f13ca`, `e854a84`, `9e99852`).

M3b's first slice, the Templates tab, is done, browser-verified against the real managed Supabase project (Raad
LTD, `jafarkhaninupwork@gmail.com`), and committed (`e53d53a`): Starter templates list (Preview + Use template,
copy renders through the existing campaign-preview endpoint into a sandboxed iframe with a desktop/mobile
toggle) and Your templates list (Preview only -- no edit/delete API exists for org templates yet, so none is
offered). A copied starter shows "Added to your templates" instead of a second copy action. `npm run check`: 0
errors. Prettier clean on touched files.

## Active part

M3b in progress. Templates tab closed. Campaigns list tab and the five-step campaign creation journey (goal,
customers, block editor, delivery, review) are next -- deliberately not started together with Templates because
both need routes/screens that do not exist yet (no campaign detail page, no journey), so there was nothing
useful to link a Campaigns list to yet.

## Exact next action

Build the Campaigns list tab (same SectionBlock/DataTable/EmptyState shell as Customer groups and Templates;
`fetchCampaigns`/`marketingCampaignsKey` already exist in `src/lib/marketing/api.ts`) together with the
five-step campaign creation journey it links to, modeled on `src/routes/(app)/clients/import/+page.svelte`'s
step-state/step-component/mutation-per-step structure (Explore-agent survey, 2026-09-20, confirmed this is the
closest existing precedent; no reusable block-editor or drag-and-drop component exists, so the block editor
(step 3) is new, following `src/lib/forms/*`'s ordered-typed-item pattern with up/down reordering, no new
drag-and-drop dependency). Leave-guard precedent: `beforeNavigate`/`onbeforeunload` pair in
`src/routes/(app)/settings/business-profile/+page.svelte`. Steps 4 (Delivery) and 5 (Review) build the UI only;
the real Send/Schedule launch command is M4's job -- decide how the button behaves before M4 exists (disabled
with a note, most likely) when starting that step.

This is large; split it at the next safe verified boundary (e.g. Campaigns list + journey shell/steps 1-2 first,
then the block editor, then steps 4-5) rather than attempting it as one session.

## Blockers

None. M4 needs SES production access + real SES send code (unrelated, later, also owns the deferred test-email
piece -- see plan doc). M9 blocked until Communications A2 passes live SMS gates (unrelated, later).

## Pointers

Plan: `docs/marketing-first-release-plan.md` (§3 M3, M4). Blueprint: `docs/marketing-product-blueprint.md` (§7
campaign list/lifecycle, §8 the five-step journey and block editor spec). M2's customer-groups UI and M3b's
Templates tab are the convention template for the Campaigns list.

Resume: `continue marketing growth` -- go straight to "Exact next action" above.
