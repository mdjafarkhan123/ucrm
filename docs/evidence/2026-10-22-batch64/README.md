# Batch 64 · Business profile (Profile at a glance) — built 2026-10-22

Approved design: Pencil `dw4fp` (B). Page: `src/routes/(app)/settings/business-profile/+page.svelte`, parts in
`src/lib/components/settings/profile/`, wording helpers in `src/lib/settings/profile-format.ts` (unit-tested).

Checked live at 1440 on the Raad LTD owner (light and dark) and the finance role.

- `business-profile-owner-light-1440.png`, `business-profile-owner-dark-1440.png`: closed page.
- `open-name-and-trade.png`, `open-time-zone-and-currency.png`, `open-where-you-work.png`: each section open in place.
- `switch-section-dialog.png`: opening a second section while one has changes asks to save or drop.
- `someone-saved-first.png`: another save landed first; red edge, who and when, "See their version" shows what changed.
- `finance-read-only.png`: no Edit buttons, lock notice.
- Main journey: edited the phone in Contact, saved ("Contact saved."), the closed card showed the new number, then put the original back (checked through `/api/settings/business`).

Differences from the drawing:
- **No "Email customers reply to" field.** It needs a new database column and overlaps the Email setup senders; waiting for Jafar.
- The service-area ring and distance chip only show once the address has resolved to a location (the same rule as before); the test business has none yet, so the map shows the pin only.
- "Changed from (604)…" under the phone (sample text in the drawing) is not built.
