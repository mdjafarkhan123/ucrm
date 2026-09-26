# Google review campaign — roadmap

Approved by Jafar 2026-09-25. Product truth: `docs/google-review-campaign-owner-brief.md`.

1. **Review settings** — Done 2026-09-25 (browser-verified as owner; role access verified in the database;
   `/reviews/settings`). The "automation needs a link" half of its gate moves to Part 4.
2. **Customer feedback page** — Done 2026-09-26 (routed and two-choice journeys, submit, revisit and Google
   exit verified in a real browser against the live database; `/v/[token]`, `review_requests`,
   `review_feedback`). Settings "Preview feedback page" still needs Jafar's glance while signed in.
3. **Manual "Request a review"** — Done 2026-09-26 (`9654e1e`, `a690456`). Proven live as owner (send, schedule,
   cancel, client-page job pick) and as field member (button only on a closed job they were assigned to).
4. **Reminders + automatic ask** — In progress; needs 3. Decisions made 2026-09-26 (brief § How the automation
   is set up). **4A reminder plan — Done 2026-09-26** (`a4fbbc5`, `7953db8`): settings timeline, warnings,
   wording, save/reload and stale-save conflict browser-verified as owner; panel plan note verified; field-member
   scope verified in the database; claim uses `review_requests_next_reminder_idx` (0.8 ms at 50k rows, rolled
   back); sustained backlog throughput not load-tested. **4B automatic ask** next. Packet: `parts/04-automation.md`.
   Gate: 4B proven live; performance design + verification done for 4B.
5. **Reviews workspace** — Planned; needs 3. Menu item "Reviews" already live (2026-09-26) but points at
   `/reviews/settings` and is probed by `reviews.manage`; move it to the workspace and its view permission. Top-level; Requests + Private feedback tabs;
   recovery items New → Contacting customer → Resolved → Closed; owner alerts; client/job history.
6. **Live verification** — Planned; needs 4 and 5. Real SMS/email, every role login, performance verification.
   Then tell the jafar-panel campaign its review-link slice is unblocked.
