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

Next: bring `OjBZG`, `m4ibfF`, `pM2Vf` and `el2At` to the approved B look (ask Jafar first), then draw the
full New Job, New Quote and New Invoice pages using the approved shared header (`NhVGQ`) and existing approved parts,
preserving each page's sections, sidebar and conditional property behaviour. Review those pages with Jafar.
Client creation needs a separate fit check; it is outside the current approval. App implementation follows
the approved screen designs. Resume: `read memory and continue contractor-design-concept`.
