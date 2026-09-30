# P8a — Package change rules (database)

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Assignment and changes
**Code:** `main`
**Done when:** the P8a done-check in `stages/3-customers.md`

## Steps

- [x] Migration `supabase/migrations/20261001090000_package_changes_and_exceptions.sql`: cancellable future agreements, charge kind, credit notes, change preview and command, cancel scheduled change, apply credit note, add and end exceptions; every agreement reader skips cancelled ones
- [ ] Push it (`supabase db push --linked`, dry run first), regenerate `src/lib/database.types.ts`
- [x] pgTAP file `supabase/tests/database/package_changes.sql` (43 checks) passes with the migration in a rolled-back rehearsal on the linked database; the ledger, grace, and access tests still pass too
- [ ] Commit, close P8a, start P8b

## Next

Push the migration (step 2): `npx supabase db push --linked`, then `npm run db:types`, `npm run check`.

## Outside actions

- Migration push — check: `supabase migration list --linked` shows `20261001090000` remote — pending

## Notes

Decided with Jafar 2026-09-30 (following Stripe and Chargebee):
- Next renewal (default) = day after paid-through. An already-created next charge at the old price is swapped for the new price if unpaid; refused if money is applied to it. No paid-through (free access, never paid) → only "now", no money change.
- Now, same billing interval: credit for unused days of the charge covering today (today counts as new), charge the new price for the same remaining days, renewal date unchanged; the credit is applied to that new charge in the same confirmed step, leftover stays credit. Paid-through never moves by itself.
- Now, month↔year: **the new period starts today** (Jafar chose this): credit for unused days, full new-interval charge from today, renewal becomes one period from today once coverage is confirmed.
- Smaller edition: refused while seats, active chat widgets, or active automations exceed its limits. If they go over again before a scheduled date, existing items keep working, nothing new can be added, and Jafar's page warns (P8b).
- A scheduled change can be cancelled; its swapped charge is swapped back.
- Exceptions: reason, start, end required; one per feature or limit at a time; planned capabilities refused; ending early keeps the record.
- Catalog `organization_count` counts every org that ever agreed; P8b should show current customers instead.

Rehearsal method: `npx supabase db query --linked -f <file>` with `begin;` + migration + test (each `select is(` rewritten to insert into a temp table) + `rollback;`; pgTAP here does not keep a results table.
