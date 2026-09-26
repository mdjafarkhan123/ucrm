# Review history says "sent" for a request that is only scheduled

- **Priority:** P3
- **Why postponed:** Wording only. `private.log_review_request_activity()` writes "A review request was sent
  by email." on insert, but a request scheduled for a future date has not gone out yet, so the client and job
  history overstate what happened. Seen live on job #2 with a request scheduled for the next morning.
- **Reactivate when:** Review request copy is next revised, or a contractor asks why the history says a
  message was sent that the customer never received.
- **Constraint:** `review_requests` has no `send_at` column — the scheduled time lives with the message, so
  the trigger cannot tell scheduled from immediate as written. Decide whether to pass it in or to reword the
  summary to something true for both (the migration is
  `supabase/migrations/20260926210000_review_request_activity.sql`).
