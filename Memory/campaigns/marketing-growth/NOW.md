# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M4 committed. M5 plan approved 2026-09-23 (plan §3 M5, blueprint §13 window amendment). M5a (delivery truth)
built and committed: migration `20260923160000` live; SES OPEN/CLICK on Raad LTD's config set; unit + live
rolled-back SQL checks pass. Not yet proven with a real inbox (Chrome extension was disconnected).

## Exact next action

Build M5b (attribution) per plan §3 M5: public form reads `?mc=` token (`call-to-action.ts`
`marketingCtaTokenHash`) and stores a tracked credit; staff-declared link; read-time 30-day last-touch window
over Requests and Jobs-without-Request; revenue from real payments. Then M5c UI.

## M5 completion gate (after M5c)

One real campaign to a fresh consented test customer (Greenfield is frequency-blocked until 2026-09-30) with a
form CTA: button carries `?mc=`, open/click times land, reply lands in that customer's conversation tagged with
the campaign, form submit credits it -- all visible on the new campaign page.

## Blockers / open findings (raise with Jafar)

- Both marketing wake cron jobs fail every minute (Vault target URLs unset). Harmless; noisy.
- DLQ alert, warmup-cap starvation, and branded click-tracking domain are M6 gates.
- M9 SMS marketing blocked on Communications A2. Raad LTD Marketing override + allowance expire 2026-09-24.

## Pointers

`docs/marketing-first-release-plan.md` §3 M5. Resume: `continue marketing growth`.
