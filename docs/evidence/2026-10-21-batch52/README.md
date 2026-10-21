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
