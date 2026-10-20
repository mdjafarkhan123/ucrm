# Shared batch 13 — 2026-10-20

Approved boards `eHJn1` (Record page frame: tabs B, save bar A) and `xrJ3f` (Record header · C). One
`work/WorkRecordHeader` now serves all six record pages; `clients/ClientDetailHeader` folded into it and
`work/QuickContactButtons` removed. Coloured top in the record type's surface; four Jobber-based facts per record
(`RecordFactsList`); footer is the tab band (client) or the Request → Paid track (`LifecycleTrack`). Save bar is the
white concept bar with a state dot (`DetailEditBar`); 24 between cards on every record page.

Late approvals added on the branch the same day (`parts/c5-shared-parts.md`):
- 4px status stripe along the card's top in the pill's main colour, clipped by the card's corners.
- Client top uses `--color-client--surface-edge` (taupe 300) so it no longer melts into the page.

Checks: browser screenshots at 1440 light and dark of all six headers (`<record>-1440-<theme>.png`), each compared
with its `xrJ3f` drawing; no page overflow. Stripe seen in blue (Lead), slate (Draft), red (Late), green. No type
check or lint run (Jafar, 2026-10-20). Icon tile hairline edge (board `k4k5Na`) is a separate follow-up.
