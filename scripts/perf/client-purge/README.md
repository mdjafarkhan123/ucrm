# Permanent customer delete at a large test business

Reproduces `docs/data-privacy-deletion-engine.md` § Performance verification at a large test business on a
local Supabase copy (the data is about 3.2 GB, beyond the free dev database). Never run against the dev or
production database: the bulk seed turns triggers off.

1. In an empty folder holding only a copy of `supabase/config.toml` (the migration history does not replay from
   scratch), run `npx supabase@2.120.0 start -x realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor`,
   then `docker update --memory 2g --memory-swap 2g --cpus 2 supabase_db_ucrm`.
2. `npx supabase@2.120.0 db dump --db-url "$SUPABASE_DB_URL" -f schema.sql` and load it into
   `postgresql://postgres:postgres@127.0.0.1:54322/postgres` with `psql --single-transaction -f schema.sql`.
3. Add a throwaway Vault key: `select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'contact_fingerprint_key');`
4. `psql <local> --single-transaction -f heavy_customer_seed.sql`, then
   `python3 gen_bulk_seed.py > bulk_seed.sql` and run it as `supabase_admin` (password `postgres`), then `vacuum analyze`.
5. `psql <local> -f big_run.sql` (heavy customer: plan preview, purge time, whole-table reads) and
   `psql <local> -f batch_run.sql` (20 ordinary customers). Both roll back, so they repeat.
6. `npx supabase@2.120.0 stop` when done.
