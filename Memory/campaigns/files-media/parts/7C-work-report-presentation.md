# 7C — Work Report presentation (approved by Jafar 2026-09-24)

Industry method: Housecall Pro Photo Reports (typed sections, drag order) + CompanyCam before/after pairs,
built as a report item, not a composite image. Research: `docs/research/work-report-photo-presentation-2026-09-24.md`.

## Approved behavior

- Optional **sections**: heading + optional note. Photos may sit above the first heading. No sections = today's look.
- **Starting layout**: only when a report has no photos chosen yet, pre-sort into Before / During / After /
  Damage sections from labels (first matching label in that order), unlabelled into "Other". Labels never
  reorder anything afterwards. Existing reports keep their photos as one unsectioned list, same order as today.
- **Ordering**: photos, pairs and sections move by drag and by up/down buttons. Newly ticked photos go to the end.
- **Before/after pair**: one report item of two photos; "Before" left / "After" right labels always shown,
  each photo's own caption below; sides swappable; stacks Before-on-top on phones. A photo appears at most
  once in a report (alone or in one pair); making a pair moves both photos to the pair's spot.
- **Customer layout**: one fixed layout — large photos with captions, 2 across desktop, 1 on phone; no slider,
  no grid option. Preview as client and Print render the same document.
- **After sending**: issued links stay frozen (order, sections, pairs, captions, labels). When the editable
  report differs from the live link, the job page shows a notice with "Copy updated link", which issues a
  new link and revokes the old one (existing rotate behavior); copy says the old link stops working.
- **Who**: same permission as editing a work report today.

## Acceptance checks

- Old issued links render exactly as before; pre-7C reports unchanged in editor and customer view.
- Trash/Restore of a sectioned or paired photo keeps the "Photo removed" gap in its place.
- Browser: arrange by drag and buttons, pair + swap, preview, copy link, edit → notice → copy updated link.

## Open (engineering, not product)

- Schema shape for sections/pairs/order; how "differs from live link" is detected.
