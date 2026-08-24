# Toast Coverage Sweep: Current Checkpoint

## Goal

Every save, delete, and archive action app-wide shows a success toast (and an error toast, or inline
error where one exists) via `getToastManager()` (`src/lib/components/ui/ToastManager.svelte.ts` /
`ui/Toast.svelte`), per `Memory/feedback_toast_on_save_delete_archive.md`. This is a cross-cutting sweep
across Clients, Requests, Quotes, Pipeline, Collaboration, Team, and the Jafar panel — not owned by any
one existing campaign.

## Status: Not started. Confirmed scope for one area only.

Already confirmed (no toast, direct read, no agent needed): **Clients** has zero toast coverage on every
mutation:

- `src/lib/components/clients/ClientForm.svelte:225` — create/edit client (`saveClient`)
- `src/routes/(app)/clients/[id]/+page.svelte:267` — inline client field save (`saveClient`)
- `src/lib/components/clients/PropertyDialog.svelte:85-86,100` — add/edit/delete property
  (`updateProperty` / `createProperty` / `deleteProperty`)

Everything else is unverified. Two survey attempts this session did not finish: a fork attempt got stuck
in an identity-confusion loop (0 tool calls, treated the coordinator's follow-up as injected content) and
was abandoned; a fresh general-purpose agent survey was killed mid-run for cost, after it had confirmed
two files were read-only and was moving on to Clients' notes/attachments and Team/Jafar areas. Neither
produced a usable report — treat the rest of the app as unsurveyed, not as "probably fine."

Already known to have toasts wired (per earlier grep, not fully re-verified): Settings pages
(`business-profile`, `business-hours`, `branding`), `quotes/[id]/+page.svelte`, `quotes/+page.svelte`,
`OpportunityNotesSection.svelte`, `OpportunityTasksSection.svelte`, `OpportunityOwnerField.svelte`, and
most of the Jafar panel (message-templates, settings, settings/cleanup, and the `*Actions.svelte`
components). Whether coverage is complete *within* those files (every mutation, not just some) still
needs verification — don't assume full coverage from the grep hit alone.

## Exact next action

1. Fix the three confirmed Clients files first (small, already scoped, no more searching needed).
2. Then resume the survey one area at a time (not one giant sweep) to stay within token budget: Requests
   next, then verify Quotes/Pipeline/Jafar's existing toast files are fully wired (not partial), then
   Collaboration shared components (Notes/Tags/Attachments — fixing here fixes every page that mounts
   them), then Team.

## Blockers

None. Purely deferred for cost/time, not waiting on any dependency.

## Protected work

- Do not touch the dirty Quotes worktree.
- Fix shared behavior (Collaboration components) once, in the component — not per page.

## Required pointers

- `Memory/feedback_toast_on_save_delete_archive.md` — the rule and its rationale.
- `src/lib/components/ui/ToastManager.svelte.ts`, `src/lib/components/ui/Toast.svelte` — the shared system.
- `src/lib/clients/api.ts`, `src/lib/requests/api.ts`, `src/lib/quotes/api.ts`, `src/lib/pipeline/api.ts`,
  `src/lib/collaboration/api.ts` — every mutation function to check per area.
