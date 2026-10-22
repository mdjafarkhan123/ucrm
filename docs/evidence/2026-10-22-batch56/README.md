# Batch 56 — New campaign · Review step (Pencil `qCDG0`, approved B)

Checked live on 2026-10-22 in a side-by-side dev server on port 5311 (Playwright, 1440 wide; Raad LTD owner, the
draft "Batch 54 check", stepped Goal → Customers → Email → Delivery → Review). Nothing was sent or scheduled and no
test email was sent.

- `review-light.png`, `review-dark.png`: Review (Schedule chosen in the dark one): email on the left (Desktop /
  Mobile bar, the pill "Shown with Alex's details", inbox line, the email), launch panel on the right (audience
  meter, "Who, from whom, and where it leads" list box, "When should it send?" radio tiles, informative notice,
  full-width Schedule/Send button, test button), footer with Back and "Nothing sends until you press Send."
- `review-schedule.png`: Schedule for later chosen: Day to send and Time boxes and the business time zone line.

## Changed beside the look

- The column is 1092 on Review as on Email (`CampaignJourney`). `CampaignAudience` has a `meterOnly` option (the
  meter without the left-out list); `CampaignEmailPreview` has a `shownWith` pill text.
- The pill says "Alex's details", not the drawing's "Sarah's": Alex is the sample customer the preview and the test
  email really use.
- The Send button names the count ("Send to 3 customers") or, once a day and time are picked, "Schedule for Tue,
  Oct 28 at 9:00 AM". Until then it reads "Schedule campaign".
- Removed the now-unused `MarketingSenderSummary` and `MarketingAllowanceNotice` (Delivery already draws them inline).

## Not driven live

Staff member view (no When block or test button), sending spinner, couldn't send, test sent / couldn't send a test,
needs-a-fix rows (no sender, no button), loading bones and couldn't load. The office login could not open the draft.

## Send while a part needs a fix

Jafar said (2026-10-22) to follow the drawing: Send/Schedule is disabled while there is no verified sender or no
valid button. `npx vitest run src/lib/components/marketing/CampaignReviewStep.svelte.spec.ts`: 3 of 3 pass (on with
both set, off with no sender, off with no button). Not driven live; the state can't be reached through the steps.
