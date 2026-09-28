# Background jobs have no production scheduler decision

Every background job today is scheduled the same way: `pg_cron` + `pg_net` inside the managed Supabase
database, posting to a bearer-protected `/api/internal/**` route, with the URL and secret in Vault. That
works, and the invitation, communications-email, automation, geocoding and inbound-attachment jobs all run
that way now. But the production target is Docker images on a VPS with the app's background workers as their
own containers, which is a different home for scheduling — and the Vault values are per-environment, so they
are set up twice if the pattern stays.

Deferred because it is one decision for all workers at once, belongs with the production topology Jafar has to
approve, and nothing is blocked meanwhile. Reactivate at the managed-to-self-hosted migration rehearsal, or
sooner if a job's lateness starts costing something.

Already known: self-hosted Supabase ships pg_cron, pg_net and Vault too, so keeping the current pattern is
viable and is not a forced rewrite — the real question is whether scheduling belongs in the database or in the
worker container, where it is easier to watch and to deploy. One job is already waiting on this decision:
`supabase/migrations/_deferred/20260911120500_schedule_member_identity_cleanup_worker.sql`, held out of the
migrations folder so the CLI cannot apply it. Until it is scheduled, identity cleanup after a permanent
removal runs on demand (`POST /api/internal/team-members/identity-cleanup/worker`).

Also known (2026-09-21): the automation one-minute sweep (`automation-worker-wake-one-minute`) has been switched on
in the shared development database since 2026-08-31 — the migration installs it off. Its Vault target URL and
secret must be set deliberately per environment; production must not inherit this by accident.

Also known (2026-09-24): the Marketing wake cron jobs fail every minute in the shared development database
because their Vault target URLs are unset. Set them deliberately per environment with the others.

Also known (2026-09-25): Files and Media ships two more crons off by default, same pattern. Both need a Vault
target URL set before they can run: `files-processing-worker-wake-one-minute` (needs
`files_processing_worker_target_url` + `files_processing_worker_secret`, plus `FILES_PROCESSING_WORKER_SECRET`/
`FILES_SCANNER_HOST`/`FILES_SCANNER_PORT` in the app's own env) and `files-export-worker-wake-five-minutes`
(needs `files_export_worker_target_url` pointing at `/api/internal/files/export-worker`; reuses the processing
worker's existing secret, no new secret value). Until these are active, upload processing and organization
export both only ever reach `queued`/`pending` locally — this is why Files and Media parts 3, 8A, and 8B were
each closed without a full local end-to-end run of their async path. The ClamAV container itself runs fine
(`docker-compose.scanner.yml`); only `FILES_SCANNER_HOST`/`PORT` were never added to `.env`. Hit again in
deferred-launch-sweep Part 7e (price-list photo): data-verified everywhere (item, price book, quote line,
quote save) but stays a placeholder image until this is turned on -- same root cause, not a new bug.
