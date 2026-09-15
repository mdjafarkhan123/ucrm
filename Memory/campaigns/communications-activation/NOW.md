# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 9 (Twilio Trust Hub ISV registration): 9A (ledger), 9B (Standard-path saga), and the Sole Proprietor path
are all DONE 2026-09-15 (unit-tested against mocks; UNCOMMITTED). Full detail: ROADMAP.md's "Stage 9" section.

**Hard constraint, confirmed live in Twilio Console:** neither the platform (UCRM's own Twilio account) nor any
contractor has a real registered business yet. This blocks live proof for both the Standard and Sole Proprietor
paths, Stage 9C, and Stage 8 — build and unit-test with mocked responses only, never spend real money firing
placeholder data at Twilio's live API.

**Business-registration thread blocked 2026-09-15 (confirmed via Twilio docs, not guessed):** Jafar is in
Bangladesh with only a website and his personal National ID. Twilio's Sole Proprietor brand tier is US/Canada-
resident only, so it does not help him — he still needs a real registered legal entity + business
registration/tax number before either path can go live. Did not touch the Twilio Console wizard this session.
Live-send testing (Virtual Phone simulator, or a real text to Jafar's own phone) was offered and declined by
Jafar 2026-09-15 — don't re-offer unless he raises it.

## Exact next action

Independent threads; Jafar picks which to resume:

1. Adapter-level spec for `twilio-trust-hub.ts` (exact HTTP method/path/param checks, mirroring
   `twilio-sms-submit.spec.ts`) + a clean full-project `svelte-check` run (last one OOM'd on this machine).
2. Stage 9C (Campaign registration + status sync onto `communication_sms_registrations.status`) — depends on
   9B/Sole Proprietor (both done), dependency-ready.
3. Business registration (blocked on Jafar's paperwork, see above).

Stage 8 (billing reconciliation, recovery and launch proof) stays deferred behind Stage 9's live-proof
prerequisite; its non-blocked pieces (price reconciliation logic, 200-tenant load test) can start in parallel.

## Constraint

A2P 10DLC cannot be completed for Jafar's test org, or for the platform's own ISV profile, until a real
registered business exists for either. Provider-owned actions and any real registration fee stay Jafar's
explicit call.

Resume: `read memory and continue — communications-activation`.
