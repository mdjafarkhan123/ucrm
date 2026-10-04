# B4 — Services and service area

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-setup-content-blueprint.md` Stage 2
**Code:** `main`
**Done when:** Services, areas, and exclusions save and resume

## Steps

- [x] Stage written as migration `20261013090000_setup_starter_services_stage.sql`; dry run on dev passed all database checks
- [x] Tests in `src/lib/setup/starter-content.spec.ts`
- [ ] Apply the migration to dev (draft only — never publish)
- [ ] Save-and-resume check, then close the part

## Next

Apply migration `20261013090000` to dev, unless the outside-action check shows it already applied.

## Outside actions

- Apply migration to dev — check: `list_migrations` shows version `20261013090000`, and the draft version has stage `services` — pending

## Notes

Departures from the blueprint, for Jafar to confirm: one services list replaces the separate "main service"
box (the first promoted pick is the main service); "Which services are available urgently" is not ordered;
"how far" choice drops "a mix", because the real places are always asked and a distance or travel time is added.
