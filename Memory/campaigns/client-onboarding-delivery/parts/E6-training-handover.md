# E6 — Training + handover

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §5–6, §8
**Code:** `main`
**Done when:** A client can arrange or skip training, see the handover page, and receive a durable Live/Delivered record; delivery cannot close without the agreed checks; Jafar's Onboarding list hides delivered clients by default.

## Steps

- [x] Jafar approved all E6 choices on 2026-10-06; plan §6 records them
- [x] Database applied to dev: migration `20261104090000_setup_training_handover` (outcome check: `select version from supabase_migrations.schema_migrations where name = 'setup_training_handover'`); types regenerated
- [x] Server: shared rules `$lib/setup/training.ts` (+spec), `$lib/server/setup/training.ts` (reads, Live/Delivered/booking/cancel emails, recording-withdrawn alert), Zod schemas, tracker states 10–11, list types
- [x] Routes. Client: `/api/setup/training` (GET, POST), `/training/skip`, `/training/consent`, `/api/setup/handover`. Jafar: `/api/jafar/organizations/[id]/setup/handover` (GET, POST), `/handover/live`, `/handover/delivered`, `/training/booking`, `/training/cancel`, `/training/recording`
- [ ] Screens: client training card on Setup (from Ready onward; owner-only skip; consent switch); `/setup/handover` printable page (owners/admins, opens once delivered) plus a Settings card; dashboard SetupCard hides 14 days after delivery (`DELIVERED_CARD_DAYS`); Jafar's `TrainingHandoverPanel` under LaunchApprovalPanel in `ClientSetupAnswers.svelte` (Mark as live, booking, recording, summary + guides, blockers, Mark as delivered, history); query keys and `$lib/setup/api.ts` fetchers; Jafar's list "Show delivered (N)" toggle passing `delivered=1`; ProjectTracker text for live/delivered
- [ ] `npx svelte-check` (it ran out of memory this session; `tsc` was clean), then route specs like `launch-checks.spec.ts`
- [ ] Browser-check on Raad LTD, remove test data

## Next

Build the screens, starting with Jafar's panel, then the client training card, handover page, dashboard card, and list toggle. Reuse `OutsideWaits`, `ConfirmDialog`, `SectionBlock`, `TimezonePicker`.

## Notes

Decisions made while building, which Jafar should hear about: once a project is Live, the database refuses a new preview release because later changes go through chat. Live and Delivered cannot be undone. Training details need at least one attendee before Jafar can book. The skip is one-way for the client, who must use chat to undo it. The recording link can be added only after the meeting time has passed. A cancellation emails the attendees.
