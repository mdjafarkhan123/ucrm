# Deferred Work

A running log of work the user has explicitly said to skip or postpone (as opposed to work that's
simply not started yet). Each entry records what was deferred, why, and what would need to happen
to pick it back up. Keep entries even after they're resolved — just mark them resolved — so there's
a record of decisions made. Do not act on a deferred item without the user raising it again.

## Open

### Docker / local Supabase for running database tests

- **What:** Local pgTAP database tests (under `supabase/tests/database/`) need `npx supabase test db`,
  which needs Docker Desktop running to spin up a throwaway local Postgres. It is not needed for normal
  development — the app itself talks to the remote Supabase project.
- **Why deferred:** User is using Supabase remote for now and doesn't want to set up Docker just for
  this. Asked on 2026-08-12 whether to (a) skip and do a manual remote check, (b) install Docker, or
  (c) run the test file directly against remote — user chose to defer entirely instead, tracked here
  and in [[Defer-Test]] rather than picking any of the three.
- **Picks back up when:** the user wants to actually run any file in `supabase/tests/database/`, or
  decides to set up local Supabase/Docker for other reasons (the project's own roadmap already plans
  a later move to a VPS with local Supabase in Docker containers, per `CLAUDE.md`).

### Prospects dedicated detail page (Part C of the Operations/Prospects UX task)

- **What:** Building `/jafar/prospects/[prospectId]` as its own page (replacing the bottom detail
  panel on the Prospects list), plus trimming the list page down to a link-out row (Part D) and the
  combined verification pass (Part E) — see `[[operations-prospects-detail-ux]]`.
- **Why deferred:** User asked to defer on 2026-08-12 after the Operations half (Parts A and B —
  reusable `Dialog` component, wired into `/jafar/operations`) was finished; the session had been
  focused on the Operations page specifically.
- **Picks back up when:** the user says they want Prospects detail work resumed. Do not start Part C
  on a plain `read memory and continue` for `operations-prospects-detail-ux.md` until then.

### Live browser verification of the provisioning/setup-password flow (Part 3d of the Jafar roadmap)

- **What:** Clicking "Provision" for real on a prospect sitting in `payment_confirmed`/`needs_attention`
  (creates a real Supabase Auth user, a real organization, and sends a real Brevo setup-link email),
  then completing the password-setup page with that real link. This is the guided browser-verification
  step for Part 3 (atomic provisioning claim, atomic setup-link consume, rate limiting) — see
  `[[jafar-complete-roadmap]]` Part 3d.
- **Why deferred:** Asked the user on 2026-08-12 whether to do it themselves, have it driven via Chrome
  automation, or defer it; user chose to defer entirely and move on to Part 4, the same choice made
  earlier for the Docker DB-test check above.
- **Picks back up when:** the user wants to actually click Provision on a real prospect and walk the
  setup-password flow, or asks for it to be driven via Chrome automation. Not blocking further roadmap
  work — Parts 3a/3b/3c are code-complete and unit-tested; this is the live click-through proof only.

### Live browser verification of the new Settings page (Part 4a of the Jafar roadmap)

- **What:** Opening `/jafar/settings`, confirming it loads with the seeded owner login email as the
  initial alert recipient, changing a value, saving, refreshing, and confirming the change stuck. See
  `[[jafar-complete-roadmap]]` Part 4a.
- **Why deferred:** Not yet asked/done this session — flagged as the user's own step per
  `[[feedback_self_verify_simple_visuals]]`, same as the Operations dialog check.
- **Picks back up when:** the user does the check (or asks for it to be driven via Chrome automation)
  and reports back, or raises Part 4b before this is confirmed -- not blocking either way, since the
  code is unit-tested and `npm run check`/`test:unit` are clean.
