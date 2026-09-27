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
   2026-09-26 (`/reviews`; `list_review_requests` + `review_request_counts`; owner and office see it, sales gets
   a no-access screen; field member sees no menu item; dark mode fine). Perf on 50k synthetic requests (rolled
   back): pages 14-58 ms; a status filter matching nothing scans all rows, ~1.1 s. **5B Private feedback tab**:
   Built 2026-09-26, live-checked as owner (tab + count, cards, Start contacting, dark mode) and sales (no tab).
   Migrations `20260926200000` (list/set-status functions, new-feedback bell alert to owners/admins, bell only,
   no email) and `20260926210000` (trigger writing review milestones to client + job history). Closed 2026-09-26:
   the history trigger, the bell alert row and office-role access were all proven in a real browser; a Reviews
   tab click left its panel empty and was fixed (`74af3495`); the client half of the history had no surface, so
   the client page gained the work records' History panel (`088123cd`). Feedback list perf not measured (keyset
   on `review_feedback_organization_submitted_idx`; an organization's feedback is a small fraction of its
   requests). Assigning a feedback item to a person was never built — the approved 5B shape had status only, and
   the brief's "assign" is still open.
6. **Live verification** — Done 2026-09-26. Test data cleaned up (verified column-by-column first, no real
   history touched). Real send proven on job #14: delivered to a real inbox, Jafar clicked through with
   different ratings on 2 separate emails and confirmed it works well. Every role checked live in Raad LTD
   (owner/admin full + settings; office full minus settings; sales/finance correctly blocked; field has no
   Reviews access and correct assigned-only job scope). Perf: all three review tables carry the org-scoped
   indexes they need; bounded per-org lists, no capacity claim made. Told the jafar-panel campaign its
   review-link slice is unblocked.
7. **Rating + private-feedback page polish** — Done 2026-09-26. Copy on the rating/choice screen
   (`ReviewFeedbackJourney.svelte`) and the never-saved private-feedback defaults (`DEFAULT_REVIEW_FEEDBACK_FORM`
   in `settings.ts`) rewritten kinder and warmer. Redesigned `/v/[token]`: desktop keeps a floating card with a
   two-column choice-tile grid and hover lift; below 640px the real customer page (never the settings preview,
   which always keeps its framed card so it reads correctly in its dialog) drops to an edge-to-edge sheet with
   bigger touch targets, a stacked choice list, and a fixed bottom "Send feedback" bar on the form step.
   Browser-verified against the live database at both a desktop and a mobile viewport: routed stars → form →
   thanks, the two-choice path → form → thanks-with-Google-prompt, and the settings preview dialog still framed
   at a narrow window width. Test review requests were inserted directly for this and fully deleted afterward;
   `review_settings.routing_enabled` was restored to its original value.
