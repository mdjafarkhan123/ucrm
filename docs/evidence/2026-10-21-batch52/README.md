# Batch 52 — record header white top and 15px type scale (2026-10-21)

Checked in the signed-in Chrome on the branch's dev server (`localhost:5181`), window as Jafar uses it
(1874 CSS px wide), beside Pencil board `xrJ3f`:

- Job (Late), Quote (Draft), Invoice (Paid, with the terms pencil), Request (Overdue), Client (Lead, tabs):
  white top, record tile in its colour, large status pill in its own colour, client line 44 avatar / 18 name /
  15 contact, facts one row with 40 tiles at the left, track or tabs at the foot. Nothing cut off.
- Job in dark mode (`data-theme="dark"` set for the check only): parts stand apart from the card, as drawn.
- Not opened: a payment page (same part; it has no track).

Code: `work/WorkRecordHeader.svelte`, `work/RecordFactsList.svelte`, `ui/StatusBadge.svelte` (`large`),
`clients/[id]/+page.svelte` (18 pin), `styles/_variables.scss` (type scale). Svelte autofixer: no new issues.

## Follow-up: Jafar's type-size table (same day)

Jafar replaced the 15px scale with his own table: smaller 12, overline 12, small 14, label 14, base 14, large 16,
larger 20, largest 24, display 28, stat 34 (`_variables.scss`, `typography.md`, Pencil variables).

Checked with Playwright (Chromium, signed in as the contractor owner from `Login.md`) on the branch's dev server at
a **1440 × 900** window, light mode, plus the job page in dark mode (`data-theme="dark"`):

- Computed on the live pages: `--typography--fontSize-base` 14px; record title 28px, client name 16px, fact value
  14px on the job, quote, invoice, request and client pages; no sideways page scroll on Home, Jobs or any of them.
- Found at 1440: the four facts need about 775px but the column gives 722, so labels and values ended in "…"
  on the client and request pages (they had been checked only at a wider window before). Fixed in
  `work/RecordFactsList.svelte`: 12 gap and inset, 10 between tile and text, and only a long value (over 14
  characters) may shrink, the short ones not at all (half a pixel less already produces "…").
- After the fix, text still ending in "…" at 1440: the client line's address (by design, full address on hover) and
  the client page's email value (full text on hover). All labels and other values are whole.
- Pencil `xrJ3f` redrawn with the same spacing; variables match the table.
