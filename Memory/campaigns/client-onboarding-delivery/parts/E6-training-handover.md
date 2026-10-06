# E6 — Training + handover

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §5–6, §8
**Code:** `main`
**Done when:** A client can arrange or skip training, see the handover page, and receive a durable Live/Delivered record; delivery cannot close without the agreed checks; Jafar's Onboarding list hides delivered clients by default.

## Steps

- [x] Jafar approved all E6 choices on 2026-10-06; plan §6 records them
- [x] Database applied to dev: migration `20261104090000_setup_training_handover` (outcome check: `select version from supabase_migrations.schema_migrations where name = 'setup_training_handover'`); types regenerated
- [x] Server: shared rules `$lib/setup/training.ts` (+spec), `$lib/server/setup/training.ts` (reads, Live/Delivered/booking/cancel emails, recording-withdrawn alert), Zod schemas, tracker states 10–11, list types
- [x] Routes. Client: `/api/setup/training` (GET, POST), `/training/skip`, `/training/consent`, `/api/setup/handover`. Jafar: `/api/jafar/organizations/[id]/setup/handover` (GET, POST), `/handover/live`, `/handover/delivered`, `/training/booking`, `/training/cancel`, `/training/recording`
- [x] Screens: Jafar's `TrainingHandoverPanel` (+ `HandoverPackEditor`) under LaunchApprovalPanel; client `TrainingCard` on Setup (from Ready); `/setup/handover` printable page + Settings card; dashboard SetupCard delivered for 14 days; list "Show delivered" toggle; tracker text. Jafar types the training time in the client's time zone (`wallClockToMoment`)
- [x] svelte-check clean (needs `NODE_OPTIONS=--max-old-space-size=12288`), route specs for both sides; fixed blank values being dropped from three database calls
- [x] Browser-check of what is reachable (2026-10-06): list "Show delivered" toggle works; `/setup/handover` shows its not-ready state; Setup page unchanged, no console errors
- [ ] Full-flow browser check: training card, Jafar's panel, Live → Delivered, handover pack, dashboard card, Settings card

## Next

The full flow needs a client at Ready with an approved preview; Raad LTD is not there yet. Run it during Jafar's hands-on run with A5 (`parts/A5-question-editor.md`), then mark E6 done.

## Notes

Decisions made while building, which Jafar should hear about: once a project is Live, the database refuses a new preview release because later changes go through chat. Live and Delivered cannot be undone. Training details need at least one attendee before Jafar can book. The skip is one-way for the client, who must use chat to undo it. The recording link can be added only after the meeting time has passed. A cancellation emails the attendees.
