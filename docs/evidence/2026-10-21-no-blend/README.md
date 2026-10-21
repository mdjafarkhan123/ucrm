# Batch 42 and no-blend shared parts — proof (2026-10-21)

Live app from branch `claude/batch42-no-blend`, 1440 wide, owner login, light and dark. Compared with Pencil
`fJ8Mx` (light `Hk64M`, states `Gk62B`) and the switch board `SnDlF`.

| Screen | Light | Dark | What it shows |
|---|---|---|---|
| New client | `client-new.png` | `client-new-dark.png` | Sand coloured top with white switch tracks, green chosen options, sunken fields with coloured front icons, Configure on stone grey, save bar status |
| New client, exact match | `client-exact.png` | `client-exact-dark.png` | Email box gets the error edge; critical notice strip "… already uses that email address" |
| Edit client | `client-edit.png` | `client-edit-dark.png` | "Edit <name>", no address card, Notes or Attachments; "Editing … · Nothing changed yet" |
| Client page | `client-page.png` | `client-page-dark.png` | Record header top in the new sand; its buttons white; grey buttons on the white part |
| Schedule | `schedule.png` | `schedule-dark.png` | View switch: green chosen option on a grey track (toolbar is on a white card); joined ‹ Today › and Map · Filters stay white |
| Timesheets | `timesheets.png` | | Same switch and joined buttons; Approve on stone grey |
| Request page | `request-page.png` | | Header buttons white on the tint; pencil and Add buttons grey; notes field sunken |
| New request | `request-new.png` | `request-new-dark.png` | Title field white on the tinted top; client picker and Service details sunken on the white card |

Blend check: no part's fill equals what is behind it on these screens — grey buttons and sunken fields on white
cards, white controls on tinted tops.
Computed check: the four front icons resolve to conversation `#118197`, time `#556acb`, invoice `#225c8c`,
client `#8a6a4b`.
