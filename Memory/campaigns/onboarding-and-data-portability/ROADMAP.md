# Onboarding & Data Portability Roadmap

Owns launch-roadmap Step 2 (`docs/crm-launch-implementation-roadmap.md` § 2): safe assisted import in, safe
export out. Proven pattern + our own divergences: `docs/research/onboarding-import-export-research.md`.

Standard: 5-step wizard (Type → Upload → Map → Details → Result). Our hard email+phone uniqueness forces
dedupe rules HubSpot does not need. No import may trigger customer messages/automations/reviews/dunning.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Import clients + contacts + linked properties: upload → column-map (auto + editable) → preview with dedupe/error flags → idempotent batch → per-row result/error file | **DONE 2026-09-13** — backend + 4-screen wizard shipped; gate met (5b: imported twice, zero dupes, no customer-facing events; UI run: full Upload→Map→Review→Done in-browser, country-name→ISO fix, error-file download). Detail in code/tests/git. | — | Met |
| 2 | Export those same records: structured package (records + relationship IDs + manifest), permission-filtered, instant download | **DONE 2026-09-13** — scope narrowed to records-only, instant download (no attachments, no stored object/link — approved divergence from the original short-lived-link idea). Owner/admin-gated, rate-limited 5/min/org. Browser-verified as Raad LTD owner: CSV row counts match manifest exactly, no internal columns leak, rate limit fires correctly. Detail in code/tests/git (`src/lib/server/exports/client-export.ts`, `src/routes/api/exports/clients/+server.ts`). | Part 1 | Met |
| 3 | Price Book import + export (`catalog_items`), reusing Part 1 pattern | **DONE 2026-09-13** — fixed a launch-blocking 42501 (Part 7 B2's cost-column grant lockdown) via two narrow SECURITY DEFINER RPCs; browser-verified upload→map→review→commit→idempotent re-import→export end to end with real cost data. Detail in code/tests/git (`src/lib/server/imports/catalog-review.ts`, `src/lib/server/exports/catalog-export.ts`, `src/routes/api/imports/price-book/*`, `src/routes/api/exports/price-book/*`, migrations `20260916160000`/`20260916170000`). | Part 1 | Met |
| 4 | Opening balances (one model: unpaid invoices OR starting balance, never both) | Blocked | Launch Step 3 financial-reconciliation audit | No double-counting; no dunning triggered; reconciles from source to screen |
| 5 | Assisted onboarding checklist + internal runbook | **DONE 2026-09-13** — owner/admin-only "Getting started" card on the dashboard, computed live from real data (business profile, price book, first client, team invite) with no stored progress flag; auto-hides once complete. Plus `docs/onboarding-runbook.md` for assisted move-ins. Browser-verified as Raad LTD owner (card correctly hidden — org already complete; incomplete-state rendering and actions verified via mocked response). Detail in code/git (`src/lib/server/onboarding/checklist.ts`, `src/routes/api/onboarding/checklist/+server.ts`, `src/lib/components/dashboard/GettingStartedCard.svelte`). | Parts 1–3 | Met |

Parts 1–3 are closed; their build decisions now live in code (`src/lib/server/imports/*`,
`src/routes/api/imports/*`, `src/lib/components/imports/*`, migrations `20260916*`,
`src/lib/server/exports/*`, `src/routes/api/exports/*`) and the research doc. Part 5 reuses all three —
re-read the research doc + Part 1/2/3 code when starting it.
