# Requests held for booking approval show a blank status badge

**Why it waits:** Found during deferred sweep Part 7a (2026-09-28), outside that slice. The public booking form
can store a request as `needs_approval` (allowed by `requests_status_check`), but the app's status list
(`src/lib/requests/statuses.ts`) doesn't know it: the Requests table shows an empty badge (Raad LTD's
"M5Gate Test" row), the Status filter can't pick it, and the Overview counts skip it.
**Brings it back:** The next Requests or booking-form work, or Jafar asks.
**Known constraints:** Decide whether a held request with a proposed time keeps saying "Needs approval" or
turns into a calendar status; `deriveRequestStatus`, `request_status_counts` and `displayStatusFilter` must
all follow the same answer.
