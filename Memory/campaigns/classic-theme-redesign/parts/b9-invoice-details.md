# B9 — Invoice details

**Stage:** Built and verified 2026-10-15 on branch `claude/classic-b9` (worktree `.worktrees/classic-b9`),
reservation `8a9daaf419d4`.

**Agreement:** Approved `classic.pen` frame `dQ7vH` "Invoice details · 1440": main = hero `R0cu77` (status,
"INVOICE #", "From job #N", journey track, four dates + terms pencil), Products and services `zSKYP` (B7),
History `ocC3F` (Payments / Edits tabs), Contract disclaimer `FFtCB`; rail = Balance `YI17d`, Online payment
`GzTk3`, Discount and tax `I8b5g`, Photos and files `sJx40`. No behaviour change needed asking Jafar.

**Built (Classic only; the old look keeps its own branch and shares the editor snippets):**
- `GET /api/invoices/[id]` returns `source` — the job (and its quote and request) from `invoice_sources` on the
  correction chain's root invoice, read as the caller so row security hides what they may not open. Feeds the
  meta "From job #N" and linked Request / Quote #N / Job #N steps.
- Header: journey shows "Due in N days" / "N days overdue" and "$X left"; facts Invoice date, Due ("On
  receipt" when due the day it is dated; a named term otherwise, e.g. "Oct 20 · Net 14"), Sent, Viewed. The
  pencil at the row's end opens Terms and dates in the header. History button scrolls to the History card.
- History RecordCard with Payments (net total chip) and Edits (count) tabs; payment rows link to payments.
- Balance card = `work/ProfitFeatureCard` (new `chip`, `pillIcon`, `muted` part): Balance due, % paid, split,
  Client account balance, Add deposit box. A voided/replaced bill shows $0 and why, no split.
- Online payment RecordCard with the toggle in a soft inset; Photos and files `look="record"`; closure notes
  restyled. Design skill `design-classic/cards.md` updated.

**Proof:** Playwright at 1440 and 1100, light and dark, Raad LTD owner: #11 (past due, job), #23 (progress, paid,
edits), #28 (replaced, deposit), #29 (draft, quote + job). Live journey on draft #29: terms pencil → editor + save
bar (Save disabled) → Cancel; disclaimer staged → Save changes → shown → restored to empty. Collect payment opens
its dialog on #11. Office role sees the page; sales has no invoice access (403, as before). svelte-check: only
the pre-existing dev-preview error. ESLint and Prettier clean on changed files. Vitest invoices/work: 9 passed.

**Known differences left on purpose:** no "Profit · team only" row (invoices carry no cost); Request step says
"Converted" and Job step "Invoiced" instead of dates; the % paid pill wraps under a long figure; at 1100px the rail
stacks under the main column (existing rule).
