# A2 — Settings pages (Pencil design)

**Branch/worktree:** `claude/settings-design`, `.worktrees/settings-design`. **Claim:** `66c9c2154e67`. **State:** Designing in Pencil.

Pencil (`classic.pen`) has only Settings Home `hBrzM` and Business profile `Q0Khrn`. The other 17 pages fall into three kinds, so one example of each is drawn first for Jafar's yes, then the rest follow the approved pattern (Jafar, 2026-10-16: agents may draw in parallel, lead reviews against his taste).

- **Forms:** Business hours (example), Taxes, Quotes, Invoices, Payments, Branding, Security.
- **Lists:** Team (example), Price book, Checklists, Forms, Pipeline, Automation.
- **Switches:** Alerts (example), Inquiry alerts, Communications, Contact matching.

**Examples on the canvas (row y=0):** Business hours x=6160, Team x=7700, Alerts x=9240. Each copies Business profile's shell and header; look only, the live page's controls and wording.

**Drawn and reviewed (2026-10-16):** Business hours `W0Nff`, Team `STRSU`, Alerts `n87Rqu`. Lead review fixed Business hours: closed day shrinks to its heading row (code: `align-items: start` on the `WeeklyHoursEditor` grid) and the "Last changed" chip is hidden (owners never see it live). Look choices for the build: Team avatars drawn neutral (live `Avatar` colours each person), seat bar under "8 of 10 seats used", search/filter in the table card header like Clients; Alerts in two columns keeping group order, no save bar (saves per switch).

**Icons colourised (Jafar, 2026-10-16):** section/group icon tiles carry their meaning — Alerts groups use record colours (Schedule/Time clock job, Messages informative, Sales quote, Money invoice, Team task, Reviews warning); Team page and seat tiles use Team & access `$color-quote`; seat bar wine = active, yellow = invited; "Open" day label green.

**Approved by Jafar 2026-10-16 ("approved"):** Business hours `W0Nff`, Team `STRSU`, Alerts `n87Rqu` as the pattern for forms, lists and switch pages, with the lead's recommendations: Owner badge dark (`$color-surface-reverse`, white text), avatars one neutral grey, Business hours hint reworded at build to match the editor (no per-day appointment option).

**Batch 2 (drawn 2026-10-17, lead-reviewed, waiting for Jafar's yes):** the other 20 top-level pages at row y=0 from x=10780, 1540 apart: Branding, Taxes, Payments, Quote settings, Invoice settings, Contact matching, Pipeline, Price book, Checklists, Request forms, Automation, Email, SMS, Website chat, Balance, Blocked addresses, Inquiry alerts, Snippets, Templates, Security. Later batch: sub-pages (automation `[id]`/new, forms `[id]`, invoices opening-balances, price-book import, team activity and `[userId]`).

Batch 2 frame ids: Branding `IXWFn`, Taxes `o1A1w`, Payments `NnzgL`, Quote settings `v8iq7i`, Invoice settings `KO472`, Contact matching `XqHYz`, Pipeline `Q25PS`, Price book `j1chB1`, Checklists `YZ8Wg`, Request forms `Wr392`, Automation `n0kJri`, Email identity `QEixl`, Phone & SMS `C70C3`, Website chat `fAAvd`, Communication balance `FQtlx`, Blocked addresses `K20fhu`, Inquiry alerts `UnRB9`, Snippets `M5vL5`, Templates `X6iCs`, Password and security `eoVYJ`. Committed in `classic.pen` on main (7aa969b8). Short frames raised to 1024 so the sidebar fits.

**Open for Jafar:** "Draft" pill is amber on Request forms but blue on Automation (pick one); "Back to settings" button on Communications pages repeats the breadcrumb (keep or drop); Automation strip meter bar is new (keep or sentence only); Pipeline Lost reasons in a right column; password fields side by side (live stacks them).
