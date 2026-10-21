# Batch 39 — Weekly hours (built 2026-10-21)

Pencil: `concept.pen` → `DhRBV` (approved B, Week planner). Checked at 1440 on the branch's dev server as the Raad
LTD owner.

| Screenshot | What it shows |
| --- | --- |
| `hours-light.png`, `hours-dark.png` | Settings → Business hours: Time tile header, hour scale, day tiles, Open / Open 24 hours, 24-hour bar with blocks, Start → End boxes without labels, length chip, red ×, Add another period; a closed day greys its tile and name |
| `setup-light.png`, `setup-dark.png` | The one-column look the setup wizard uses, at 640: switches beside the day, bar and 130 boxes under it. Raad's and B12's setup are accepted (read only), so this was rendered on the Business hours page with `singleColumn` for the screenshot only, not committed |
| `friday-open-saved.png` | Friday after being opened and saved |

Main journey: Business hours, Friday Closed → Open, Save (button busy, "Business hours saved."), then Open →
Closed, Save again — Raad's hours are back as they were.

Unit: `npx vitest run src/lib/settings/weekly-hours.spec.ts` — 7 passed (bar blocks and their labels).
Known difference: secondary buttons (Add another period, ×) look grey in dark mode; that is the shared Button's
dark look, not this part. Not run, by Jafar's rule: type check and lint (once at campaign end).
