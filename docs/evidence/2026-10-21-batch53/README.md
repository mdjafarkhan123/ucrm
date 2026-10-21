# Batch 53 — New campaign · Customers step, proof (2026-10-21)

Live app from branch `claude/build-batch51` (dev server on port 5190), Chrome, Raad LTD owner login, light and dark.
Compared with Pencil `RPlkr` (main `HMFg8`, states `XTfuS` loading, `S5GsI` counting, `nZMCZ` list open).

| Shot | What it shows |
|---|---|
| `customers-meter-dark.jpg` | Dark: group picked, "Matches customers who" chip, audience meter (2 of 2 will get it), the "Everyone who matches will get it" row, footer hint "2 customers will get this email." |
| `customers-list-light.jpg` | Light, the "Test group" (21 match, 3 will get it, 18 left out): reasons list with warning tiles for the ones the owner can fix, customer list with grey reason pills and "Will get it" |
| `customers-loading-light.jpg` | Light, loading the groups: bones for the picker, chips, meter and the reasons list |
| `customers-counting-light.jpg` | Light, counting after picking a group: meter bones in the Growth tint's edge colour, footer "Counting who will get this email…" |

States forced for the screenshots with a temporary switch in the step (loading, counting, no groups); it was removed
before the commit. The empty state shows the Growth tile and a main New group button. Couldn't-load uses the shared
error state and was not pressed.

Main journey pressed live: Goal → Continue → picked three different groups (counts, chips and the footer followed each
pick), opened and closed View customers, scrolled the list with exclusion pills. Continue to Email works unchanged.

New parts: `marketing/CampaignAudience` (meter, reasons, customer list), `marketing/group-rule-tiles` (the rule colours
the customer group pop-up already used, now shared), `marketing/group-rule-chips` (one short phrase per rule, with a
unit spec). `CustomerGroupPreview` still serves the pop-up, Delivery and Review in its own approved look.

Differences from the drawing: icons use Tabler names; the reasons' tiles are 32 (the drawing's 28 is not a tile size
in the app); the list footer is the shared `ListLoadMore` bar ("All N customers are showing") instead of a centred
Load more button. Not drawn, so chosen in the same pattern: when nobody is left out the head reads "Everyone who
matches will get it"; a group with no matches says so in one quiet line; a group with no rules says it matches every
active customer. Tags are said by their count ("Have the chosen tag") because the label lookup only knows services.
