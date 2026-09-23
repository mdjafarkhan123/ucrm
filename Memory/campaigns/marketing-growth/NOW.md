# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M4 committed. M5a (delivery truth) committed. M5b (attribution) built this session, not yet committed:
migration `20260923180000_marketing_campaign_attribution.sql` live on the linked project. Adds tracked credit
(public form submit carries `?mc=` through to `process_next_form_submission`, which stores the credit the
moment a Request/Job is created -- the resulting work's own client gets the credit, so a forwarded email still
counts), staff-declared credit (`declare_marketing_campaign_result_credit`, exposed at
`POST /api/marketing/campaigns/[id]/credits`, needs `marketing.draft`), and the read-time 30-day last-touch
window (`marketing_campaign_window_attribution`, called by M5c, never stored). Verified with a live
rolled-back SQL transaction (tracked credit, forwarded-email client, duplicate-declare rejection, window
in/out of range) -- passed, zero residue. `npm run check` and the marketing/forms unit suites pass;
`database.types.ts` regenerated.

## Exact next action

Commit the M5b changes (migration + `src/lib/server/marketing/campaigns.ts` + the new credits route +
`public-forms.schema.ts` + the submit route + the public form page + `database.types.ts`), then build M5c:
Campaign detail Overview/Recipients/Content/Results tabs (blueprint §12), including a way for staff to browse
window-attributed candidates and call the declare endpoint. Capture Jobber's campaign report screens to
`Design/` first per CLAUDE.md rule 5.

## M5 completion gate (after M5c)

One real campaign to a fresh consented test customer (Greenfield is frequency-blocked until 2026-09-30) with a
form CTA: button carries `?mc=`, open/click times land, reply lands in that customer's conversation tagged with
the campaign, form submit credits it -- all visible on the new campaign page.

## Blockers / open findings (raise with Jafar)

- Both marketing wake cron jobs fail every minute (Vault target URLs unset). Harmless; noisy.
- DLQ alert, warmup-cap starvation, and branded click-tracking domain are M6 gates.
- M9 SMS marketing blocked on Communications A2. Raad LTD Marketing override + allowance expire 2026-09-24.

## Pointers

`docs/marketing-first-release-plan.md` §3 M5; `docs/marketing-product-blueprint.md` §12-13. Resume:
`continue marketing growth`.
