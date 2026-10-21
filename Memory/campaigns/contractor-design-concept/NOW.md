# Contractor design concept — now

- **Goal:** Whole-app redesign: design → review → approve → build.
- **Core agreement:** `docs/contractor-design-concept-behavior-contract.md`.
- **Experience:** `.claude/skills/design/SKILL.md` and its modules.
- **Stage:** Approved parts are being built; further screens are being drawn.

**Create pages:** Shared coloured header approved for Request, Quote, Job and Invoice (`NhVGQ`), existing
rails retained. All four create pages (Request, Quote, Job, Invoice) built on it 2026-10-21, with the Batch 35
money card before save; `PrimaryInfoCard` deleted. Saved job/quote/invoice pages got the card too:
`parts/new-request-top-form.md`.

**Next:**
1. Shared parts: `parts/c5-shared-parts.md`. Batches 1–24, 26–30, 33 and 39 built (25 superseded).
   Batch 35 built on create and saved record pages (2026-10-21). Batches 24, 29, 30, 39 built 2026-10-21. Next: 37, 38, 40. Batches 37
   (customer group), 38 (profile photo, `n2ujB`), 39 (weekly hours, `DhRBV`) approved B; 40 (signature pad, `alWwd`) approved A. Next drawing: empty row in `stages/list-1b-parts.md`;
   List 1a drawn, DataTable skipped. Gaps found 2026-10-21, waiting to be drawn: Field-worker Home
   (`list-2a-daily.md`), Select work pop-up and payment-stage state of New invoice (`list-2b-daily.md`). Older work needs the 12px text sweep.
2. Schedule, event completion and Jobs pop-ups merged; proof `docs/evidence/2026-10-19-schedule/README.md`.
   App fills available width; 1440 is the reference. Migration applied.
3. Jafar confirms checklist order/pop-up marks: `stages/list-index.md`, `parts/c5a-redesign-checklist.md`.

**Pencil:** Preserve active drawing work. Pilot leftovers: `parts/c7-build-pilots.md`.
**Open:** Dark money cards; Changes requested colour; duplicate styling-module sets after rollout.
