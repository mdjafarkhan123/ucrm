# Independent Jobber requests tour

Status: isolated comparison note, not an authoritative product or Jobber reference.
Observed live: 2026-08-18 in the signed-in Jobber trial account.
Safety: read and cancel only. Nothing was saved, sent, converted, completed, archived, or deleted.

## Compared with Claude's reference

Comparison target: `.claude/skills/jobber/jobber-02-requests-leads.md`.

Claude's reference agrees with the independently observed list page, request detail layout, state-dependent
primary action, inline section editing, request actions, staff-created request form, photo limit, optional
assessment panel, three scheduling states, team assignment/reminders, line items, notes, and conversion paths.

## Small deltas to consider later

- Editing an existing on-site assessment shows `Delete`, `Cancel`, and `Save`. The delete action belongs to
  the assessment itself, not the whole request. The official reference describes the edit surface but does
  not currently call out this removal action.
- Adding an assessment to a new staff-created request defaults to `Schedule later` checked. With that state,
  date and time inputs are disabled and `Anytime` is checked but disabled.
- The new assessment inherited the current user as an assigned team member in this account. This may be an
  account/user default rather than a universal Jobber rule, so treat it as observed but unverified.
- A newly added assessment defaulted the team reminder to `No reminder set`; the existing scheduled
  assessment used `24 hours before`.
- Editing request form answers is inline within the Overview section and has its own Cancel/Save controls.
  The observed image question displayed a `6/10` counter and an Upload Images action.
- Request-title editing is also inline and exposes only the title field with local Cancel/Save controls.

## No change proposed yet

Do not promote these notes until they are compared with campaign scope and Claude's conclusions. In
particular, assessment deletion and auto-assignment need an explicit UpliftContractor product decision or
additional confirmation before becoming behavior requirements.
