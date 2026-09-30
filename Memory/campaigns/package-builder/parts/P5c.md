# P5c — Free access in Jafar's panel; old code removed

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § free access (line "Free access is covered dates without payment")
**Code:** `main`
**Done when:** Jafar can grant, extend, and end free access in the browser; no code refers to the old free-access command or legacy review; `npm run check` passes

## Steps

- [x] Migration `20260930180000_free_access_in_billing_and_legacy_review_retired.sql` written (Riverside resolved to active, `pending_setup` status removed, lifecycle reactivation uses coverage, directory loses legacy review, billing reader adds free access)
- [ ] Apply it to the live database; regenerate types
- [ ] Billing tab: Free access section with grant / extend / end dialogs through `/api/jafar/organizations/[id]/billing`
- [ ] Delete old free-access route + spec, `FreeAccessActions`, Access tab free-access card, legacy-review screens, `organizationLegacyReconciliationSchema`, `freeAccessChangeSchema`
- [ ] Update pgTAP files that use `pending_setup`; `npm run check`, unit tests; browser check

## Next

Apply the migration with `supabase db push --linked` (dry-run first).

## Outside actions

- Live migration 20260930180000 — check: `supabase migration list --linked` shows it, and Riverside Legacy Demo is `active` — pending
