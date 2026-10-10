# B3 — One Application

**Campaign:** multi-industry-platform-foundation · **Plan:** `docs/multi-industry-platform-foundation-behavior-contract.md` § Application and qualification
**Code:** `main`
**Done when:** Uplift can hold and explain an unclear case; no payment or provisioning proceeds without a supported decision and compatible offer.

## Steps

- [x] Database: proposal fields, nullable package, Uplift decision history, payment gate (migration `20261125090000_application_qualification`)
- [x] Public form: business first ("What kind of business?" + "What work…"), packages filtered by kind, "Something else"/"Medspa (coming soon)" skip the package; `?type=roofing` link prefill
- [x] Status page + receipt email for held / no-package applications
- [x] Uplift Prospects: "Kind of business" panel, Confirm / Hold form, history; package list filtered by fit
- [x] Unit tests pass (`npx vitest run src/routes/api/get-started src/routes/api/jafar/prospects src/routes/api/jafar/deals`, 127 passed)
- [ ] `npm run check` (not finished before pause)
- [ ] Finish `src/routes/get-started/application-qualification.e2e.ts` and prove the journey live
- [ ] Design screen check (1440 + 390) of form steps 1–4, status page (held/no-package), Prospects panel and forms
- [ ] Commit, push, mark B3 done; B4 next

## Next

Run `npm run check` and fix errors. Then the live proof: start a second dev server with the spam check off —
`PUBLIC_TURNSTILE_SITE_KEY= TURNSTILE_SECRET_KEY= npx vite dev --port 5174 --strictPort` — and a temporary
Playwright config in the project root (a config outside the project cannot load modules) with
`baseURL: 'http://localhost:5174'`, no webServer; delete it afterwards. The e2e stopped at its first step:
`getByRole('combobox', { name: 'What kind of business do you run?' })` was not found — the `Select` names its
trigger differently (check its markup/aria-labelledby). Journey to prove: apply as "Something else" → status page
says a package will be recommended → in `/jafar/prospects?application=<id>` "Mark reviewed" is refused → Hold
with a message → status page shows it → Confirm Contractor · Handyman → Change package → Mark reviewed →
Awaiting payment → close as Not proceeding.

## Outside actions

- Migration applied to remote — check: `select version from supabase_migrations.schema_migrations where version='20261125090000'` — done

## Notes

- Jafar 2026-10-10: "Something else" skips the package (Uplift recommends one); Medspa shows as "coming soon",
  recording interest only. Clinic questions (treatments, US state, supervisor) arrive with the Medspa build.
- Found and closed: payment could be recorded on an unreviewed application; now refused until confirmed.
- A held application already asked to pay goes back to "new". Decisions allowed until payment is confirmed.
- No-package receipt email is fixed copy in `application-receipt.ts`, not a Jafar-editable template — mention it.
- Existing paid applications have no decision; B4 must cover provisioning them.
