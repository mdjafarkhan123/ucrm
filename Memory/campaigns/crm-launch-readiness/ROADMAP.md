# CRM Launch Readiness Roadmap

This parent campaign tracks the nine approved delivery parts. Each product domain remains responsible for its
own implementation. Production infrastructure remains behind Jafar's separate topology and migration approval.

| Part | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Close trust blockers in security, permissions and financial history | Complete 2026-09-11 | Current product | Met |
| 2 | Make assisted adoption and exit safe | Complete 2026-09-17 — opening-balances import wizard browser-verified; campaign closed | Part 1 | Met |
| 3 | Finish and reconcile the everyday CRM operating core | Complete 2026-09-16 — `financial-reconciliation` campaign closed all 6 parts; detail lives in code, migrations, tests and `docs/financial-reconciliation-contract.md` | Part 1 and completed Part 2 foundations | Met |
| 4 | Ship the minimum website speed-to-lead experience | Complete 2026-09-18 — six stages built, proven end to end, Automations on for contractors | Part 3 | Met |
| 5 | Ship compliant missed-call text-back | Later, after the controlled first launch | Part 4; Twilio setup and messaging approval | Live tests prove consent, opt-out, quiet hours, deduplication, failure and cost controls |
| 6 | Ship safe one-click campaigns | Email first release done 2026-09-25 (marketing-growth closed); shared-SES load recheck in `operational-email-ses` Part 6 | Part 5 for SMS; protected email may precede SMS | Recipient eligibility, cancellation, partial failure and transactional-delivery protection are proven |
| 7 | Ship a policy-approved Google review flow | Later — Marketing blueprint §3 part 3; starts as its own campaign | Completed-work truth; email or approved SMS | Permissions, consent, reminders, private feedback and current policy approval pass |
| 8 | Final audit before advertising widely: accessibility, security, browsers, phone web; then only what early customers show they need | Priority 6 — after Parts 12–16 | Parts 1–7 as sold, 12–15 | Contractors can onboard, operate, reconcile and leave without routine staff/database help |
| 9 | Prove production and launch gradually | Last before launch (Jafar 2026-10-10: complete the app first). P9B built; the rest awaits P9A approval and no infrastructure is approved | Every capability sold in the controlled first launch | App packaging, staging, backup/restore, security, monitoring, failure and measured-load gates pass before controlled launch; self-hosted Supabase remains a separately approved later cutover |
| 10 | Necessary-feature gap research | Complete 2026-10-08 — labels agreed; gaps in the Feature checklist in `docs/crm-launch-implementation-roadmap.md` | Public Jobber sources | Each gap checked against code and labelled |
| 11 | Build the Urgent gap items: Quote-approval team alert; working client reminder switches | Complete 2026-10-10 — campaign `client-reminders` closed; switches checked live | Part 10 | Met |
| 12 | Alerts: phone and browser push alerts, each person's alert settings, and telling a teammate when they are put on a Visit or Assessment | Priority 2 — not started (asked 2026-10-01 for before launch; constraints in deferred `push-alerts-and-per-person-notification-settings`) | Part 11 | Alerts reach a phone with the app closed, respect each person's settings, and never send twice |
| 13 | Home screen and Reports: today's work, what needs action, money owed; a Reports screen beyond the accountant CSV | Priority 3 | Part 3 reconciliation | Figures match the books and respect each person's permissions |
| 14 | Customer portal: appointments, quotes, invoices, balances, asking for more work | Priority 4 | Part 11 | A customer sees only their own records and can act on them |
| 15 | Everyday extras: Quote templates, more automation recipes, move many Visits across Jobs, auto-archive stale Requests and Quotes, custom fields | Priority 5 — order set in NOW.md | Part 11 | Each item proven on the live app |
| 16 | Time clock: start and stop a live timer on a Visit or Job, clock in and out for the day, a Timesheets page for the week, and a manager's check of hours | Priority 1 — not started (crews use it daily; only hand-typed hours exist) | Part 11 | Crew times in and out on a phone, hours land on the Job cost and timesheet once, and a manager can correct them |

The controlled first launch waits for Parts 1–4 and 9. Start with a few closely supported paying contractors.
Wider rollout waits for the necessary Part 8 work and evidence from that first group. No capacity claim is made
without a named workload and measured result.
