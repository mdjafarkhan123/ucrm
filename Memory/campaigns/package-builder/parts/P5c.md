# P5c — Free access in Jafar's panel; old code removed

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § free access (line "Free access is covered dates without payment")
**Code:** `main`
**Done when:** Jafar can grant, extend, and end free access in the browser; no code refers to the old free-access command or legacy review; `npm run check` passes

## Steps

- [x] Migration `20260930180000_free_access_in_billing_and_legacy_review_retired.sql` written (Riverside resolved to active, `pending_setup` status removed, lifecycle reactivation uses coverage, directory loses legacy review, billing reader adds free access)
- [x] Apply it to the live database; regenerate types
- [x] Billing tab: Free access section with grant / extend / end dialogs through `/api/jafar/organizations/[id]/billing`
- [x] Delete old free-access route + spec, `FreeAccessActions`, Access tab free-access card, legacy-review screens, `organizationLegacyReconciliationSchema`, `freeAccessChangeSchema`
- [x] Update pgTAP files that use `pending_setup`; `npm run check`, unit tests (fresh local rebuild: every package, billing, directory, closure test passes)
- [ ] Browser check: grant, extend, end free access on Riverside Legacy Demo's Billing tab

## Next

Browser check on `/jafar/organizations/7e37a58f-60e4-40ee-bb4a-cf13966a7a3d?tab=billing`: Grant (asks for the password), then Extend, then End. Nothing was granted yet. Then close the part.

## Outside actions

- Live migration 20260930180000 — check: `supabase migration list --linked` shows it, and Riverside Legacy Demo is `active` — done 2026-09-30
