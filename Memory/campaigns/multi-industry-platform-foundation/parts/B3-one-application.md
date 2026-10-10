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
- [x] `npm run check` clean (package list now carries `experience_keys`, migration `20261126090000`)
- [x] `application-qualification.e2e.ts` passes live at 1440 (needs a 2nd dev server with the spam check off; see Next)
- [ ] Design screen check — form step 1–2 fixed at both widths; status page and Prospects panel at 390 left
- [ ] Commit, push, mark B3 done; B4 next

## Next

Run the journey at phone width and review its screenshots (status page held/no-package, Prospects panel):
start `PUBLIC_TURNSTILE_SITE_KEY= TURNSTILE_SECRET_KEY= npx vite dev --port 5174 --strictPort`, a temporary
`playwright.b3.tmp.config.ts` in the project root with `baseURL: 'http://localhost:5174'` (delete after), then
`PUBLIC_TURNSTILE_SITE_KEY= E2E_WIDTH=390 E2E_SCREENSHOT_DIR=<dir> npx playwright test -c <config>`. The form
allows 5 submissions per 15 minutes from one address. A failed run leaves an open "B3 Test Groomers …"
application: close it with `public.mark_onboarding_application_not_proceeding`.

## Outside actions

- Migrations `20261125090000`, `20261126090000` applied — check: `select version from supabase_migrations.schema_migrations where version in ('20261125090000','20261126090000')` — done

## Notes

- Jafar 2026-10-10: "Something else" skips the package (Uplift recommends one); Medspa shows as "coming soon",
  recording interest only. Clinic questions (treatments, US state, supervisor) arrive with the Medspa build.
- Found and closed: payment could be recorded on an unreviewed application; now refused until confirmed.
- A held application already asked to pay goes back to "new". Decisions allowed until payment is confirmed.
- No-package receipt email is fixed copy in `application-receipt.ts`, not a Jafar-editable template — mention it.
- Existing paid applications have no decision; B4 must cover provisioning them.
