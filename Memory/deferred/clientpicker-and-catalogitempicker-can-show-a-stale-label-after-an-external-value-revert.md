# Pickers can retain a stale label after external value revert

- **Priority:** P3
- **Why postponed:** Current callers do not expose the bug; ClientPicker also needs a way to resolve an id outside its current results.
- **Reactivate when:** Either picker enters an in-place form whose Cancel restores an earlier value.
- **Constraint:** Preserve keyboard focus; a remount on every selection is not acceptable.
- **Pointers:** TimezonePicker.svelte and LocationPicker.svelte contain the proven external-revert pattern.
