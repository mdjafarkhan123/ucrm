# Shared batch 5 — 2026-10-20

Reference: read-only concept.pen board uSXlT and docs/contractor-shared-parts-approved-notes.md. Six shared pickers use indigo lead tiles, weekday, quick dates, indigo hour/minute columns, duration chips, round flag tiles, quiet country/offset chips and safe search emphasis. DateTimePicker composes the updated controls. No persistence, provider, permission or schema changes.

- Focused existing date-time and CountryPicker tests: 21 passed. New CalendarPicker quick-date tests: 2 passed (next business week-start; caller limits/custom validation).
- Focused ESLint passed. SCSS-preprocessed Svelte compile: six components passed, zero warnings. MCP autofixer: no issues after preprocessing; retained existing external-value reset effects needed for Cancel.
- Browser: 1440/390 light/dark, empty/filled/disabled/error, open calendar/time pop-ups, no horizontal overflow. Tomorrow, hour/minute, duration, country/time-zone search/select and Escape passed. Temporary fixture removed.
- Live app: Raad LTD owner, New job; chose Tomorrow, changed start hour, closed Done. live-new-job.png. No record saved or server mutation; no page errors.
- Fixed portal day selectors, centred selected time columns and disabled tiles. No full-project checks or capacity claim.
