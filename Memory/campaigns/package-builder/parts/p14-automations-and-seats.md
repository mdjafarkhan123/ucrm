# P14 — Automations and team seats

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Still unclear (safety values) and the allowances line on seats
**Code:** `main`
**Done when:** With 2 active automations allowed, a third cannot be switched on and the reason is shown; inviting past the seat limit is refused; cancelling an invite frees the seat at once; the six safety values are enforced; Automations marked sellable.

## Steps

- [x] Jafar agreed the platform-wide automation safety values (2026-09-30)
- [ ] Migration: set the six values in `platform_automation_safety_limits`
- [ ] Enforce the three unchecked values (longest wait, messages per run, gap between messages) when saving and switching on; give trigger-started runs the 180-day end
- [ ] Verify active-automation limit and seats (invite, cancel, expiry) on a test organization
- [ ] Mark Automations sellable; move the decision into the plan

## Next

Write the migration setting the six values, then extend `src/lib/server/automation/definition.ts` validation.

## Notes

Agreed safety values (Jafar, 2026-09-30, "my suggestion"): 6 conditions per automation, 10 steps, 5 customer messages per run, at least 1 hour between two customer messages, longest single wait 90 days (Jobber's cap), longest run 180 days.
Found: steps and conditions are checked at save; run length only on manual enrolment; wait length, message count, and gap are shown but never checked (the wait step accepts up to 2,160 of any unit).
