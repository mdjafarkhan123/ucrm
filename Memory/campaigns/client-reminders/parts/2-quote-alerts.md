# 2 — Quote alerts

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § Quote approved or changes requested online
**Code:** worktree `../Ucrm-reminders`, branch `client-reminders-p2` (main folder had another writer)
**Done when:** Approving through a quote link puts one alert in the owner's bell and one email in their inbox; repeating it adds none; the customer gets one thank-you.

## Steps

- [x] Migration `supabase/migrations/20261106090000_quote_answer_alerts.sql` written
- [ ] Apply to the remote database, recorded as version 20261106090000
- [ ] TypeScript: alert kinds in `src/lib/team/notifications.ts`; email footer in `src/lib/server/team/inquiry-alerts.ts`; tests
- [ ] Prove: approve, ask for changes, decline (long message) through a real quote link; check bell, alert email, thank-you
- [ ] Merge to `main`, remove worktree

## Next

Apply the migration (outside action below), then the TypeScript step.

## Outside actions

- Apply migration — check: `select version from supabase_migrations.schema_migrations where version = '20261106090000'` and `select count(*) from pg_proc where proname = 'send_quote_approval_thanks'` — pending

## Notes

- Do not run `supabase db push`: local `20261105090000_organization_directory_filters.sql` is live under version 20261006114433 and would run again.
- Found and fixed here: a decline message over 500 characters failed the customer's whole answer (alert body limit).
