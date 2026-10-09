# Client reminders — now

**Goal:** Contractors hear at once when a customer approves a quote or asks for changes online, and customers
get the confirmation, visit reminders, overdue-invoice reminders and job thank-you that the client switches
promise (email now, texts after registration).
**Plan:** `docs/client-reminders-behavior-contract.md`

**In progress:**

- 2 Quote alerts — built and proven in the app 2026-10-09; only the email-arrival check remains (needs the tunnel)

**Next part:** 4 Booking confirmation (needs 3, done 2026-10-09); finish Part 2's email check when the tunnel is up.

**Note:** background wakes reach the app only through the Cloudflare Tunnel; while it is down (HTTP 530 in `net._http_response`), no automation or email runs.

**Blockers:** none. Parent: `crm-launch-readiness` Part 11.
