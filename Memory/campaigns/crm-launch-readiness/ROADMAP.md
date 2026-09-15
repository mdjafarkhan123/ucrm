# CRM Launch Readiness Roadmap

This parent campaign tracks the nine approved delivery parts. Each product domain remains responsible for its
own implementation. Production infrastructure remains behind Jafar's separate topology and migration approval.

| Part | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Close trust blockers in security, permissions and financial history | Complete 2026-09-11 | Current product | Tenant/role isolation, immutable issued documents and safe financial corrections are proven |
| 2 | Make assisted adoption and exit safe | In progress — only opening balances remain | Part 1; opening balances wait for Part 3 financial rules | Repeat import creates no duplicates; errors are explainable; complete export is independently usable |
| 3 | Finish and reconcile the everyday CRM operating core | Active — owned by `financial-reconciliation` | Part 1 and completed Part 2 foundations | Reports, exports and the Request → Payment journey agree and failed bulk work is safely retryable |
| 4 | Ship the minimum website speed-to-lead experience | Planned for the controlled first launch | Part 3; existing Website Chat, email and Automation | Form/Chat creates or matches one lead and sends at most one eligible reply, stopping on human activity |
| 5 | Ship compliant missed-call text-back | Later, after the controlled first launch | Part 4; Twilio setup and messaging approval | Live tests prove consent, opt-out, quiet hours, deduplication, failure and cost controls |
| 6 | Ship safe one-click campaigns | Planned — owned by `marketing-growth` | Part 5 for SMS; protected email may precede SMS | Recipient eligibility, cancellation, partial failure and transactional-delivery protection are proven |
| 7 | Ship a policy-approved Google review flow | Later — routed through `marketing-growth` | Completed-work truth; email or approved SMS | Permissions, consent, reminders, private feedback and current policy approval pass |
| 8 | Productize only the wider-rollout needs shown by early customers | Waiting for controlled-launch evidence | Parts 1–7 as actually sold | Contractors can onboard, operate, reconcile and leave without routine staff/database help |
| 9 | Prove production and launch gradually | Preparation may run beside Part 3; implementation awaits topology approval | Every capability sold in the controlled first launch | Staging, backup/restore, cutover/rollback, security, monitoring, failure and measured-load gates pass |

The controlled first launch waits for Parts 1–4 and 9. Start with a few closely supported paying contractors.
Wider rollout waits for the necessary Part 8 work and evidence from that first group. No capacity claim is made
without a named workload and measured result.
