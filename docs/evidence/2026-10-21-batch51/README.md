# Batch 51 — New campaign · Goal step, proof (2026-10-21)

Live app from branch `claude/build-batch51` (dev server on port 5190), Chrome, Raad LTD owner login, light and dark.
Compared with Pencil `t0L1xo` (light `aIuQ2`, dark `HPwWq`). The browser window did not shrink below its full
width; the page is one fixed 760 column, so the column matches the drawing at any width.

| Shot | What it shows |
|---|---|
| `goal-step-light.jpg` | Breadcrumb (Campaigns › the campaign's name), Growth megaphone tile, "Unsaved changes" with Save draft (white), step track with Goal current, goal tiles two to a row with the first one chosen, name field, footer bar with Continue |
| `goal-step-dark.jpg` | Same screen in dark |

Main journey pressed on the live app: chose a goal, typed a name (the breadcrumb and heading followed it and the
save state went to "Unsaved changes"), pressed Continue to Customers, picked a group, Continue to Email, Continue to
Delivery, then Back to Goal with the goal and name kept. The finished steps show a check tile and a green line.
Save draft was not pressed, so no draft was left in the test business; its save code is unchanged.

Changes: `marketing/CampaignJourney` (breadcrumb replaces Back to campaigns, header tile, save state with an icon,
Save draft white with a save icon, one 760 column), `CampaignStepper` (stacked step track with icons),
`CampaignGoalStep` (icon goal tiles, name field, footer bar). The import wizards' step card moved to
`layout/SetupStepCard` so the campaign steps and the imports share it.

Differences from the drawing: icons use Tabler names (`speakerphone` for megaphone, `rotate`, `list-check`,
`device-floppy`). Continue keeps its arrow after the word, as on the import steps. The Customers, Email, Delivery
and Review cards still have their old look inside the new frame until their own drawings (Batch 53 onward).
