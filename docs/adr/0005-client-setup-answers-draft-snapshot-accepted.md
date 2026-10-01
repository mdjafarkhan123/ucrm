# ADR 0005: Client setup answers live in three layers — draft, submitted snapshot, accepted value

## Status

Accepted 2026-10-01, with client onboarding part B1. Follows the approved
[client onboarding and delivery plan](../client-onboarding-delivery-behavior-contract.md) §2, §3.10, §4 and
§9, and GOV.UK's [Complete multiple tasks](https://design-system.service.gov.uk/patterns/complete-multiple-tasks/)
and [Check answers](https://design-system.service.gov.uk/patterns/check-answers/) patterns.

## Context

The setup wizard is filled in over several sittings and devices, autosaves, and must never treat a
half-typed draft as an attested answer. The contractor later sends it to Uplift, which freezes what was
sent; an edit after that must show as a tracked change. Jafar then accepts or returns sections, and only
accepted values may populate the CRM's real settings. One fact (a business phone, say) is asked once however
many purchased services reuse it, and the package decides which sections appear.

## Decision

1. **Three layers, three tables, never one row doing double duty.**
   - **Draft** — `organization_setup_answers`, one row per organization and fact. Autosave writes here and
     nowhere else. Built in B1.
   - **Submitted snapshot** — an immutable copy of every draft answer taken by Send to Uplift, with the
     confirmation wording version, actor and time. Added by B13. A later draft edit is compared with the
     latest snapshot to show a tracked change; the snapshot itself is never updated.
   - **Accepted value** — Uplift's per-section acceptance, pointing at the snapshot it accepted. Added by
     stage C. Only acceptance copies a value into the CRM's own settings, through that setting's existing
     save command, so setup never becomes a second source of truth for a live setting.
2. **Answers are keyed by fact, not by screen.** `fact_key` (for example `business.public_phone`) is the
   identity. Sections are a presentation grouping, so a shared fact has one row and every branch that needs
   it reads the same one.
3. **The fact list lives in code.** `src/lib/setup/catalogue.ts` names every fact, its section, kind,
   whether it is required, and whether "I don't have this yet" and "I need Uplift's help" apply. The server
   validates each save against it with Zod; the database checks only shape and size. Adding a question is a
   code change, not a migration.
4. **"Don't have it yet" and "need help" are answers, stored without a value.** `availability` is `have`,
   `not_yet` or `need_help`, and a check constraint allows a value only with `have`. Uplift's to-do for a
   help request is read from these rows rather than copied into a second task record, so the request can
   never be marked complete while the fact is still missing.
5. **Autosave is per fact and last-write-wins.** Each field saves on its own once it is valid; an invalid
   value is not saved and the last valid one stays. Two devices editing different fields never collide; on
   the same field the later save wins. No revision check: these are drafts by one or two administrators,
   and a conflict dialog on every keystroke would cost more than it protects.
6. **A section is done when the administrator says so** (GOV.UK task list), recorded in
   `organization_setup_sections`. The task list shows it as done only while every required fact still has
   an answer, so clearing a required answer reopens the section without a second write.
7. **Only owners and administrators read or write setup**, through three commands
   (`save_organization_setup_answers`, `set_organization_setup_section_done`,
   `mark_organization_setup_welcome_seen`). Passwords and provider credentials are never a fact.

## Rejected

- **Writing wizard answers straight into `organization_settings`.** A draft would become a live business
  default before the contractor confirmed it or Uplift accepted it, and "need help" has nowhere to live.
- **One JSON document per organization.** Two devices saving different fields would overwrite each other,
  and the tracked-change comparison would have to diff a blob.
- **A row per section.** Shared facts would be duplicated across sections, which is exactly the
  "asked once" rule the plan forbids breaking.

## Consequences

- B13 must take the snapshot in one command and refuse silent edits to it.
- Stage C must apply accepted values through the existing settings commands and respect their revisions, so
  an unrelated later edit in Settings is not overwritten.
- Organization closure and export (plan §9) must include these three tables and the two that follow.
