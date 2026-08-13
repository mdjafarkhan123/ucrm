# Jafar Panel Roadmap

The permanent behavior lives in `docs/jafar-completion-contract.md` and its linked approved documents. This file owns only campaign ordering and gates.

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 0 | Audit and approved decision contract | Complete | None | Git history | Approved behavior, boundaries, and delivery gates are established. |
| 1 | Reconcile schema, generated types, and QueryClient ownership | Complete | 0 | Git history | No unresolved drift blocks writes and QueryClient is request/app scoped. |
| 2 | Durable operations, notifications, outbox, and atomic owner history | Complete | 1 | Git history | Failure work is attributable, recoverable, and database-tested. |
| 3 | Concurrency-safe provisioning and atomic password setup | Complete | 2 | Git history | Retry and setup consumption cannot duplicate or race. |
| 4 | Public application, templates, settings, receipts, and owner notifications | Complete | 2, 3 | Git history | Every onboarding acceptance check passes, including the remaining pgTAP test. |
| 5 | Prospect review through first contractor login | Complete | 3, 4 implementation | Git history | The real application-to-login journey works without the legacy direct-create path. |
| 6A | Commercial-control foundation | Complete | 4, 5 | Git history and `supabase/migrations/20260813200000_organization_commercial_control_foundation.sql` | Commercial timezone, immutable events, serialized projections, and safe notices form one database-tested seam. |
| 6B | Payments and paid-through control | Pending | 6A | Create when active | Renewals and adjustments update commercial state atomically, including optional late-renewal reactivation. |
| 6C | Versioned package changes and reasoned exceptions | Pending | 6A | Create when active | Package and exception changes are immediate, immutable, reasoned, and cannot leak private details. |
| 6D | Free access and categorized lifecycle control | Pending | 6A, 6B | Create when active | Free-access schedules and lifecycle transitions are serialized, reasoned, eligible, and safely disclosed. |
| 6E | Legacy organization reconciliation | Pending | 6B, 6C, 6D | Create when active | Every legacy organization has an explicit review state and a deliberate active or suspended outcome. |
| 6F | Searchable organization directory and attention queues | Pending | 6A, 6E | Create when active | Stable server pagination, protected search, summaries, and attention filters work without unbounded loading. |
| 6G | Unified history and Part 6 verification | Pending | 6B through 6F | Create when active | Every organization’s lifecycle and commercial access are explainable from immutable, correctly redacted records. |
| 7 | Team access and administrator recovery | Pending | 6G | Create when active | Jafar can recover administration without passwords, impersonation, or casual permission editing. |
| 8 | Operations and current-owner security hardening | Pending | 6G, 7 | Create when active | High-impact actions are attributable and recoverable within the approved single-owner boundary. |
| 9 | Recoverable closure and strict purge | Pending | 6G, 8 | Create when active | Closure is reversible for 30 days, then live tenant resources are removed without orphans. |
| 10 | Dependency-linked provider and CRM controls | Blocked by contractor subsystems | Relevant contractor module | Create per dependency | Every shipped contractor capability has matching Jafar eligibility, health, history, and recovery controls. |
| 11 | Final A-Z audit and Memory cleanup | Pending | 0 through 10 | Create when active | All approved gates pass, placeholders are removed, browser journeys are approved, and temporary campaign Memory is deleted. |

## Dependency-linked Part 10 slices

- Phone and SMS through Twilio.
- Tenant email domains and platform fallback through Brevo.
- Contractor-owned Stripe payment readiness and recovery.
- UCRM-hosted webchat eligibility and diagnostics.
- Contractor-owned review links and campaign readiness without direct review-provider reconciliation.
