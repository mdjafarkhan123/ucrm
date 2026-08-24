# Two applied migrations have no file in the repo

- **Priority:** P0


- **Campaign:** none - found during the quote package removal, 2026-08-21.
- **Reason:** `supabase_migrations.schema_migrations` holds `the_clients_message_lands_where_staff_read_it`
  and `preview_says_false_not_unknown`, and neither exists under `supabase/migrations/`. Their effects are
  live in the database, so nothing is broken today, but the repo can no longer rebuild this schema from
  scratch and a fresh environment would come up missing whatever they changed.
- **Reactivation trigger:** anyone provisions a second environment, or a local Supabase stack is stood up.
- **Prerequisites:** none - `select statements[1] from supabase_migrations.schema_migrations where
  version = ...` returns the applied SQL verbatim, which is how item 3's own missing file was recovered on
  2026-08-27. Commit both as timestamped migration files matching the applied order.
- **Checkpoint:** `select version, name from supabase_migrations.schema_migrations order by version;`

