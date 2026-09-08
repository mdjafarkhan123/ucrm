# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Parts 1–15e complete. 15f is deferred by Jafar as optional
  (`Memory/deferred/offline-field-records-on-site.md`). **15g complete 2026-09-08**: permissions and
  one-off/recurring journeys passed; the measured Job-history blocker was fixed and verified live. Jafar
  cancelled phone verification, so no phone-readiness claim exists.

## Exact next action

**Scope Part 16 with Jafar and confirm its transferred Schedule/Invoice dependencies are ready before planning
or implementation.** Part 16 is the integrated contractor-journey, recovery, and measured-performance gate.

## Open decisions for Jafar (asked, not yet answered)

- Filling in a checklist writes no history event at all — confirmed, checklists never touch `activity_events`.
  Add the event, or defer?
- Assignee picker searches names only, not email; three near-identical "Jafar" accounts made it error-prone.
- Assignment is job-level by design: one visit on a 26-visit contract exposes the whole job and the customer.
  Jobber behaves the same; Jafar was told and has not objected.
- `CLAUDE.md` Admin password is wrong — the account uses `11223344`, not `111223344`.

## Pointers

- Roadmap: `Memory/campaigns/jobs/ROADMAP.md`. Part 16 is next and still unscoped.
- Round 3 (phone layout) was never run, so **no phone-readiness claim may be made** for the field screens.
- Two findings went to global deferred Memory this session: a Field member reads every request in the
  business (raised to P1), and a full-page-load hydration crash showing the wrong page's content.

Resume command: `read memory and continue the Jobs campaign`.
