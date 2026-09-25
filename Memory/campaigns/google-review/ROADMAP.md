# Google review campaign — roadmap

Approved by Jafar 2026-09-25. Product truth: `docs/google-review-campaign-owner-brief.md`.

1. **Review settings** — Done 2026-09-25 (browser-verified as owner; role access verified in the database;
   `/reviews/settings`). The "automation needs a link" half of its gate moves to Part 4.
2. **Customer feedback page** — Done 2026-09-26 (routed and two-choice journeys, submit, revisit and Google
   exit verified in a real browser against the live database; `/v/[token]`, `review_requests`,
   `review_feedback`). Settings "Preview feedback page" still needs Jafar's glance while signed in.
3. **Manual "Request a review"** — Planned; needs 2. On completed job and client page; contact, channel (SMS
   first), style, send now/schedule; real delivery states; fieldworker only on own jobs.
4. **Automation** — Planned; needs 3. New job subject in the existing automation engine; enrol on close with
   every Visit completed or every N completed visits (recurring); 6-month cooldown wins; reminders 3 and 5 days;
   brief's stop rules; cannot activate without a saved Google link. Run performance-review design branch first.
5. **Reviews workspace** — Planned; needs 3. Top-level Reviews menu item; Requests + Private feedback tabs;
   recovery items New → Contacting customer → Resolved → Closed; owner alerts; client/job history.
6. **Live verification** — Planned; needs 4 and 5. Real SMS/email, every role login, performance verification.
   Then tell the jafar-panel campaign its review-link slice is unblocked.
