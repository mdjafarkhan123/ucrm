# New request — shared top form

**Stage:** Layout approved 2026-10-20 (A · Quiet white); its look was then polished and **approved B ·
Coloured top** with record-number fact tiles (`NhVGQ`, 2026-10-20), which replaces the quiet-white look. **Scope:** Pencil design; full Job/Quote/Invoice
designs follow, with app implementation afterward.
Jafar discarded the previous session's create-page drawings; this approval supersedes C5's Batch 31 drafts.

## Agreement

One shared top form for Request, Quote, Job and Invoice: title first, client picker on the left, each record's
own field on the right. Requested on is read-only; record numbers retain “Given when you save”. Invoice
dates/terms stay in their existing card. Existing form sections and their order remain. Keep the right rail:
New Request has Notes and Attachments there. Clients were discussed as a possibility, not approved for reuse.

## Blueprint and evidence

- `concept.pen`: approved form/light and dark `m4ibfF`, reusable form `OjBZG`, New Request at 1440 `el2At`,
  Quote/Job/Invoice header variants `pM2Vf`. B and its previews were removed after Jafar chose A.
- Look: `.claude/skills/design/layout.md` → Create pages.
- Evidence: `docs/evidence/2026-10-20-new-request-concept/README.md`.
- Live app: visited all four create pages as owner. Request/Quote/Invoice use PrimaryInfoCard; Job has its
  own first card. All share RecordFormLayout and other form parts.
- Jobber: toured New Request live, including the client picker, selected-client menu and assessment. Durable
  observations are in `jobber-02-requests-leads.md` → New Request recheck.

## Saving and next

Branch `codex/new-request-concept` merged into main 2026-10-20 (its `concept.pen` was not taken; the open canvas
already held its boards). The active
Pencil file is `/home/jafar/Ucrm/concept.pen`. Jafar saved the cleaned final design at 20:49 Bangladesh time;
the saved copy is committed here as `ac1ec3fe`. No app code changed. Jafar ended the session and requested
this handover for the next session.

Done 2026-10-20: reusable `OjBZG` rebuilt in the B look, so `m4ibfF`, `pM2Vf` and `el2At` show B; old `zUFDO`,
`TVQzs`, `U8RY1n` deleted. Next: draw the
full New Job, New Quote and New Invoice pages using the approved shared header (`NhVGQ`) and existing approved parts,
preserving each page's sections, sidebar and conditional property behaviour. Review those pages with Jafar.
Client creation needs a separate fit check; it is outside the current approval. App implementation follows
the approved screen designs. Resume: `read memory and continue contractor-design-concept`.

## Batch 32 — whole New job page (Jafar 2026-10-20: "improve the whole job new page, quote new, invoice new")

One page per session: New job first; Quote and Invoice reuse whatever is approved. Drawn, waiting for Jafar's
pick: board `q6Ffc` "Concept · Batch 32 · New job page · A vs B" (light pages `RXUCw` A, `aTFrx` B; dark `z2sHH`,
`uIcN4`). Both: approved B header (`OjBZG`), Jobber order Visits → Billing → Products, every live field kept,
rail kept. A refined cards (team names in the open visit's head, Anytime/Schedule later side by side, deep-green
Job total feature card). B one job sheet (label column left, fields right; Anytime/Schedule later as one
three-way "When" switch; rail = white totals card with job-green band). Section order changed from live
(Products was second): Jafar's KiMYd decision. **Approved A by Jafar 2026-10-20** ("A"); B and its dark copy
deleted; board renamed "… · Approved A". Look in `layout.md` → Create pages. Jafar also approved the live
Products empty-state padding fix (flush New job block), done in `ProductsAndServicesBlock.svelte`.
Next: New quote page, same way (one page per session), then New invoice; build after the drawings.
**Built 2026-10-21** (Jafar asked to build New job before the other drawings): shared form as
`work/CreateFormHeader.svelte`, used by New job only so far; Request, Quote and Invoice still use
`PrimaryInfoCard` inside the old white sheet, so they move to the shared form when their pages move to the
concept frame, then `PrimaryInfoCard` is removed. Job total rail card left as it was (another session is
redesigning the totals card). Proof `docs/evidence/2026-10-21-new-job-page/README.md`.

## Batch 34 — whole New quote page (**approved A by Jafar 2026-10-21**)

Board `OzXHh` "Concept · Batch 34 · New quote page · A vs B" (light `B5DLv` A, `z6BYiM` B; dark `q7Cn1w`,
`raDUx`). ("Batch 33" was taken by another session's Number cards board `fzPaM`.) Both: approved B header in
quote pink, every live field kept (Introduction, Products and services with Add text/heading and Client view,
Client message, Contract disclaimer, 5000 limit), rail = Batch 24 Overview + one Discount and tax card, Notes,
Attachments. A refined cards: optional parts as slim cards marked Optional where they will appear; Client view
row above the subtotal. B one quote sheet: the four parts numbered down a quote-pink line in reading order,
hollow numbers for optional parts, "Client sees" tags, Client view chip in the sheet head. Disclaimer starts
empty (no settings default today). Jafar chose A ("A"); B and its dark copy deleted; board renamed "… · Approved A".
Look in `layout.md` → Create pages. Next: New invoice page, same way (one page per session); build after.

## Batch 35 — shared money summary card (drawn 2026-10-21, waiting for Jafar's pick)

Jafar 2026-10-21: one shared rail card for New job, New quote and New invoice showing revenue, cost and profit
with a bar, like Jobber (Jobber: Total price / Total cost under the lines on New job; Revenue vs Cost bar card
on the job page). Today: New job has the green Job total card, New quote and New invoice the plain Overview card;
neither shows cost or profit although every line carries a unit cost.
Board `UN1hM` "Concept · Batch 35 · Money summary card · A vs B": A `VttVX` green Job total card with a profit
panel (like Job details `tNdkX`); B `Pqiry` new concept, deeper forest green (new Pencil variable
`color-feature-deep` #012a17, not yet in code) with a margin ring and two tiles. States: priced job, quote and
invoice, nothing priced, loss, no cost rights; dark mode `f4UDf`. Jafar asked for his own look, not classic.pen's colours, but bar colours that stand out: cost `color-warning` (amber), profit white on A and `color-success` on B.
Text colours by meaning (Jafar 2026-10-21, "from contractor perspective"): what you keep `color-success`, item cost
`color-warning`, customer pays white, loss `color-feature-alert`; B cards use the dark theme tokens so greens stay
bright on the deep card. B adds a margin status chip (Healthy margin / Below your 35% target / Losing money); the
target comes from the existing quote target-margin setting, so using it on jobs and invoices needs Jafar's yes.
Redraw 2026-10-21 (Jafar: "design like the classic design… use other color with border"): B is now `MSRlv`,
classic.pen's Projected profit layout (profit + margin pill, "On $X of work", one cost/profit bar, legend with
shares) on an ink-blue card. New Pencil variables, not yet in code: `color-money-start` #032b3a,
`color-money-end` #0b4559, `color-money-border` #ffffff2e (edge stays visible in dark mode). `color-feature-deep` is unused now.
