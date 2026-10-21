# Contractor design concept — now

- **Goal:** Whole-app redesign: design → review → approve → build.
- **Core agreement:** `docs/contractor-design-concept-behavior-contract.md`.
- **Experience:** `.claude/skills/design/SKILL.md` and its modules.
- **Stage:** Approved parts are being built; further screens are being drawn.

**Next:**
1. **Build:** Batches 43 Merge clients and 44 Collect payment pop-ups built 2026-10-21
   (`docs/evidence/2026-10-21-popups/`). Waiting: Batch 45 Notification bell pop-up `FGYzU` B (`modals.md`; look
   only, plus a kind→tile map and Needs-you pinning). Shared-part history:
   `parts/c5-shared-parts.md`. Create pages: `parts/new-request-top-form.md`.
   **Build next (Jafar 2026-10-21: "make sure next ai session does all this changes on real app"):**
   a. **White buttons and boxes, app-wide:** `ui/Button` secondary, danger, menu and icon kinds white with a 1px
      brand-green edge (danger red), hover/pressed per `buttons.md`; `ui/Input`, `ui/Select`, `Textarea`, money and
      date/time boxes white with the soft grey edge everywhere (`inputs.md`). Shared components only, so every page
      follows; check a few busy screens at 1440 light and dark against Pencil.
   b. **Batch 46 On-site assessment panel A** (`PLgAR`, `layout.md` → On-site assessment panel) in
      `requests/AssessmentBlock`: keep it inside its card on New request (drop the `form` fieldset look), Time-tinted
      head, Anytime/Schedule later side by side, people pick chips (reuse the New job visit panel's parts), saved-request
      actions row, error and team states; End defaults to one hour after Start. Restyle only; behaviour unchanged.
      Prove it live on New request and on a saved request page.
2. **Draw:** next empty row in `stages/list-1b-parts.md` (`layout/MobileNav` is phone-only: check `list-1d-left-out.md`
   first, else `layout/RouteSkeleton`). Gaps: Field-worker Home
   (`list-2a-daily.md`), Select work pop-up and payment-stage New invoice (`list-2b-daily.md`); 12px text sweep.
3. **Jafar decides:** checklist order and pop-up marks
   (`stages/list-index.md`, `parts/c5a-redesign-checklist.md`).

**Pencil:** `concept.pen`; every switch is the `SnDlF` component. Pilot leftovers: `parts/c7-build-pilots.md`.
**Open:** Dark money cards; Changes requested colour; duplicate styling-module sets after rollout.
