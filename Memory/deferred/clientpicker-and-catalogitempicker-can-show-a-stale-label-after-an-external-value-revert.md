# ClientPicker and CatalogItemPicker can show a stale label after an external value revert

- **Priority:** P3


- **Campaign:** found during `contractor-settings` Part 1 Layer 4 browser verification, 2026-08-24, while
  fixing the identical defect in `TimezonePicker`/`LocationPicker`.
- **Reason:** bits-ui's `Combobox.Root` `inputValue` prop is not bindable (only `value`/`open` are, per
  `combobox.svelte.d.ts`); once the user picks an option, bits-ui's internal `SelectInputState` box takes
  its own copy of the displayed text and stops re-reading a wrapper's derived `inputValue`. If some caller
  later reverts the bound `value` in place (a form Cancel), the combobox keeps showing the stale label even
  though the underlying value reverted. `TimezonePicker.svelte` and `LocationPicker.svelte` were fixed with
  a targeted `{#key resetKey}` remount that only fires on a genuine external revert (detected by comparing
  incoming `value` against the value the component itself last committed), not on every selection — a naive
  `{#key value}` remounts on every pick too and was proven live to drop DOM focus, breaking Tab to the next
  field for keyboard users.
- **Why left alone:** `ClientPicker.svelte` cannot use the same fix as-is — its `selected` client object is
  only known for ids that appeared in the current search results, so reverting `value` to an id outside that
  set can't resolve a label from local data the way Timezone/Location can from their always-complete lookup
  tables; it would need an id-based fetch first. `CatalogItemPicker.svelte` has the identical defect
  (`inputValue={value}` direct, no revert-safety) but lives inside the dirty, protected Quotes worktree
  (`git status` shows it untracked/WIP) that Contractor Settings work must not touch. Neither component's
  bug is reachable today: `ClientPicker` is only used in `RequestForm` (create-only, Cancel just navigates
  away) and `CatalogItemPicker` only in Quotes' `ProductsAndServicesBlock`.
- **Reactivation trigger:** either component is wired into a form whose Cancel reverts an in-place `value`
  (e.g. Quotes line editing, or a future Request/Quote edit-in-place flow), or the `quotes` campaign resumes
  and can fix `CatalogItemPicker` itself.
- **Prerequisites:** For `ClientPicker`: decide whether an external revert should re-fetch the client by id
  to resolve its display name, or whether the parent must always pass back a resolved object instead of a
  bare id. For `CatalogItemPicker`: the same `lastCommitted`/`resetKey` pattern as `TimezonePicker` applies
  directly once Quotes work resumes.
- **Checkpoint:** `src/lib/components/ui/TimezonePicker.svelte` and `src/lib/components/ui/LocationPicker.svelte`
  (the fixed pattern to copy), `src/lib/components/work/ClientPicker.svelte`,
  `src/lib/components/quotes/CatalogItemPicker.svelte`.

