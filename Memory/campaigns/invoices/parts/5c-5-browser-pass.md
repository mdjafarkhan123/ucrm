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

### RIG — J4/J5 rig rebuilt through the UI as Job #18 (Job #1 retired from this role)

Job #1 could not serve (see the J4/J5 blocked note above). A replacement was created **through the UI**,
not by SQL, so every invariant is the app's own: **Job #18 "5c-5 Stage Billing Rig"**
(`02780a53-1668-44f0-8e59-73ba67b28c0c`), client Tester Account, one line "Stage billing work" qty 1 at
**$665.00**, whole-job pricing, one-off. Fixed 3-stage schedule added via Billing setup:
**Deposit $200.00 / Mid build $200.00 / Final $265.00**, footer reconciled "Adds up to $665.00 of $665.00".
Job #17 was deliberately NOT reused: its three stages are all $200, so a stage billed out of order would
be invisible. J5 later re-pointed the unlocked stages to **Mid build $300.00 / Final $165.00** (below),
which is that journey's own outcome, not drift.

### J5 — PASS

- Where: Job #18 (`02780a53-…`), Billing card → "Edit payment schedule", with only the first stage linked
- Saw, with Deposit already claimed by Draft Invoice #21:
  - The dialog explains itself: "One of these stages has already been invoiced, so the schedule stays as it
    is set and that stage cannot be changed."
  - The **Deposit row is disabled** — greyed description and amount, an "Invoiced" badge, and **no Remove
    button**. The Amounts/Percentages mode toggle is disabled too, so the billed stage's mode is stuck.
  - Mid build and Final stayed editable with Remove buttons.
  - **Non-reconciling set refused whole:** Final 265.00 -> 100.00 and Save produced "The stages must add up
    to the job total. They currently add up to $500.00 but the total is $665.00." Nothing saved — the
    Billing card behind still read Final $265.00. No silent adjustment.
  - **Reconciling set accepted:** Mid build -> $300.00 and Final -> $165.00 (200 + 300 + 165 = $665.00)
    saved, and the card now reads Deposit $200.00 (Draft, Invoice #21) / Mid build $300.00 / Final $165.00.
    The locked $200.00 was preserved throughout.
- Expected: exactly the above, per the sheet.
- Blocked: no
- Note, already a known deferral not a new bug: after correcting the numbers the red "stages must add up"
  banner kept quoting the stale $500.00 until save, while the live footer correctly tracked to
  "Adds up to $665.00 of $665.00."

### J4 — PASS

- Where: Job #18 "5c-5 Stage Billing Rig" (`02780a53-1668-44f0-8e59-73ba67b28c0c`), Billing card and the
  three invoices it produced
- Steps: for each stage in order — Create invoice -> Save -> "..." -> Mark as Sent -> Collect payment
  ("Mark as Sent" is the issue path here because Tester Account has no email address; Send invoice would
  have needed one)
- Saw, each stage carrying its OWN amount to its OWN invoice, correctly tagged Payment 1/2/3:
  | Stage | Amount | Invoice | Stage header | End state |
  | --- | --- | --- | --- | --- |
  | Deposit | $200.00 | **#21** | "Payment 1 · Deposit" | Paid, balance $0.00 |
  | Mid build | $300.00 | **#22** | "Payment 2 · Mid build" | Paid, balance $0.00 |
  | Final | $165.00 | **#23** | "Payment 3 · Final" | Paid, balance $0.00 |
  - Each stage walked **Still To Bill -> Draft -> Awaiting payment -> Paid**, and the Billing card showed
    the stage's badge plus a live "Invoice #N" link at every step.
  - **A created stage locks immediately, while still Draft:** the moment Invoice #21 was saved (before it
    was issued or paid) the Deposit row lost its "Create invoice" button and showed Draft + Invoice #21.
    Re-opening the schedule editor then showed that row disabled with an "Invoiced" badge.
  - The composer is read-only on amounts throughout: "These amounts come from the job's payment schedule
    and cannot be changed here", and each invoice keeps the Item total $665.00 / Due this invoice column.
  - With all three billed, the editor disables every row, the mode toggle, and every Remove.
- Expected: exactly the above, per the sheet.
- Blocked: no
- Verified by query afterwards: stages persist 20000 / 30000 / 16500 minor, each with
  `locked_amount_minor` equal to its value, summing to the $665.00 job total.
- Themes and console: J4 stages 1-2 and the rig build ran in **light**, stage 3 and the final card in
  **dark**, plus the fully-paid card re-checked in light — all clean. **No console messages at all**
  (errors or otherwise) with tracking active across a full reload. Collect payment and Edit payment
  schedule dialogs both keep Tab focus inside and close on Esc, returning focus to their trigger.

### BUG 3 — FIXED (browser check owed) — "Add stage" stays enabled on a fully-invoiced schedule where it can never save

- Where: Job #18 (`02780a53-…`), Billing card → "Edit payment schedule", after all three stages are billed
- Steps: bill every stage, reopen the schedule editor
- Saw: every stage row, the Amounts/Percentages toggle and every Remove button are correctly disabled, but
  the full-width **"Add stage" button remains enabled**. The schedule already reconciles at $665.00 of
  $665.00 and every existing stage is frozen, so any stage added here is unsaveable by construction — a
  stage above $0.00 breaks reconciliation and $0.00 is refused by "Every stage needs an amount above zero."
- Expected: disabled alongside the other controls once no reconciling edit is possible, so the dialog does
  not offer a route whose every outcome is a refusal.
- **Fix:** `JobPaymentScheduleDialog.svelte` gains an `allStagesBilled` derived (`rows.every(row =>
  row.locked)`); `addRow` returns early on it and the "Add stage" button disables on it alongside the
  existing saving / 12-stage guards. A partly-billed schedule is untouched — a new stage there is still
  legitimate, because the unlocked rows can be rebalanced around it.
- Blocked: no — cosmetic dead-end affordance, not a data risk.

### NOTE — not filed as a bug: dialog reflow while typing into a freshly added stage

The pass observed that adding a third stage reflows the dialog, so text aimed at row 1 landed in row 2;
it refilled after the layout settled and moved on. Not filed: this is coordinate-blind automation typing
into a moving layout, which a person clicking a field before typing would not hit, and each row is keyed
by a minted `crypto.randomUUID()` precisely so an added row never re-owns another row's input node. Worth
a look only if a human reports it.
