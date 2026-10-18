# C7b — Build Job details to `tNdkX` / `jFBRB`

**Campaign:** contractor-design-concept · **Parent:** `parts/c7-build-pilots.md` · **Approval:** `parts/c4-job-details.md`
**Branch:** `claude/job-details-review` (worktree `.worktrees/job-details-review`, pushed, not on main).
**Live:** `src/routes/(app)/jobs/[id=uuid]/+page.svelte`, `src/lib/components/jobs/*`. Test jobs (Raad LTD):
#20 `698bbe09-…` (visits, labor), #25 `d75b37a8-…`, #29 `b8ca0bfd-…`.
**Done when:** every section matches `tNdkX` side by side at 1440 light and dark, with real data in each section,
then the Pencil tidy-up (`docs/pencil-workflow.md` step 6), merge to main and push.

## Done

- Header, Visits rows, Money divider, Products table, Billing look, Labor/Expenses rows, rail button overflow.
- Products edit mode `jFBRB` (`f72d0951`): inline Discount / Tax / Total panel (`work/PricingAdjustmentsEditor`,
  preview `work/money-preview`), Save bar in the card. Proven live on #25 ($150 → $142.50 → back).
- Visit spec fixed (`91d38661`).

## Jafar 2026-10-18: "we did not implement the details page fully" — fix all next session

Side-by-side of #20 against `tNdkX` found:

1. **Empty states** are big dashed boxes: Instructions, Checklists, Work report, Photos and files. Compact
   drawing `wgrYP` waits for Jafar's yes (Photos and files is not on it yet — add it).
2. **Notes:** live has an open "Write a note…" box; drawing has a "+" in the header and grey note bubbles
   (avatar, name, time). Jafar to choose.
3. **Job total card:** drawing has "$4,142.00 before tax" under the total; check live shows it when tax exists.
4. **Signatures with signed records:** live shows grey cards and a full-width "Collect a new signature"; drawing
   only draws the empty row. Restyle to the concept or draw it for Jafar.
5. **Billing with no schedule:** live shows a full-width "Add a payment schedule" and an extra footnote
   ("Reminders are prompts…") that the drawing lacks — decide with the drawing's rows in mind.
6. **Labor rows:** live money text is larger than the drawing's 13/600; avatars use other colours than the
   drawing's (check the shared avatar colour rule).
7. **Not yet seen with data:** Checklists rows (progress bar, "Required · 3 left" pill, "6 of 9"), payment
   schedule rows (card tile, amount, Paid / Not yet pill), reminder rows, Photos grid with "+1 PDF" tile,
   Work report chips. Find or make test data on a Raad LTD job and compare each one.
8. **Not drawn (left out for data the app lacks):** "Client since 2024 · 3 jobs", "Started Oct 14", Visits
   hint "next today 9:00 AM", "From quote #318".

Also: the pop-ups (none restyled yet), and dark mode for every section above.

## Next

Ask Jafar for the two answers (empty states, Notes) if not given, then work down the list 1–7, screenshot each
section live beside its Pencil node, merge to main and push. Jafar: no long test suites until the campaign ends.
