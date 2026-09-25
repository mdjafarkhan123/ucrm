# Operational Email on SES Roadmap

Approved behavior: `docs/contractor-email-contract.md` (incl. 2026-09-23 cutover amendment). Architecture:
`docs/research/amazon-ses-contractor-email-inbound-architecture-2026-09-19.md`.

## Goal

Move contractor operational email (domain setup, sending, delivery events, customer replies) from Brevo to
Amazon SES with an easy owner/contractor workflow. Allowances, warm-up, reputation, suppressions and senders
already exist provider-neutrally; this is a provider swap plus the setup UI, not a rebuild.

## Start rule

No coding until the marketing-growth agent has committed its current SES work (`dns-reconcile.ts`, the
marketing-domain route, `CommunicationsWorkspace.svelte`, `email-domain-activation.ts` edits). Then build in a
separate git worktree on its own branch (started 2026-09-24: `../Ucrm-email-ses`, branch `operational-email-ses`); merge the shared `ses.ts`/`ses-env.ts` overlap at the end.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Research check + screen designs | Done 2026-09-24 (`e786e40`; designs in contract "Email setup screens") | Start rule | Jobber/GHL setup screens reviewed; Jafar approves designs for the owner Email card and contractor Settings → Email request flow |
| 2a | Operational domain setup on SES (backend) | Done 2026-09-25 (`174a8ec` + DKIM key-length fix); Raad live: mail.test verified on SES, MAIL FROM + reply identity passing, only 8 records added | 1 | Owner Set up creates mail + reply SES identities, bounce.mail MAIL FROM, `ucrm-operational-<org>` config set in the org tenant via Cloudflare; Check/Remove handle SES rows; reply MX + receiving row deliberately untouched until Part 4; Raad re-activated and verified live |
| 2b | Owner Email card UI | Done 2026-09-25 (`e831175`) | 2a | Approved "Email setup screens" owner card (one Email card, Everyday + Marketing rows, one status + one action each) replaces EmailDomainActions/MarketingDomainActions; browser-verified |
| 3 | Outbound sending + delivery events on SES | Done 2026-09-25 (`7de601a`, migration `20260925130000` live) | 2a | Email worker sends via SES with config set and opaque Reply-To; delivery/bounce/complaint update projection and suppressions; live send proven -- created a real SES-backed sender through the Settings UI on Raad LTD, assigned it to a staff member, sent a real reply, watched it land Delivered from a live SES event |
| 4 | Customer replies on SES | Built; folded into Set up by Part 6 step 1 (`48b50bb`); live proof pending Part 6 step 5 | 3 | Set up alone makes reply.<root> receive on SES; reply, duplicate, oversized attachment, expired alias, auto-response, recovery proven live; a reply to a Marketing campaign email lands in the right Conversation with Campaign origin (marketing M5 recheck) |
| 5 | Contractor request-setup flow | Planned | 2b | Request email setup in Settings → Email, Needs attention item for Jafar, send-refusal links there (absorbs old P3 deferral) ; browser-verified |
| 6 | Contractor-side Brevo removal (Jafar 2026-09-25: zero Brevo on the contractor side; platform/Jafar Brevo kept) | In progress — approved 2026-09-25; steps 1–3 done (`9ecef26`); step 4 waits on Jafar allowing Brevo deletes (see NOW.md) | 4 | Steps: (1) replies folded into Set up, today's switch button/code removed; (2) contractor Brevo code, `webhooks/brevo/inbound` + `transactional`, Replace-domain, contractor Brevo env keys removed; (3) contractor email tables SES-only, Raad's Brevo test rows deleted; (4) Raad's Brevo domain + inbound webhook deleted via Brevo API (account + `BREVO_API_KEY` kept); (5) fresh Set up on Raad, live send + reply acceptance with Jafar. Kept on Brevo: `src/lib/server/email/brevo.ts` + `events/dispatcher.ts` users (Jafar emails, setup links, team invites, inquiry alerts). Marketing M6e burst check still owed |
| 7 | Over-allowance email credit | Planned (approved 2026-09-24, contract `108b445`) | None in this campaign; reuses SMS Communication Balance | Essential email never stops on allowance/balance; optional overage charges Communication Balance and pauses when empty; Jafar price setting shows SES cost + industry hints; browser-verified |

## Known constraints

- Part 3 must add the event destination to `ucrm-operational-<org>` (not done in 2a) and route operational
  events apart from Marketing ones on the shared SNS topic. Part 6 must delete the orphaned Brevo domain for
  any org moved to SES (2a overwrites `provider_domain_id` with the SES ARN).

- 2b found this constraint live on Raad: 2a's cutover left the old Brevo sending domain still `verified`
  instead of retiring it, so two live `purpose='sending'` rows existed at once and the Email card picked the
  oldest (Brevo) by `created_at`. Fixed for Raad (Brevo senders deleted at the provider, domain retired via
  `begin_communication_email_domain_removal`/`finalize_...`) and the domains route now orders newest-first as
  a defensive display fix. Part 3/6 must still make the real per-contractor cutover itself retire the old
  domain, not rely on display ordering.

- Rehearsal on Jafar's real domain: export the Cloudflare zone first, test outside business hours, check the
  Hostinger inbox sends/receives before and after. `bounce.mail.upliftcontractor.com` already has SES MAIL FROM
  records, so choose unoccupied prefixes for the rehearsal.

- Pre-existing (not SES-specific), found live-testing Part 3: a sender's "business default" checkbox only
  governs automated sends (quotes/invoices/receipts). A staff member's own manual reply requires that sender's
  `assigned_user_id` to equal the actor -- `enqueue_conversation_reply_email` has no default fallback. Any
  future setup flow (Part 5) must tell the contractor to assign a sender to each staff member who needs to
  send manual email, not just mark one sender "default".
