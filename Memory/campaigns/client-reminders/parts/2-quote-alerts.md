# 2 — Quote alerts

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § Quote approved or changes requested online
**Code:** on `main` (migration file recovered, alert kinds and email footer added 2026-10-09)
**Done when:** Approving through a quote link puts one alert in the owner's bell and one email in their inbox; repeating it adds none; the customer gets one thank-you.

## Steps

- [x] Migration `supabase/migrations/20261106090000_quote_answer_alerts.sql` written
- [x] Applied to the remote database as version 20261106090000 (confirmed 2026-10-09)
- [x] Lost migration file recovered from the database (same bytes)
- [x] TypeScript: alert kinds, email footer, tests
- [x] Prove in the app: approve (twice), changes, 990-character decline on Raad LTD quotes #44, #34, #31 — one bell alert each, browser-checked desktop and phone; approve-again added nothing; decline is bell-only
- [ ] Prove the emails arrive (waits for the Cloudflare Tunnel; it was down, HTTP 530)
- [x] On `main`; worktree removed

## Next

When the tunnel is up (Jafar restarts it), wait a minute, then check: the two `team_notifications` rows for
quotes #44 and #34 (kinds `quote.customer_approved`, `quote.changes_requested`, created 2026-10-09 09:44 UTC)
show `email_state = 'sent'`, and the delivery intent whose send key starts `quote-approval-thanks:9a50ce08`
was delivered to `dev.jafarkhan+part8@gmail.com`. Ask Jafar to confirm the alert email in
`info.socialmediauser1@gmail.com` and the thank-you in his Gmail. Then the part is done.

## Outside actions

- Apply migration — check: `select version from supabase_migrations.schema_migrations where version = '20261106090000'` and `select count(*) from pg_proc where proname = 'send_quote_approval_thanks'` — done 2026-10-09

## Notes

- Do not run `supabase db push`: local `20261105090000_organization_directory_filters.sql` is live under version 20261006114433 and would run again.
- Found and fixed here: a decline message over 500 characters failed the customer's whole answer (alert body limit).
