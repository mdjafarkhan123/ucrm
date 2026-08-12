# Operations dialog + Prospects detail page — Temporary Work Memory

## Resume instruction

Say `read memory and continue`. Read this file plus the full approved plan at
`C:\Users\Jafar Khan\.claude\plans\refactored-booping-eich.md` (still on disk, not deleted — it has
the full part-by-part detail; this file is the short status tracker). Do the next unchecked
**non-deferred** part only, then update this file and stop. Part C is currently deferred (see its
entry below) — do not start it on a plain `read memory and continue` unless the user has separately
said they want Prospects work resumed.

## Why

While browser-verifying the new `/jafar/operations` screen (part of the separate
`Memory/jafar-complete-roadmap.md` Part 2e task), the user flagged the bottom-of-page detail panel
pattern (used by both Operations and Prospects) as poor UX. Clarified with the user and got explicit
plan approval (via plan mode) for:

- **Operations** → replace the bottom panel with a reusable popup/dialog.
- **Prospects** → replace the bottom panel with its own dedicated page at
  `/jafar/prospects/[prospectId]`, matching how `/jafar/organizations/[organizationId]` already
  works for a similarly data-heavy entity.

Pure UX/structure change — no API, schema, or business-logic changes anywhere.

## Checklist

- [x] **Part A — Build the reusable `Dialog` component.** Filled in the previously-empty
  `src/lib/components/ui/Dialog.svelte` using bits-ui `Dialog` (not `AlertDialog`, which is reserved
  for the existing password-confirm flow in `OwnerReconfirmDialog.svelte`). Props: `open` (one-way,
  controlled — not `$bindable`), `title`, `size?: 'default'|'small'|'large'`, `onClose`, `children`
  snippet for body content, no forced footer. Styled per `.claude/skills/design/modals.md` /
  `src/routes/demo/modal/+page.svelte` tokens (`--elevation-modal`, `--color-overlay`,
  `--radius-base`, `--modal--width`), using `--shadow-high` to match `OwnerReconfirmDialog`'s actual
  production styling rather than the doc's `--shadow-base`. `npm run check`: 0 errors (same 2
  pre-existing dashboard warnings). Not yet used anywhere — next part wires it into Operations.
- [x] **Part B — Operations page: dialog instead of bottom panel.** Edited
  `src/routes/jafar/(protected)/operations/+page.svelte`: replaced the `{#if selectedOperation}`
  bottom `<section class="operations__review">` block with `<Dialog open={Boolean(selectedOperation)}
  title={...} onClose={clearSelection}>`, moved the same inner content (status badge, details `<dl>`,
  last-error line, seen/resolved notes, feedback strip, owner-actions buttons, resolve form) into the
  dialog body, dropped the redundant heading/icon wrapper (dialog header already shows the title, kept
  the status `Badge` directly under it). Removed the table footer's "Close detail" button (dialog's own
  close button replaces it). Removed the now-superseded `.operations__review`,
  `.operations__review-icon`, `.operations__review-content`, `.operations__review-heading`, and the
  now-dead `.operations__quiet-button` (belonged only to the removed footer button) from SCSS, plus
  their references in the two media queries; kept `.operations__review-details` and the other
  inner-content rules. Verified: `npm run check` 0 errors (same 2 pre-existing dashboard CSS warnings),
  `npm run test:unit` 189/189, `npx eslint` on both touched files shows only the pre-existing
  `URLSearchParams` rule already tripped by the identical pattern on the Prospects list page (not
  introduced by this change). **Browser-verified 2026-08-12** by the user directly (not Claude — see
  `[[feedback_self_verify_simple_visuals]]`): dialog opened on row click, closed correctly, "Mark as
  seen" confirmed end-to-end (row moved to `acknowledged`, attributed to the owner's login in
  `platform_operation_attempts`). The leftover test row (`test_manual_verification`) used for this
  check has been deleted from the database. Operations half of Part B is fully done.
- [ ] **Part C — DEFERRED.** New dedicated Prospects detail page. Create
  `src/routes/jafar/(protected)/prospects/[prospectId]/+page.svelte`, mirroring the structural
  pattern of `organizations/[organizationId]/+page.svelte` (breadcrumb, loading/error states via
  `page.params`/`$app/state`/`resolve`), but scaled to Prospects' single query. Move the entire
  current detail-panel body (today's `prospects/+page.svelte` lines ~621-1015), all five mutations,
  their supporting state, and their helper functions from the list page into this new page verbatim
  (see plan file Part C for the exact line ranges and symbol list).
  **Deferred 2026-08-12:** user asked to hold off — the working session had been focused on the
  Operations page (Parts A/B), and Prospects (Parts C/D, and the Prospects half of Part E) is being
  parked rather than continued immediately. Also see `Memory/Deferred-Work.md`. Not blocking; pick
  back up whenever the user raises Prospects again — do not resume it proactively via
  `read memory and continue` without the user confirming they want Part C now.
- [ ] **Part D — Prospects list page: link instead of stateful panel.** Edit
  `src/routes/jafar/(protected)/prospects/+page.svelte`: remove everything moved to the new detail
  page in Part C, remove `selectedProspectId`/selection handlers, add a trailing "open" link cell
  exactly like `organizations/+page.svelte:210-219` (`<a href={resolve(...)}>` +
  `arrowRightIcon`).
- [ ] **Part E — Verify.** `npm run check` (expect 0 new errors), `npm run test:unit` (expect still
  189/189 — no API/route logic changed), `npx eslint` on the four touched/new files. Then guide the
  user through a browser check: Operations dialog open/close/actions still work; Prospects row →
  navigates to its own page → all five actions still work → invalidates the list correctly on
  navigating back.

## Notes for whoever resumes

- The full plan file at `C:\Users\Jafar Khan\.claude\plans\refactored-booping-eich.md` has the
  precise file:line references, exact symbol lists to move, and styling token details — read it
  before starting Part B, don't re-derive from scratch.
- This task is independent of `Memory/jafar-complete-roadmap.md` (the Jafar A-Z mission) — it was
  spun out mid-session from that task's browser-verification step, but touches none of its
  checklist items. Do not conflate progress between the two files.
- No backend/API/migration files are touched by this task at all.
