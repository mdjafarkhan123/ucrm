# Communications Roadmap

Permanent behavior lives in the approved Communications and channel contracts under docs/.

**Verification policy (Jafar, 2026-08-28): browser checks batch to the end.** Slices close on
code-level evidence — pgTAP, svelte-check, eslint, prettier, Svelte MCP autofixer — and every screen
built goes on the pending list below instead of being opened in a browser. Drain the whole list in
one pass at Part 9. Open a browser mid-campaign only when nothing else can answer the question (a new
interaction primitive, a reveal/prefetch or layout behavior no test can prove, or a bug Jafar saw on
screen); "it is a new screen" is not a reason.

## Pending browser verification

One line per screen, added when it is built, removed when the end pass clears it.

| Screen | From | What the pass must confirm |
| --- | --- | --- |
| `/jafar/communications` — `MessageRecoveryQueue` | 7.6a | Queue lists stuck mail; history prefetches on hover and opens; retry and cancel each re-check policy, toast, and refresh the queue |
| `/settings/communications/email` — usage card | 7.6b | Both meters read right against the period; reset date shows in the org timezone; the held-mail warning appears only when the reserve is exhausted |

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 0–5 | Email foundation through shared Conversations UI | Closed | — | Delivery, replies, attachments, and shared inbox verified |
| 6 | Templates, snippets, and preferences | Closed (2026-08-27) — preferences, snippets, platform library, org copy-on-write, composer picker all shipped and browser-verified; automation-owned sync deferred (Memory/deferred/INDEX.md) | Email, Conversations | Content and suppression behavior works as approved |
| 7 | Allowances, reputation, and Jafar controls | Closed at code level (2026-08-28) — every slice 7.1–7.6b done; screens queued for the Part 9 browser pass | 1–6 | Limits, reserves, pauses, recovery, and history enforced; screens queued for the Part 9 pass |
| 8 | Suspension, closure, and cleanup | Pending | 4, 7 | Recovery and provider cleanup are safe |
| 9 | Cross-domain completion | Pending | Shipped channels | Security and integration gates pass, and the pending browser-verification list above is drained in one pass |
| WC0 | Website Chat architecture and blueprint | Closed | Communications UI | Approved contract and delivery plan |
| WC1 | Entitlement and organization controls | Partial; later slice unscoped | WC0 | Limits, disable/suspend, health, audit, and Jafar controls complete |
| WC2 | Contractor widget management | Partial; preview slice pending | WC1 | Configuration, domains, preview, usage, and blocked states complete |
| WC3 | Shadow-DOM public widget shell | Closed | WC2 | Cross-origin widget works without style leakage |
| WC4 | Visitor identity, sessions, messaging, and staff UI | Closed | WC3 | Eight checks in the active packet pass |
| WC5+ | Presence, media, routing, and Automation/SMS integrations | Future | WC4 and owning channels | Create and approve each dependency-ready slice |
