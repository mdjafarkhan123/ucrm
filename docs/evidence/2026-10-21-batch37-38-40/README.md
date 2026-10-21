# Batches 37, 38, 40 (built 2026-10-21)

Checked at 1440 on the branch's dev server (port 5181) as the Raad LTD owner, in Chrome.

| Batch | Pencil | Screenshot | What it shows |
| --- | --- | --- | --- |
| 40 Signature pad | `alWwd` A | `signature-draw-job.png` | Job → Collect signature, Draw it with ink: switch with icons (chosen icon in the job colour), Clear with eraser above the paper, × on the signing line, caption, Full name under the paper |
| 38 Profile photo | `n2ujB` B | `photo-your-photo.png` | Settings → Change photo: dark studio, 176 photo with white ring, preview panel (Top bar, Schedule, Inbox), Remove + Choose new photo |
| 37 Customer group | `PLExJ` B | `group-light.png`, `group-dark-name-missing.png` | Marketing → New group: Marketing tile, condition rows with coloured tiles, white chips, green Add and Add a condition…, purple Recipients panel with the counts card; dark mode with "Give this group a name." |

Main journeys on the live app:
- Profile photo: chose a test picture (moving and zooming shown, previews follow the crop, zoom track fills
  green), "Choose a JPG, PNG, or WEBP photo." strip for a text file, dark mode, Save photo (button busy,
  "Profile photo saved.", top bar updated), then Remove (button busy, "Profile photo removed.") — the account is
  back to no photo.
- Signature pad: Type it shows the typed name; Draw it takes ink and wakes Clear. Closed without saving.
- Customer group: Add a condition… menu with each condition's tile; added six conditions, a city chip (Austin)
  and a service chip via search; counts filled in the panel; empty name shows the field error; closed without
  saving.

Shared parts extended: `DropdownMenu` items take an optional `tile` colour; `ErrorState` has `size="small"`
(the panel's couldn't-count card); `CustomerGroupPreview` has `variant="panel"` used only by the pop-up — the
campaign steps keep their current look. New token `--color-photo-studio`.

Known, unchanged from live: while a list condition has nothing picked yet, the count shows "could not be
checked". Not run, by Jafar's rule: type check and lint (once at campaign end).

## Follow-up fix: unfinished conditions (2026-10-21)

Cause: a list condition (city, tags, services, lead source, include / exclude customers) starts with nothing
picked, and the rule check only accepts lists with at least one value, so the whole count was refused ("could
not be checked") and Save would have failed with a vague error.

Fix, following how HubSpot and Klaviyo list builders treat an unfinished filter: `completeGroupRules` leaves
empty conditions out of the count; each empty row shows "Pick at least one, or remove this condition."; Save
stops and turns those hints red (`incompleteGroupConditions`) instead of sending a request that would fail.

Checked live (`group-unfinished-conditions.jpg`): with City and Services still empty the panel counted 1
eligible; Save with a name kept the pop-up open with both hints red; after removing City and picking a service,
Save showed busy, closed the pop-up and the group "Check unfinished conditions" appeared in the list (left in
Raad LTD as test data). `npx vitest run src/lib/marketing/customer-groups.spec.ts` — 11 passed (3 new).
