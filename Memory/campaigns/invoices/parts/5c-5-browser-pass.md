# 5c-5 browser pass — find only, do not fix

Approved checklist: `docs/invoice-part-5c-plan.md` line 81. Do not re-derive it.

## Rules for this session

1. **Fix nothing.** Not even a one-line obvious bug. Record it and move on.
2. **A blocked journey is recorded, then skipped.** Do not work around a broken screen; start the next
   journey. Journeys are independent by design.
3. **Change no test data beyond what a journey's own steps require.**
4. Check every journey in **light and dark**, watch for **console errors**, and in any dialog confirm
   Tab/Shift-Tab stay inside it and Esc closes it.
5. The app is slow over the tunnel: allow ~4 s before a screenshot, 8–12 s on a job-detail cold load.

## Already proven by query — do NOT re-test these in the browser

The database math is verified. The browser pass only checks that the **screen shows these numbers**.

| Fact | Verified value |
| --- | --- |
| Job #1 fixed schedule reconciles | $200.00 + $200.00 + $265.00 = $665.00 job total |
| Job #13 percentage schedule | $66.66 / $66.66 / $66.68 = $200.00 — **divides evenly, no residual** |
| Job #14 stages | $500.00 + $376.65 = $876.65 job total; both locked |
| Invoice #18 | total $500.00, 4 lines summing $500.00, deposit applied $400.00, **balance $100.00** |
| Invoice #19 | total $376.65, 4 lines summing $376.65, no deposit |
| Both #18/#19 | `progress_original_amount_minor` retains the full $876.65 job value |

## Journeys

**J1 — Direct fixed schedule.** Job **#17 "5c-5 Fixed Schedule Rig"** (`ed14da3e-…`), total **$600.00**,
no schedule yet. Add a fixed 3-stage schedule through Billing setup: $200 / $200 / $200.
Expect: saves, three stages show Remaining. Then try to save $200 / $200 / $150 —
expect the **whole save refused** (fixed must reconcile exactly), not a silent adjustment.

**J2 — Percentage schedule, residual cents.** Job **#15 "5c-5 Residual Cents Rig"** (`64b313b8-…`),
total **$100.01**, no schedule. Add percentage stages 33.33 / 33.33 / 33.34.
Expect exactly: **$33.33 / $33.33 / $33.35** — the spare cent lands on the LAST stage (largest remainder).

**J2b — Tie broken by position.** Job **#16 "5c-5 Tie-Break Rig"** (`45437d90-…`), total **$100.01**,
no schedule. Add percentage stages 50 / 50.
Expect exactly: **$50.01 / $50.00** — the spare cent lands on the FIRST stage (tie → earlier position).

**J3 — Quote-carried funded deposit (render only).** Job **#14 "Panel upgrade quote"** (`1ef8947f-…`)
and its **Invoice #18**. Expect the Job Billing card to show the carried 2 stages with the deposit stage
marked, both locked; and Invoice #18 to read **total $500.00, $400.00 applied, $100.00 due**.
The conversion command itself is already covered by pgTAP — do not rebuild a quote to test it.

**J4 — Create / open / pay each stage.** Job **#1 "Testing job"** (`fd9e7a6d-…`), fixed
$200 / $200 / $265, nothing linked yet. For each stage in order: create its invoice, open it, record a
payment. Expect the stage to move Remaining → Draft → Awaiting payment → Paid, the invoice number and
total to show on the Job Billing card, and a created stage to become **locked, including while Draft**.

**J5 — Edit remaining stages after one is linked.** Continue on Job #1 after J4's first stage only.
Expect: the linked stage is not editable; the two unlinked stages can be edited or reordered **only if
the whole schedule still adds up to $665.00 with the locked $200.00 preserved**; a set that does not
reconcile is refused whole.

**J6 — Correction refusal / preview.** Invoice **#5 "D2 refusal test"** carries the state.
Expect the refusal to be explained on screen rather than a raw error. **Known limit:** there is no
correction UI (see NOW.md deferrals), so if the entry point does not exist, record that as the finding
and stop — it is not a bug to hunt for.

**J7 — Customised visit quantities. CLOSED.** Covered by the 5c-5c pass and its three fixes
(`863a96c`, `7aaa5f3`, `83fd891`). Do not repeat.

**J8 — Fixed-period non-regression.** Job **#2 "Recurring Lawn Care Test"** is `fixed_per_period`.
Expect **no per-visit pricing section** anywhere on its visits, and its billing to use the job's lines.

## How to record a bug

Append to `## Findings` below. One block each, nothing else:

```
### BUG n — one line saying what is wrong
- Where: job/invoice number + id, and the screen
- Steps: the shortest click path that shows it
- Saw: what was on screen (a number, a message, nothing at all)
- Expected: the number or behavior from this sheet
- Blocked: yes/no — did it stop the rest of that journey
```

## Findings

### BUG 1 — FIXED + BROWSER-VERIFIED — Payment-schedule dialog's live percentage preview misrounds and understates the total before save
- Where: Job #15 "5c-5 Residual Cents Rig" (`64b313b8-77ae-476b-94be-2f84ce76a150`), Add a payment schedule dialog, Percentages mode
- Steps: Add a payment schedule → Percentages → enter 33.33 / 33.33 / 33.34 into the three stages
- Saw: Row amounts shown live as $33.33 / $33.33 / $33.34, with the footer reading "Adds up to $100.00 of $100.01" — one cent short, looking unreconciled
- Expected: The live preview should show the same largest-remainder rounding the backend actually applies ($33.33 / $33.33 / $33.35, adding to $100.01) so the on-screen total matches the job total before the user commits
- **Verified 2026-09-07 in the browser, both themes, no console errors:** Job #15 previews
  $33.33 / $33.33 / $33.35 with "Adds up to $100.01 of $100.01"; Job #16 previews $50.01 / $50.00 with
  the spare cent on the FIRST stage; retyping 60/40 live-updates to $60.01 / $40.00. Fixed mode
  non-regression on Job #17: $200 x3 reconciles, and 200/200/150 is still refused whole with "The stages
  must add up to the job total..." — nothing silently adjusted. Esc closes and restores focus to the
  trigger; Tab/Shift-Tab wrap inside the dialog. No stage data was saved by the verification pass.
