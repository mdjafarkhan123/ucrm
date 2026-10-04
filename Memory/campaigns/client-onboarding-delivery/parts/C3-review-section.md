# C3a — Review a section, Jafar's side

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 4, § 8; ADR 0005 (accepted layer)
**Code:** `main`
**Done when:** Jafar accepts one section and returns another; both show on the Setup tab and in Activity

## Decisions (Jafar, 2026-10-04, all recommended; model: Content Snare approve / send back with reason)

1. Return = a note plus ticked questions; the client sees those questions highlighted.
2. Ask a question = a support chat with the owner, section attached (reuse `/jafar/support?new=<org>` start chat).
3. Client sees "Accepted by Uplift"; changing an accepted section puts it back for review on the next send.
4. Help requests: "Uplift's to-do"; a section can be accepted with them open; an item closes when Jafar records Uplift's answer (C3c).
5. A return emails owners and admins straight to that section, banner on /setup, reminders restart (C3b).

## Steps

- [ ] Migration: `organization_setup_section_reviews` (one row per section: accepted/returned, the send it judged, note, questions, who/when), `owner_review_setup_section` (newest send only, audit event, a return restarts reminders), `start_support_thread_by_uplift` takes a section
- [ ] `$lib/setup/review.ts` review state per section (accepted stays only while the section's answers match the accepted send) + tests
- [ ] Setup tab view + POST `/api/jafar/organizations/[id]/setup/reviews`
- [ ] Setup tab: badge, Accept, Return dialog, Ask a question link; support start chat carries the section
- [ ] Tests, check, browser check on Raad LTD

## Next

Write the migration.
