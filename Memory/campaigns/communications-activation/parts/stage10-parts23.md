# Stage 10 Parts 2 + 3 — Buy a number, and its paperwork

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Part 2, § Part 3
**Stage:** Building · **Branch / folder:** `claude/stage10-parts23` in `.worktrees/stage10-parts23` (pushed)
**Claim:** `4e0ad188b841` (owner `claude-stage10-opus`) — keep until merged.
**Done when:** a business can buy a texting number from Add number (board `qaFQf`) and send country paperwork
(board `A0URqF`), every state matches its board, then merged to main.

## Part 2 — built 2026-10-22 (not merged)

Migrations `20261222120000`/`…120100` (live); saga `sms-number-purchase.ts`; UI
`components/communications/add-number/*`. Proof: 15 saga tests; live walk, nothing bought. Open: no number prices yet (Jafar to set US local/toll-free); monthly
renewal not built (needs research + Jafar's decision before any live purchase); sweep for orders stuck
"purchasing"; bought/refusal states unscreenshotted (need a real buy).

## Part 3 — server built 2026-10-22, screens half-built (not merged)

- DB (applied live): `20261223090000_sms_number_paperwork.sql` — sets (one per business, country, kind), documents
  (one per Twilio document kind; file = protected setup document, fact key `texting.number_paperwork`), history;
  setup sweep now treats a paperwork file as held; approved paperwork schedules its files for deletion in 90 days.
- Server: `twilio-regulatory.ts`, `sms-number-paperwork.ts` (form from live Regulation, resumable send, fix on the
  same bundle, review sync), `-store.ts`, `-api.ts`; shared rules + fetchers `$lib/communications/number-paperwork.ts`. Purchase now uses approved paperwork
  (`ensureTwilioSubaccount` extracted); Add number skips "paperwork first" for approved kinds.
- API under `/api/settings/communications/sms/paperwork` (list/start, `[id]` get/autosave/delete, send, documents
  upload + complete); signed webhook `/api/webhooks/twilio/number-paperwork`; daily check in
  `trust-hub-status-cron`. Proof: `sms-number-paperwork.spec.ts` (18) passes.
- Live rules: GB business needs only an address (no file); AU one register extract covers three requirements;
  kinds ending `_address` take no file; files PDF/JPG/PNG ≤ 5 MB.
- Dev limit: the file-check cron is off, so an upload stays "Checking" in the live check.

## Next

Build the screens against board `A0URqF` (exported PNGs: re-export with Pencil `Export`), checking each state:
1. Written: `components/communications/paperwork/paperwork-ui.ts` and `PaperworkFlag.svelte`. To write:
2. List page `src/routes/(app)/settings/communications/sms/paperwork/+page.svelte`: breadcrumb, header (40
   conversation `file-check`, New paperwork), list card (needs-fix row first + fix box, head row, foot band),
   side cards How it works + Details we reuse (`reused` from the list API), empty/loading/couldn't-load states.
3. `paperwork/new/+page.svelte`: Country and kind step (CountryPicker without US/CA + kind); `?country&type` starts
   at once (POST start) and replaces the URL with `paperwork/[id]?step=details`.
4. `paperwork/[id]/+page.svelte`: draft → steps form (extend `ImportStepper` with a `steps` prop; reuse
   `SetupStepCard`, the CampaignJourney header with save state + Save draft; autosave PATCH with revision);
   Business details, Documents ("What counts" chips pick the kind; a kind chosen above is "covered"; upload =
   `startPaperworkUpload` → `uploadAttachmentFile` → `finishPaperworkUpload`, poll while checking), Check and
   send (422 problems → form error card), Sent card. Needs fix / under review / approved → opened-set view.
5. Live check 1440 light+dark on Road LTD (Login.md), nothing sent to Twilio; compare with the board; commit;
   then merge Parts 2+3 to main (type check once first, memory rule) and release the claim.

## Questions for Jafar

- The board says "We'll email you" when the phone company decides, but nothing emails the business yet (Twilio
  emails Uplift's address). Copy will say "the answer shows here" unless Jafar wants that email built.
