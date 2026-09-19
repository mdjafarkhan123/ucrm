# Jafar Panel Roadmap

Permanent behavior lives in docs/jafar-completion-contract.md.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 0–5 | Approved contract through first contractor login | Closed | — | Application, review, provisioning, and login work end to end |
| 6 | Commercial state, packages, access, directory, and history | Closed | 0–5 | Commercial control is serialized, explainable, and recoverable |
| 7 | Team access and administrator recovery | Closed | 6 | Recovery avoids passwords and impersonation |
| 8 | Operations and owner security | Closed | 6–7 | High-impact actions are attributable and recoverable |
| 9 | Recoverable closure and strict purge | Closed | 8 | Closure is reversible for 30 days, then resources are removed safely |
| 9A | Organization control room UX rebuild | Closed | 6–9 | URL-backed workspaces preserve every control, surface urgent state on Overview, and pass responsive/browser verification |
| 10 | Provider and CRM controls by subsystem | Partially closed — SMS, Email domains, Website Chat, Stripe closed 2026-09-19 | Contractor subsystem | Eligibility, health, history, and recovery exist for each shipped capability, or a documented reason why a slice doesn't need one |
| 11 | Final audit and cleanup | Pending | 0–10 | All approved gates pass and temporary campaign Memory is removed |

Part 10 slices may cover Twilio phone/SMS, Brevo tenant domains, Stripe readiness, Website Chat diagnostics, and review-link readiness when their contractor systems exist. SMS, Email domains, and Website Chat were built alongside their features under communications-activation (Stage 2C-6 Jafar owner UI, WC4) and browser-verified live 2026-09-18 (Raad LTD org): eligibility (registration, sender capabilities, domain verification), health (SMS worker health, platform-wide hold, retail rates), history (Activity log entries), and recovery (holds, credit top-ups, refunds, promotional credits, widget suspension) all confirmed working. Stripe slice (online-payments Part 7) shipped 2026-09-19: a read-only "Stripe connection health" card in the Communications tab (`GET`/`POST /api/jafar/organizations/[organizationId]/payments/stripe-connection`, backed by the existing `stripe-connection.ts` readiness module) shows account identity, live/test mode, last-checked time, and a sanitized health badge, plus a manual "Recheck now" action — browser-verified live on Raad LTD's sandbox connection (status "Healthy", recheck updated `last_checked_at` live). No eligibility/history/recovery controls: per docs/jafar-completion-contract.md, the restricted key is contractor-owned and never reaches Jafar, so there is nothing for Jafar to connect, disconnect, or recover — visibility plus recheck is the complete, intentionally narrower scope for this provider. Review-link slice stays blocked: that contractor subsystem doesn't exist yet.
