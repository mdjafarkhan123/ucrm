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
