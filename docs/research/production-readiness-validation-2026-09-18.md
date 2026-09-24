# Production-readiness plan validation

**Research date:** 2026-09-18  
**Document reviewed:** `docs/production-readiness-plan.md`  
**Status:** Research finding only. No infrastructure, topology, spend, recovery target, or cutover method is approved by this note.

## Verdict

The draft has the right broad direction: immutable application images, Supabase's self-hosted Docker distribution rather than the CLI development stack, an off-host PostgreSQL recovery system, a separate rehearsal environment, and evidence-based load testing.

It is **not ready for approval as written**. The cutover rollback would lose or split post-cutover writes; the migration command is wrong for Supabase; the backup claim does not actually guarantee the stated RPO; a database backup alone cannot recover Vault or R2 objects; the monitoring design promises data that an external Worker cannot observe; and the Hostinger sizing statement is a capacity claim without a measured workload. Redis/BullMQ, `adapter-node`, production Dockerfiles, and a deployment workflow are also future architecture, not the repository's current state.

## Critical corrections before approval

| Draft statement | Validation | Required correction |
| --- | --- | --- |
| Hostinger KVM 4 “comfortably” runs the full stack, app, Redis, and workers | KVM 4 has 4 vCPU, 16 GB RAM, 200 GB storage, 300 MB/s I/O, and 16 TB bandwidth. This clears Supabase's published recommended **starting specification** for all components, but it does not prove headroom for this workload or for colocated components. [Hostinger plan limits](https://support.hostinger.com/en/articles/6976044-parameters-and-limits-of-hosting-plans-in-hostinger), [Supabase Docker requirements](https://supabase.com/docs/guides/self-hosting/docker) | Call KVM 4 a **single-node pilot candidate**. Approve it only after production-like load, restore, backup-overhead, disk-growth, and failure tests. One VPS remains one failure domain. |
| The production stack is Postgres/Auth/PostgREST/Realtime/Storage/Studio plus Envoy | In the current official `v0.8.1` snapshot the base Compose services are `studio`, `api-gw`, `auth`, `rest`, `realtime`, `storage`, `imgproxy`, `meta`, `functions`, `db`, and `supavisor`. Logs/Analytics and Vector became optional in June 2026. Envoy became the default gateway in August 2026. [Pinned v0.8.1 Compose file](https://github.com/supabase/supabase/blob/self-hosted/v0.8.1/docker/docker-compose.yml), [Supabase self-hosting changelog](https://supabase.com/changelog) | Name and test the exact snapshot and services. Decide whether Functions, Studio, imgproxy, Storage, Realtime, and Supavisor are required; remove unused optional services instead of silently running them. |
| Only the gateway is public and Studio stays private | Envoy routes both public APIs and Studio. Its admin port `9901` exposes sensitive configuration and must remain local. The official Compose also publishes the gateway on `8000` and Supavisor/Postgres access on `5432` and `6543` unless deployment overrides or firewall rules prevent it. [Envoy self-hosting guide](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/self-hosting/self-hosted-envoy.mdx), [official Compose file](https://github.com/supabase/supabase/blob/self-hosted/v0.8.1/docker/docker-compose.yml) | Specify the exact proxy routes, bindings, firewall rules, and administrator access method. Do not expose Studio's root route, Envoy admin, database, or pooler to the public Internet. |
| WAL fills a segment in minutes, giving a minutes-level RPO | PostgreSQL may leave a partly filled WAL segment unarchived indefinitely on a low-write system. A failed archive command can also fill `pg_wal` and eventually stop the database. [PostgreSQL continuous archiving](https://www.postgresql.org/docs/current/continuous-archiving.html) | Set and test an `archive_timeout` comfortably below the approved RPO, and alert on archive failures, age/lag, and local WAL growth. A daily base backup plus WAL is not enough without these controls. |
| WAL-G is selected because pgBackRest was paused in April 2026 | The cited source is not primary, and the claim is false against the current official project: pgBackRest released `2.59.1` in August 2026 and documents PostgreSQL 17 and S3-compatible repositories. WAL-G is also active and supports PostgreSQL WAL/base backups and S3-compatible endpoints. [pgBackRest project](https://github.com/pgbackrest/pgbackrest), [pgBackRest user guide](https://pgbackrest.org/user-guide.html), [WAL-G PostgreSQL guide](https://github.com/wal-g/wal-g/blob/master/docs/PostgreSQL.md), [WAL-G storage guide](https://github.com/wal-g/wal-g/blob/master/docs/STORAGES.md) | Remove the maintenance claim. Treat WAL-G as a viable candidate, not a settled choice, until a staging spike proves full backup, continuous archive, latest recovery, and time-target recovery against the pinned Supabase/Postgres image and R2. Compare pgBackRest on the same acceptance test if the choice remains open. |
| Cut over using one `pg_dump`/`pg_restore` | Supabase's official managed-to-self-hosted procedure uses three exports: roles, schema, and COPY-format data. A raw `pg_dump` includes Supabase-managed internals and produces ownership/permission failures. [Restore a platform project to self-hosted](https://supabase.com/docs/guides/self-hosting/restore-from-platform) | Rehearse the exact official `supabase db dump --role-only`, schema dump, and `--use-copy --data-only` flow, followed by the documented transactional restore order. Pin both source and destination PostgreSQL compatibility. |
| After cutover, rollback is switching the connection string back | That is safe only while the target has accepted **no unique writes**. After writes reopen, the old managed database is stale; switching back discards or splits new jobs, invoices, payments, auth changes, and queued work. | Define the rollback boundary. Before reopening writes, DNS/config rollback is allowed. After reopening writes, use a forward fix or a rehearsed reverse-sync/reconciliation procedure with an explicit loss policy. Drain and pause API writes, background work, scheduled work, and inbound webhooks during the final copy and validation. |
| R2 remains unchanged | PostgreSQL recovery does not recover R2 object bytes. Restoring the database to an earlier time can leave rows pointing to objects deleted later. R2 durability does not protect against application deletion; Bucket Lock can protect a backup bucket but changes deletion behavior. [R2 durability](https://developers.cloudflare.com/r2/reference/durability/), [R2 Bucket Lock](https://developers.cloudflare.com/r2/buckets/bucket-locks/), [R2 S3 compatibility](https://developers.cloudflare.com/r2/api/s3/api/) | Separate the app-object and database-backup buckets/credentials. Decide and test object retention/recovery, including database-to-object consistency. Confirm there are no Supabase Storage blobs; database dumps include Storage metadata, not the object bytes. |
| A Git SHA tag makes an image immutable | Registry tags, including SHA-shaped tags, can be moved. A digest identifies immutable image content. [Docker image digests](https://docs.docker.com/dhi/core-concepts/digests/), [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) | Build once, attest/sign as desired, deploy by `image@sha256:digest`, and record the promoted digest. An old app digest does not reverse a database migration, so releases need a backward-compatible migration and rollback contract. |
| A Cloudflare Worker checks app, DB, disk, queue, and error spikes | A Cron Worker can run every minute and one run/minute fits the free request allowance, but an outside HTTP probe only sees public HTTP. It cannot independently observe host disk, private queue age, or internal error rate unless the app/host exports them. Cron changes can take up to 15 minutes to propagate. [Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) | Use the Worker for black-box reachability and a deliberately narrow authenticated readiness signal. Add host/service metrics and off-host log/alert storage for disk, WAL, database, queues, and errors. Deduplicate Telegram alerts and send recovery notices. Add a heartbeat/dead-man mechanism if Cloudflare being a common failure domain is accepted. |
| Redis/BullMQ queue health is part of launch | The repository does not currently contain a working BullMQ/Redis worker implementation; its live asynchronous paths are primarily database/RPC/cron-based, and the `workers/` placeholders are empty. | Remove Redis/BullMQ from the launch topology unless a separately approved design shows a launch requirement. Monitor the queues the application actually uses. |

## Supabase release facts that change the plan

The plan must pin an official self-hosted release and read every intervening release note rather than treating `master` as a release. Supabase says the tested snapshots are released roughly monthly and does not guarantee arbitrary mixes of individual service versions. [Self-hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker), [Docker release changelog](https://github.com/supabase/supabase/blob/master/docker/CHANGELOG.md)

The current changelog contains several launch-relevant changes:

- Envoy is now the default self-hosted API gateway, replacing Kong. [17 July 2026 entry](https://supabase.com/changelog)
- Self-hosted Auth now expects `API_EXTERNAL_URL` to include `/auth/v1`. [18 June 2026 entry](https://supabase.com/changelog)
- Logs/Analytics and Vector are optional, and Studio/postgres-meta changed database-role behavior. [18 May 2026 entries](https://supabase.com/changelog)
- Current self-hosted Supabase ships PostgreSQL 17; a major upgrade is not automatic. The `db-config` volume contains the Vault root key, and losing that key makes existing Vault ciphertext unrecoverable. The upgrade also needs temporary disk space of about twice the database size plus 5 GB. [PostgreSQL 17 self-hosted upgrade](https://supabase.com/docs/guides/self-hosting/postgres-upgrade-17)
- New tables are no longer automatically exposed through the Data API. [28 April 2026 entry](https://supabase.com/changelog)
- Legacy `anon` and `service_role` JWT-based keys are scheduled for deprecation at the end of 2026. New publishable/secret keys and the resulting server-key migration need to be included in the production build. [API-key migration](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)

Supabase explicitly places operating-system hardening, service maintenance, backups/disaster recovery, monitoring, and high availability on the self-hosting operator. Managed backups/PITR and advanced metrics are not included. [Self-hosting overview](https://supabase.com/docs/guides/self-hosting)

## Migration and recovery contract

### What the official database migration carries

The documented three-dump procedure carries application schemas/data, roles, RLS, functions/triggers, and Auth rows, including password hashes. It does **not** recreate project API keys/JWT configuration, OAuth providers, SMTP, Edge Functions, DNS, or Storage object bytes. Users should be expected to sign in again when the signing configuration changes. [Restore a platform project to self-hosted](https://supabase.com/docs/guides/self-hosting/restore-from-platform), [migrating Auth users](https://supabase.com/docs/guides/troubleshooting/migrating-auth-users-between-projects)

This repository uses Supabase Vault. The Vault encryption root key lives outside PostgreSQL, so a database-only dump or WAL recovery is insufficient. The managed source key must be exported while the source still exists, installed in the destination through the documented mechanism, stored independently with restricted access, and included in clean-machine recovery rehearsals. This is an inference from Supabase's Vault and PostgreSQL 17 self-hosting documentation and must be proven in staging. [Vault](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/database/vault.mdx), [PostgreSQL 17 self-hosted upgrade](https://supabase.com/docs/guides/self-hosting/postgres-upgrade-17)

The browser Supabase URL/key are currently imported through SvelteKit's `$env/static/public`, which is statically injected at build time. Merely changing a server environment variable at cutover will not change those values in an already-built client bundle. Either build and promote a target-configured image or deliberately refactor to a validated runtime-public configuration mechanism before rehearsing cutover. [SvelteKit public static environment variables](https://svelte.dev/docs/kit/%24env-static-public)

### Required backup design decisions

PostgreSQL PITR requires one recoverable base backup plus an unbroken WAL chain; a logical dump is not a PITR base. [PostgreSQL continuous archiving](https://www.postgresql.org/docs/current/continuous-archiving.html)

Before implementation, the plan must specify:

1. The approved RPO and RTO. The draft's 15-minute/4-hour numbers must be reconfirmed because the overall plan is explicitly still a draft.
2. The selected tool/version, how it is installed without mutating the database container at runtime, and its compatibility with the pinned Postgres image.
3. Base-backup frequency, WAL timeout, retention window, pruning rules, encryption/credentials, and a separate least-privilege R2 backup credential. R2 supports bucket-scoped API tokens and S3-compatible endpoints. [R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/)
4. Alerts for failed/stale base backups, last successful WAL archive, restore verification, repository capacity, local `pg_wal` growth, and loss of the watcher itself.
5. Recovery of non-database state: Compose/config versions, application image digests, proxy/firewall configuration, provider configuration, encrypted secrets, and the Vault root key.
6. An automated latest restore and time-target restore onto a blank host. Full end-to-end restoration is the proof of recoverability, not a successful upload log. [Google SRE: Data Integrity](https://sre.google/sre-book/data-integrity/)

Hostinger's two daily and two weekly backups, plus one temporary snapshot, are useful host-level safety nets. They are not downloadable, restoring one replaces the current server state, and they do not replace the off-host PITR/clean-machine contract. [Hostinger VPS backup and restore](https://www.hostinger.com/support/1583232-how-to-back-up-or-restore-a-vps-at-hostinger/)

## Images and secrets

The destination should use a Node-compatible SvelteKit adapter and a multi-stage application Dockerfile, but the repository currently uses `adapter-auto`, has no production Dockerfile, and has no production image-publishing workflow. Those are implementation tasks, not established facts in the plan.

No application or infrastructure secret may be copied into an image layer, build argument, repository, browser bundle, or public health response. Docker recommends secrets rather than ordinary environment variables for sensitive values where the image supports file-based secrets. Supabase's upstream containers primarily use environment configuration, so the plan needs a concrete root-readable host configuration/configuration-management approach with strict file permissions and controlled backup—not the unresolved phrase “secrets manager or env file.” [Docker Compose environment guidance](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/), [Compose secrets](https://docs.docker.com/reference/compose-file/secrets/)

Treat the Vault root key as a separate recovery secret. Rotate bootstrap/default Supabase credentials before exposure, define an operator break-glass path, and test key/credential rotation in staging. GitHub Actions can produce artifact attestations for the exact image digest; that is recommended supply-chain evidence, not a substitute for runtime hardening. [GitHub artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)

## Monitoring boundary

The proposed Worker plus Telegram Bot is inexpensive and technically feasible: one run each minute is 1,440 invocations/day, and alert volume should be far below Telegram's documented group/broadcast limits. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Telegram Bot FAQ](https://core.telegram.org/bots/faq)

It is not independent of Cloudflare: the application currently uses Cloudflare Tunnel and R2, so a Cloudflare account/control-plane/network event can affect both the service path and the watcher. This may be an acceptable pilot trade-off, but the plan must say so. A dead-man heartbeat to another alert path is the minimum way to detect a silent Worker failure.

Use the Worker only for black-box HTTPS checks and a low-detail readiness result. Use host/service exporters or agents for CPU, memory, disk, filesystem inodes, network, process/container restarts, PostgreSQL connections/latency/locks, WAL archive age, and real queue state. Prometheus's node exporter is one official option for host metrics. [Prometheus node exporter guide](https://prometheus.io/docs/guides/node-exporter/)

The production ingress is also unresolved: direct Nginx/Caddy with Let's Encrypt and Cloudflare Tunnel/proxy are different designs. Select one concrete path and document source-IP trust, TLS termination, firewall exposure, OAuth redirect URLs, API external URL, and whether the external watchdog actually tests the same customer path.

## Staging, restore, load, and failure gates

“Production-like staging” must mean a separate, disposable failure domain using the same pinned Compose release, image digests, proxy/firewall shape, secret-injection method, and approximately representative database/object volume. A clean-machine restore cannot be proven by restoring onto the production VPS, and a load generator should run outside the tested host.

Before any capacity statement, write a workload contract containing:

- tenant count and tenant-size/skew distribution;
- database rows/bytes and object count/bytes, plus expected growth;
- concurrent signed-in users, request rate, read/write/action mix, and burst profile;
- concurrent Realtime connections and message/fan-out pattern if Realtime is kept;
- background arrival rate, provider limits, retry behavior, and acceptable oldest-job age;
- latency/error objectives for the important Lead → Request → Quote → Job → Invoice → Payment journeys;
- backup/archive activity during normal load.

Run a smoke test first, then average-load, stress, spike, and soak scenarios with thresholds. Report only the exact tested mix, duration, dataset, and result; 40,000 registered customers is not a concurrency or throughput claim. [k6 automated performance testing](https://grafana.com/docs/k6/latest/testing-guides/automated-performance-testing/), [k6 API load testing](https://grafana.com/docs/k6/latest/testing-guides/api-load-testing/)

Record p50/p95/p99 journey latency, errors/timeouts, database connections and query/lock latency, CPU/RAM, disk I/O/free space/inodes, WAL archive age, backup overhead, container restarts, actual queue age/retries, Realtime connections/fan-out, and R2/provider latency. The current evidence state is **Blocked: workload and measurements do not yet exist**.

Failure tests should start in non-production, define the steady-state signal, blast radius, rollback step, and automatic stop condition. Restart application/database services, remove one external dependency at a time, interrupt R2/WAL upload, exhaust the connection pool, simulate provider throttling, and test disk pressure on a bounded disposable volume rather than filling the host root disk. Verify customer-visible behavior, retry/idempotency, alert delivery, and recovery without manual database repair. [AWS Well-Architected failure injection guidance](https://docs.aws.amazon.com/wellarchitected/latest/framework/rel_testing_resiliency_failure_injection_resiliency.html)

## Decision frontier

Jafar should approve or reject these product/operating trade-offs before build-out:

1. **Pilot reliability:** accept one Hostinger VPS as one failure domain for the controlled pilot, with measured recovery rather than high availability, or fund separate failure domains now. Recommendation: accept one node only for the closely supported pilot and make the limitation explicit.
2. **Recovery promise:** confirm a maximum 15-minute data-loss target and four-hour restore target, including Auth/Vault and file-object consequences. Recommendation: keep these targets only if the staging evidence proves them.
3. **Rollback promise:** accept that automatic switch-back ends when writes reopen; after that point the response is forward-fix/reconciliation, not a connection-string flip. Recommendation: enforce a final pre-write acceptance gate and a named go/no-go owner.
4. **Ingress/admin access:** choose Cloudflare Tunnel/proxy or direct Caddy/Nginx, and approve a private Studio/admin access method. Recommendation: preserve the current Cloudflare edge path if it is stable, but prohibit public database, pooler, Studio, and Envoy-admin exposure.
5. **Monitoring independence:** accept Cloudflare Worker + Telegram as a low-cost pilot black-box monitor despite the Cloudflare common-mode risk, with host telemetry and a dead-man signal added. Recommendation: acceptable for the pilot, not equivalent to an independent monitoring provider.
6. **Staging and restore resources:** approve a genuinely separate staging/restore machine and the time/cost for recurring clean-machine restores. Recommendation: this is a launch gate, not optional polish.
7. **Queue architecture:** keep the application's existing PostgreSQL-backed asynchronous mechanisms for launch or authorize a separate Redis/BullMQ project. Recommendation: remove Redis/BullMQ from this launch plan unless current measured behavior proves it is needed.

Engineering can then choose WAL-G versus pgBackRest by the same evidence-based recovery spike, finalize the pinned release, and produce the exact port, secret, image, backup, deployment, migration, and test runbooks. None of those actions should start against production or customer data until the seven decisions above are recorded and the corrected plan is explicitly approved.
