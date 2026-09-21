# Three small live database gaps found while fixing the stale tests

- **Priority:** P3. **Reactivation:** Jafar approves a live database change (each is a one-file migration; none is urgent). All 162 pgTAP files pass on a rebuild as of 2026-09-21.
- **Outbound email attachments have no fixed order.** `list_communication_outbound_attachments` sorts by `created_at, id`, but files attached in one call share one
  `created_at`, so the tie is broken by a random id. Fix: an explicit position column set from the array order. Then restore the ordered check in
  `communications_outbound_attachments.sql` (it is a set check today).
- **A sender can still be added while its domain is being removed.** `validate_communication_email_sender` only refuses a `removed` domain, and finalizing a removal never
  touches senders, so a not-yet-enabled sender can be left on a removed domain (it can never send). Fix: refuse `removal_pending` on insert. Then tighten
  `communications_domain_sender_authority.sql` test 23 back to a `pending_verification` insert.
- **`private.member_permission_scope` is executable by `authenticated`** (added with the Field role, `d0520f5`). Nothing needs it: callers are SECURITY DEFINER and `authenticated`
  has no USAGE on `private`. Fix: revoke it, then flip its row in `team_function_grant_matrix.sql` to `array[]::text[]`.
- Run one test file against a scratch stack with `supabase test db --db-url "postgresql://postgres:postgres@127.0.0.1:<port>/postgres?sslmode=disable" <file>`.
