# Google review campaign — roadmap

Approved by Jafar 2026-09-25. Product truth: `docs/google-review-campaign-owner-brief.md`.

1. **Review settings** — Done 2026-09-25 (browser-verified as owner; role access verified in the database;
   `/reviews/settings`). The "automation needs a link" half of its gate moves to Part 4.
2. **Customer feedback page** — Done 2026-09-26 (routed and two-choice journeys, submit, revisit and Google
   exit verified in a real browser against the live database; `/v/[token]`, `review_requests`,
   `review_feedback`). Settings "Preview feedback page" still needs Jafar's glance while signed in.
3. **Manual "Request a review"** — Done 2026-09-26 (`9654e1e`, `a690456`). Proven live as owner (send, schedule,
   cancel, client-page job pick) and as field member (button only on a closed job they were assigned to).
4. **Reminders + automatic ask** — Done 2026-09-26. **4A reminder plan** (`a4fbbc5`, `7953db8`): settings
   timeline, warnings, wording, save/reload and stale-save conflict browser-verified as owner; panel plan note
   verified; field-member scope verified in the database; claim uses `review_requests_next_reminder_idx`
   (0.8 ms at 50k rows, rolled back); sustained backlog throughput not load-tested. **4B automatic ask**
   (`ea9840c`, `0cbdf66`): engine + builder built, perf verified (rolled back, single samples). Live-proven
   twice on Raad: no-sender case (job #23, "Not sent" with reason shown in the panel) and real-send case (job
   #24, 2026-09-26 — automatic email delivered to a real inbox via SES, confirmed in Gmail; recipe `34803b3e`
   paused afterward).
5. **Reviews workspace** — Approved 2026-09-26 as two builds. **5A page + Requests tab**: Built and browser-verified
   2026-09-26 (`/reviews`; menu item now probes `reviews.view`; `list_review_requests` + `review_request_counts`;
   owner and office see it, sales gets a no-access screen). Perf on 50k synthetic requests (rolled back): pages
   14-58 ms; a status filter matching nothing scans all rows, ~1.1 s (not load-tested beyond that; search with many
   clients not measured). Not yet checked: field-member login, dark mode, cancel-request click, client/job history
   still only shows in the request panel. **5B Private feedback tab**: Planned; recovery cards New → Contacting
   customer → Resolved → Closed (`review_feedback.status`), `reviews.feedback`, bell alert to owners/admins only.
6. **Live verification** — Planned; needs 4 and 5. Real SMS/email, every role login, performance verification.
   Then tell the jafar-panel campaign its review-link slice is unblocked.
