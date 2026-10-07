# P5 — Design and build roadmap

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § Approved first release
**Code:** `main`
**Done when:** Jafar approves the build parts, their order, and observable checks

## Steps

- [x] Reuse and risk audit of the current code (findings in Notes)
- [x] Draft build parts, stages, and screen direction
- [ ] Jafar answers the questions below and approves or corrects the parts
- [ ] Write the approved stages into `ROADMAP.md` + `stages/`, record the teammate sign-in ADR, close P5

## Next

Waiting for Jafar's answers to the questions below (the draft list was shown to him in the 2026-10-07 session). After approval: write stages A–E into `stages/*.md`, list them in `ROADMAP.md`, add ADR 0007 for teammate sign-in, point `NOW.md` at A1.

## Notes

Audit findings (2026-10-07):
- `/jafar` knows one person: `requireOwner`/`getOwnerSession` in `src/lib/server/auth/owner.ts`, env-configured, called directly by ~200 API routes. Teammates need one shared access check first — riskiest part (A1).
- Contractor pipeline, tasks and schedule tables are organization-scoped with contractor permissions; Uplift needs its own records. Their screens (`components/pipeline`, `components/schedule`, `settings/SettingsDestinationCard`) are reusable.
- Contractor booking slots live in database functions (`get_form_available_slots`); a pattern, not reusable data.
- Reminders/emails: reuse the once-a-minute worker wake + durable email outbox (`enqueueEmailDelivery`, see `setup/reminder-emails.ts`).
- No Zoom/Meet connection exists; training only stores a pasted link.
- Public package pages exist at `/packages/[slug]` — the Deal's pricing link can point there.

Questions put to Jafar (word for word in the session reply):
1. Order: Recommend you-first (sales journey before teammate logins). OK?
2. Teammates must use a 6-digit code from a phone authenticator app at sign-in. OK?
3. Is any part too big, too small, or in the wrong place?