- **Fix:** `JobPaymentScheduleDialog.svelte` now prices percentage stages as a set in a `rowAmounts`
  `$derived.by`, mirroring `private.price_job_payment_schedule`: floor every share, then hand the leftover
  cents out one apiece by largest fractional part, ties to the earlier stage. `plannedTotal` sums that
  array and each row renders `rowAmounts[index]`. A locked stage is no longer held out of the spread,
  because the server prices it through the same pass and refuses the save if the result stops matching
  what it was billed at — so the dead `lockedAmountMinor` draft field is gone.
- Blocked: no — clicking Save schedule anyway persisted the correct $33.33 / $33.33 / $33.35 split (confirmed on the saved Job Billing card), so this is a display-only miscalculation in the dialog, not a data bug. A user watching the dialog would reasonably believe the split is invalid and not attempt to save.
- Also reproduces in the other direction: Job #16 "5c-5 Tie-Break Rig" (`45437d90-f6dc-4c06-8828-c8b7cc1a311c`), same dialog, 50/50 percentage split on $100.01 previewed as $50.01 + $50.01 = "Adds up to $100.02 of $100.01" (over, this time), but saved correctly as $50.01 / $50.00. Each row is independently rounded in the live preview instead of using the same largest-remainder/tie-break allocation the backend applies across the whole set.

### BUG 2 — NOT A BUG — the "red square" is a real line photo, rendering correctly
- Where: Job #14 "Panel upgrade quote" (`1ef8947f-55e2-44ae-8397-3de4e53e1e50`), Products and services card, "Custom haul-away fee" row
- Steps: Open Job #14 and look at the Products and services table
- Saw: A solid red square (~40x40px) sits in the blank space of the "Custom haul-away fee" row, between the line-item name and the Quantity column. It has no accessible-tree representation and no text (get_page_text shows a blank line there) — it's a pure CSS/paint artifact. It scrolls with the page content (confirmed by scrolling and re-screenshotting), so it's part of the row, not a cursor or screenshot-tool overlay. Confirmed in both light and dark mode.
- Expected: No red block — this line item should render like the other three rows
- **Verdict: not a defect, no fix made.** That line genuinely carries a photo. `job_line_items` →
  `attachments` for this job returns `line-photo-test.png`, `image/png`, **178 bytes**, uploaded
  2026-08-20 — a deliberately tiny solid-colour test PNG. The read-only table renders it at
  `ProductsAndServicesBlock.svelte:1279` in the `pricing-table__photo` column, which sits exactly
  between the name and Quantity, as `<img alt="">` — decorative by design, which is precisely why it has
  no accessible-tree entry and no text. The pass read that absence as a paint artifact; it is the photo
  feature working. The other three lines have `image_attachment_id` null, so only this row shows one.
- Blocked: no

### J4/J5 BLOCKED — Job #1's live state does not match the tick sheet; not a UI bug
- Where: Job #1 "Testing job" (`fd9e7a6d-393f-46a5-bc11-1c6d6cb20e99`)
- Steps: Opened Job #1 to run J4 (create/open/pay each fixed stage)
- Saw: Job #1's real total is **$66,500.00** (1900 x Solar Panel @ $35.00), not the $665.00 ($200/$200/$265) the tick sheet and NOW.md describe. It already carries a 3-stage schedule (Deposit $20,000 / Mid build $20,000 / Final $26,500, all "Still To Bill", none linked) — and separately, **Invoice #6 "Testing job"** already bills the whole job for $66,500.00 (status Past due, balance $66,500.00, created Sep 6 2026, predates the schedule). Clicking "Create invoice" on the Deposit stage and saving correctly surfaced "This whole job has already been billed on another invoice" and refused the save — that refusal itself looks like correct behavior (can't double-bill a job that already has a whole-job invoice), it just means this job can't run the J4 rig as written.
- Expected: Per the tick sheet, Job #1 should have been a clean $665.00 fixed schedule with nothing linked, ready for the create/open/pay walkthrough.
- Blocked: yes, for both J4 and J5 (J5 continues from J4's first linked stage). This is a test-data/Memory drift issue, not a screen defect — Memory needs correcting or a fresh rig job needs seeding before J4/J5 can be run for real.

### J6 — confirmed known limit, not a bug
- Where: Invoice #5 "D2 refusal test" (`ba443ebb-93b2-488e-b945-5300fc702dd4`), Past due, balance $39,000.00 of $50,000.00
- Steps: Opened the invoice, checked its "..." action menu (Resend invoice, Copy customer link, Preview as client, Print or save PDF, Mark as received, Write off balance, Void invoice) and the Products and services card (no pencil/edit icon, unlike a Job's card)
- Saw: No Edit/Correct entry point anywhere on the page. "Write off balance" opens a real, working dialog (bad-debt write-off, unrelated to correction) — cancelled without submitting.
- Expected per NOW.md's known limit: there is no correction UI, so the entry point's absence itself is the expected finding, not a bug to chase further.
- Blocked: no further action needed — journey complete as a confirmation.
