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
1. Shared parts: `parts/c5-shared-parts.md`. Batches 1–24, 26–30, 33, 35 and 37–40 built (25 superseded);
   every approved batch up to 40 is built. Batch 41 follow-up card approved B `jXc9n`, waiting to be built. Batch 42 Client form approved A `fJ8Mx` and the no-blend shared parts (client colour, switch, buttons, fields), waiting to be built: work order `parts/batch42-no-blend-build.md`. Top bar on hold until Jafar decides. Next drawing after it: next empty row in `stages/list-1b-parts.md` (`clients/ClientMergeDialog`);
   List 1a drawn, DataTable skipped. Gaps found 2026-10-21, waiting to be drawn: Field-worker Home
   (`list-2a-daily.md`), Select work pop-up and payment-stage state of New invoice (`list-2b-daily.md`). Older work needs the 12px text sweep.
2. Schedule, event completion and Jobs pop-ups merged; proof `docs/evidence/2026-10-19-schedule/README.md`.
   App fills available width; 1440 is the reference. Migration applied.
3. Jafar confirms checklist order/pop-up marks: `stages/list-index.md`, `parts/c5a-redesign-checklist.md`.

**Pencil:** Preserve active drawing work. Pilot leftovers: `parts/c7-build-pilots.md`.
**Open:** Dark money cards; Changes requested colour; duplicate styling-module sets after rollout.
