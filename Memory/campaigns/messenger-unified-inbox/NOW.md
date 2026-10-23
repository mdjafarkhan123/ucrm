# Messenger in the Unified Inbox — now

**Goal:** A business connects its Facebook Page; customers' Messenger messages arrive in the Conversations inbox
like GoHighLevel does; staff reply from there; Meta's rules are respected. Messenger only (Instagram later).
**Core agreement — read on every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules, Decided) and the Messenger/Instagram + Connections sections of `docs/unified-inbox-behavior-contract.md`.
**Plan:** `docs/messenger-behavior-contract.md` and `docs/messenger-implementation-plan.md` — approved 2026-10-23, including the three product choices.
**Stage:** Planning done; building starts at Part 3.

**Facts a new session needs:** Meta app "Ucrm Messaging", App ID `1709471683925717` (2nd Facebook account; old 1419027217062214 abandoned), development mode, portfolio Uplift Contractor 855656587107152, Business Verification **Verified** 2026-10-18. Webhook host `https://app.upliftcontractor.com`. Test Page "Random News". Jafar logs in, types passwords and uploads; Claude drives Chrome.

**In progress:** Part 1 — permissions and login configuration done 2026-10-23; only the test Page choice remains — `parts/1-meta-app-dashboard-setup.md`. Part 1b done (app is managed by the portfolio).

**Next part:** 3 Database foundation — the contract asks for Jafar's go-ahead on database work before starting.

**Blockers (Jafar):** `META_APP_SECRET` in `.env` is still the old app's — paste the new app's secret (needed by Part 4). Test Page: the 2nd account manages only "Uplift Contractor", not Random News — Jafar picks (needed by Part 4).
