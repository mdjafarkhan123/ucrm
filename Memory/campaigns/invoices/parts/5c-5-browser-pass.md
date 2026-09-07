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

_(none yet — the pass has not run)_
