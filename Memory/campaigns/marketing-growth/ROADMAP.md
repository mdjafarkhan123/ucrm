# Marketing Growth Roadmap

Permanent product behavior lives in `docs/marketing-product-blueprint.md`. Research support lives in
`docs/research/marketing-product-patterns-2026-09-15.md` and
`docs/research/marketing-bulk-email-safety-2026-09-15.md`.

## Goal

Give contractors a simple, safe way to create repeat work from existing relationships: one-off email first,
then useful automation, reputation, SMS, referrals, and broader growth tools without turning UCRM into GHL.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| M0 | First-release implementation plan | Complete 2026-09-18; provider boundary amended by Jafar afterward: Brevo for Jafar/platform email, SES for contractor CRM operational and Marketing email; sandbox-first proof, controlled US explicit-opt-in Marketing pilot, and globally disabled release until M6 passes remain approved | Approved blueprint; current CRM/email/Automation contracts | One reviewable plan identifies reuse, data and API ownership, UI slices, provider campaign delivery, security, migration, verification, rollback, and scale evidence without changing approved behavior |
| M1 | Access, readiness, sender and Marketing allowance | Complete `8ef77f7` | M0; contractor email foundation | Correct roles and packages see Marketing; owner/admin launch is enforced; verified Marketing sender, reputation/readiness, separate allowance, and protected service priority are explainable and testable |
| M2 | Customer groups and exact recipient preview | Complete 2026-09-20 — M2a server `a3f13ca`, M2b UI browser-verified end to end (real Supabase, Raad LTD): rule builder, live count, View customers, save/edit/delete. Found and fixed a real bug in verification: `AsyncMultiPicker` used a plain `Map` for chip labels, which Svelte 5 `$state` doesn't deep-proxy, so a reopened group's id-backed conditions (services, always-include/exclude customers) showed a raw uuid instead of a name once the async label fetch resolved after mount — fixed with `SvelteMap` from `svelte/reactivity` | M1; Customers and work history | Dynamic past-customer/lost-lead rules, bounded preview, deduplication, consent/exclusion reasons, and a frozen launch snapshot agree |
| M3 | Drafts, three goals, templates and email editor | Complete 2026-09-20 -- M3a `9e99852`; Templates tab `e53d53a`; journey Steps 1-2 `cf61575`; Step 3 (block editor) `5576295`; Step 4 (Delivery) `eedc056`; Step 5 (Review) `fe7cba9`, all browser-verified. Send/Schedule and "send a test email" stay disabled/out of scope until M4 builds the real SES send path (see M3's own note) | M1–M2; Requests/Bookings CTA | Contractors can deliberately create, save, preview, test, and review a branded campaign for the three approved first-release goals |
| M4 | Safe send, schedule, gradual delivery and cancellation | Planned | M1–M3; Communications email contracts | One authorized launch uses provider campaign/batching plus bounded fair release; send-time rechecks, idempotency, partial failure, pause, and cancellation protect recipients and service email |
| M5 | Results, replies and honest attribution | Planned | M4; Conversations and CRM lifecycle | Paginated recipient results, shared-inbox replies, direct/window attribution labels, and campaign/customer timelines agree without overwriting original lead source |
| M6 | Integrated first-release proof | Planned | M1–M5 | Browser, role/tenant, accessibility, recovery, provider-callback, cancellation-race, representative-load, and service-email protection gates pass; claims stay within measured evidence |
| M7 | Automatic past-customer and lost-lead presets | Later — first follow-up | M6; Automation future-event truth | Plain-language presets use Automation safely and never silently enroll historical customers |
| M8 | Reputation and review recovery | Later — second follow-up | M6; completed-work truth; current policy review | Manual/preset requests, public destination, private recovery, permissions, reminders, stop rules, and honest reporting pass |
| M9 | SMS marketing | Later | M6; Communications A2 live SMS safety | Registration, purpose consent, STOP/HELP, quiet hours, cost, callbacks, reply handling, and live delivery are proven before release |
| M10 | Referrals and credits | Later | M8; billing/invoice credit truth | Referral links, rewards, credits, invoice application, attribution, and anti-abuse behavior are approved and proven |
| M11 | Broader contractor growth surfaces | Later — plan on demand | First-release evidence | Social posting/calendar, Google profile optimization, job showcase, website/landing builder, and broader templates have separately approved product plans |
| M12 | Advanced marketing | Later — evidence-led | Demonstrated customer demand | Paid ads/prospecting, advanced branching/loops, A/B tests, predictive audiences/AI, multi-touch attribution/ROI, multi-location, and multi-asset planning are separately approved before implementation |

## Boundaries and risks

- The contractor clicks once; UCRM delivers progressively. Never promise all recipients in one second.
- Marketing cannot consume the protected operational-email reserve or use a transactional-send loop as bulk fan-out.
- Imported contacts without reliable Marketing-consent source and date remain excluded.
- Marketing owns goals, audiences, content, launch, and results. Communications owns channel delivery; Automation
  owns always-on execution; source domains keep Customer, work, booking, payment, and completion truth.
- Schema, auth, permission, or infrastructure changes require the normal explicit approval before implementation.
