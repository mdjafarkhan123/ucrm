# Batch 61 — shared menu and select

Approved Menu B and Select B, Pencil board `bM4k0` (2026-10-22). Built in
`src/lib/components/ui/DropdownMenu.svelte` and `Select.svelte`. The shared
Select also replaces the remaining native `<select>` controls in
`FieldWorkerHome.svelte`, `TeamAccessEditor.svelte`, and `ImportMapStep.svelte`.
Native `<datalist>` text suggestions remain.

Focused Svelte autofixer, Sass/Svelte compilation, ESLint, Prettier and
`git diff --check` passed. Search found no native `<select>` in `src/`.
The browser pass checked the Pipeline select and action menu in light and dark,
desktop and 390px phone; the team role picker; and field-worker customer and
property choices, including clearing the property when customer changes.
No form was saved. Import mapping passed source checks; its live mapping step
was not entered because it requires a file upload.
