# CRM Launch Readiness Roadmap

This parent campaign tracks the nine approved delivery parts. Each product domain remains responsible for its
own implementation. Production infrastructure remains behind Jafar's separate topology and migration approval.

| Part | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Close trust blockers in security, permissions and financial history | Complete 2026-09-11 | Current product | Tenant/role isolation, immutable issued documents and safe financial corrections are proven |
| 2 | Make assisted adoption and exit safe | Complete 2026-09-17 — opening-balances assisted-import wizard (`onboarding-and-data-portability` Part 4) browser-verified and committed; campaign closed | Part 1; opening balances wait for Part 3 financial rules — satisfied 2026-09-16 | Met |
| 3 | Finish and reconcile the everyday CRM operating core | Complete 2026-09-16 — `financial-reconciliation` campaign closed all 6 parts: contract, permission-aware reports, accountant CSV package, batch billing failure handling, Sales Pipeline final audit, and the journey-trace + opening-balance schema/readers/export. Memory folder removed; detail lives in code, migrations, tests and `docs/financial-reconciliation-contract.md` | Part 1 and completed Part 2 foundations | Met |
| 4 | Ship the minimum website speed-to-lead experience | Complete 2026-09-18 — all six stages built, browser-verified, proven end to end (33/33), Automations switched on for contractors and work committed | Part 3; existing Website Chat, email, SMS and Automation | Met |
| 5 | Ship compliant missed-call text-back | Later, after the controlled first launch | Part 4; Twilio setup and messaging approval | Live tests prove consent, opt-out, quiet hours, deduplication, failure and cost controls |
| 6 | Ship safe one-click campaigns | Email first release done 2026-09-25 (marketing-growth closed); shared-SES load recheck in `operational-email-ses` Part 6 | Part 5 for SMS; protected email may precede SMS | Recipient eligibility, cancellation, partial failure and transactional-delivery protection are proven |
| 7 | Ship a policy-approved Google review flow | Later — Marketing blueprint §3 part 3; starts as its own campaign | Completed-work truth; email or approved SMS | Permissions, consent, reminders, private feedback and current policy approval pass |
| 8 | Productize only the wider-rollout needs shown by early customers | Waiting for controlled-launch evidence | Parts 1–7 as actually sold | Contractors can onboard, operate, reconcile and leave without routine staff/database help |
| 9 | Prove production and launch gradually | In progress — corrected hybrid-pilot plan awaits P9A approval; no infrastructure implementation approved | Every capability sold in the controlled first launch | App packaging, staging, backup/restore, security, monitoring, failure and measured-load gates pass before controlled launch; self-hosted Supabase remains a separately approved later cutover |
| 10 | Necessary-feature gap research | Complete 2026-10-08 — Jafar agreed the labels | Public Jobber sources (help centre, pricing, updates, videos, Capterra/G2 reviews), brief Housecall Pro check; no subscriptions | Every gap is checked against the code, kept only if needed, labelled Urgent/High/Medium/Later with a reason and example, and added to the Feature checklist in `docs/crm-launch-implementation-roadmap.md` |
| 11 | Build the Urgent gap items: team alert on online Quote approval or change request; working client visit and overdue-invoice reminders (email now, text after registration) | Running as campaign `client-reminders` (Jafar 2026-10-08: build before anything else; also job follow-up and booking confirmation) | Part 10; existing email delivery and client reminder switches | Both alerts and both reminder switches proven to send, respect each switch, and never send twice |

The controlled first launch waits for Parts 1–4 and 9. Start with a few closely supported paying contractors.
Wider rollout waits for the necessary Part 8 work and evidence from that first group. No capacity claim is made
without a named workload and measured result.
