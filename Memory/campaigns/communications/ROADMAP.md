# Communications Roadmap

Permanent behavior lives in the approved Communications and channel contracts under docs/.

**Verification policy (Jafar, 2026-08-28): browser checks batch to the end.** Slices close on
code-level evidence — pgTAP, svelte-check, eslint, prettier, Svelte MCP autofixer — and every screen
built goes on the pending list below instead of being opened in a browser. Drain the whole list in
one pass at Part 9. Open a browser mid-campaign only when nothing else can answer the question (a new
interaction primitive, a reveal/prefetch or layout behavior no test can prove, or a bug Jafar saw on
screen); "it is a new screen" is not a reason.

## Pending browser verification

Empty. All three Platform Owner screens were drained in the Part 9 pass (2026-08-28): recovery queue,
`/jafar/settings/cleanup`, and the org-detail Website Chat authority section all passed. Details in NOW.md.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 0–5 | Email foundation through shared Conversations UI | Closed | — | Delivery, replies, attachments, and shared inbox verified |
| 6 | Templates, snippets, and preferences | Closed (2026-08-27) — preferences, snippets, platform library, org copy-on-write, composer picker all shipped and browser-verified; automation-owned sync deferred (Memory/deferred/INDEX.md) | Email, Conversations | Content and suppression behavior works as approved |
| 7 | Allowances, reputation, and Jafar controls | Closed at code level (2026-08-28) — every slice 7.1–7.6b done; screens queued for the Part 9 browser pass | 1–6 | Limits, reserves, pauses, recovery, and history enforced; screens queued for the Part 9 pass |
| 8 | Suspension, closure, and cleanup | Closed (2026-08-28) — all five slices 8.1–8.5 done; screen queued for the Part 9 browser pass | 4, 7 | All five slices below pass their gates |
| 8.1 | Suspension and an open closure window defer contractor outbound mail; callbacks/replies keep flowing | Closed (2026-08-28) — migration `20260908090000`, pgTAP 12 green; no UI, nothing added to the browser list | 7 | pgTAP: suspended org claims nothing, deferred not cancelled; callback processing unaffected |
| 8.2 | Per-class retry deadlines; expired mail cancels with a readable reason | Closed (2026-08-28) — migration `20260908100000`, pgTAP 20 green; no UI, nothing added to the browser list | 8.1 | pgTAP: each class expires on its own clock; reactivation releases only live mail |
| 8.3 | Closure window: outbound stops, inbound routing and provider resources preserved 30 days, early-delete impact preview | Closed (2026-08-28) — migration `20260908110000` adds `preview_organization_closure_impact`, pgTAP 16 green; no UI, nothing added to the browser list | 8.1, 8.2 | pgTAP + preview counts aliases, queued messages, recent replies; restore re-opens sending |
| 8.4 | Purge does retryable Brevo cleanup (domains + senders); receipt reports per-component results | Closed (2026-08-28) — migration `20260908120000` + cron provider leg; pgTAP 41 green, cron vitest 19 green; no UI. Per-org webhooks don't exist today → reported not_applicable (contract § Suspension, closure, and deletion). Unified receipt state model: status is in_progress/failed_partial/completed across both external legs | 8.3 | Cleanup failure leaves the receipt retryable; receipt holds no recipients/content/identifiers |
| 8.5 | Jafar closure-impact preview and provider-cleanup retry on `/jafar/settings/cleanup` | Closed (2026-08-28) — svelte-check/eslint/prettier/autofixer clean; vitest 37 green across the four touched spec files; screen added to the pending browser list above | 8.3, 8.4 | Screen built and added to the pending browser list above |
| 9 | Cross-domain completion | Closed (2026-08-28) — Vitest sweep 42 files / 252 tests green; all five browser screens passed (contractor email-usage, Website Chat settings, recovery queue, cleanup, org-detail Website Chat authority). Pending browser list drained | Shipped channels | Security and integration gates pass, and the pending browser-verification list above is drained in one pass |
| WC0 | Website Chat architecture and blueprint | Closed | Communications UI | Approved contract and delivery plan |
| WC1 | Entitlement and organization controls | Closed (2026-08-28) — authority migration and FK-index follow-up applied to the linked remote project; pgTAP 33 green with rollback confirmed; security/foreign-key advisor gates clear; screen queued for Part 9 | WC0 | Limits, disable/suspend, health, audit, and Jafar controls complete |
| WC2 | Contractor widget management | Closed at code level (2026-08-28) — existing configuration/domains/install workflow retained; contractor usage, blocked/suspension states, and responsive live preview added; Svelte autofixer, targeted ESLint, and Prettier clean; screen queued for Part 9 | WC1 | Configuration, domains, preview, usage, and blocked states complete |
| WC3 | Shadow-DOM public widget shell | Closed | WC2 | Cross-origin widget works without style leakage |
| WC4 | Visitor identity, sessions, messaging, and staff UI | Closed | WC3 | Eight checks in the active packet pass |
| WC5+ | Presence, media, routing, and Automation/SMS integrations | Future | WC4 and owning channels | Create and approve each dependency-ready slice |
