# Client reminders — now

**Goal:** Contractors hear at once when a customer approves a quote or asks for changes online, and customers
get the confirmation, visit reminders, overdue-invoice reminders and job thank-you that the client switches
promise (email now, texts after registration).
**Plan:** `docs/client-reminders-behavior-contract.md`

**In progress:**

- 2 Quote alerts — started 2026-10-08; paused 2026-10-09 (Codex session stopped), unclaimed

**Next part:** 4 Booking confirmation (needs 3, done 2026-10-09), or resume paused Part 2.

**Note:** background wakes reach the app only through the Cloudflare Tunnel; while it is down (HTTP 530 in `net._http_response`), no automation or email runs.

**Blockers:** none. Parent: `crm-launch-readiness` Part 11.
