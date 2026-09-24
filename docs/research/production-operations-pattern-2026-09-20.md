# Production operations pattern for the controlled pilot

**Research date:** 2026-09-20  
**Scope:** simplest robust operating model for the first, closely supported paying contractors.  
**Source rule:** current first-party documentation only. This note is research, not approval to change infrastructure.

## Recommendation

Use a **hybrid pilot**:

1. Run the SvelteKit app and only the required background workers on the planned VPS as immutable Docker images built in CI. Deploy a recorded image digest; do not build on the server.
2. Keep Postgres, Auth, PostgREST, Realtime, and Supabase control-plane responsibilities on the existing **managed Supabase project** during the controlled pilot.
3. Keep Cloudflare R2 external. Use separate, least-privilege credentials/buckets for customer objects and recovery artifacts; decide retention before launch.
4. Use the current Cloudflare edge path if it is stable. Cloudflare Tunnel can keep the VPS free of public inbound ports because `cloudflared` makes outbound-only connections. Use an external Worker for black-box HTTPS checks, but collect host/database/worker metrics separately.
5. Build and rehearse the official self-hosted Supabase Docker destination in a disposable staging/restore environment, without customer traffic. Cut over only after backup restore, clean-machine recovery, migration, rollback, security, and production-like workload gates pass.

This preserves the intended destination while avoiding making a non-expert owner operate a database platform and recovery system on day one. It also avoids an unnecessary database cutover before there is a measured reason to accept that risk.

## Why managed Supabase is the better pilot default

| Concern | Managed Supabase first | Self-hosted Supabase now |
| --- | --- | --- |
| Daily operations | Supabase operates the platform; the owner operates the app release and account settings. | The owner must provision, harden, update, monitor, back up, and recover the full stack. |
| Backups/PITR | Pro/Team/Enterprise projects receive daily backups; PITR can restore to a selected point with up-to-seconds granularity as an add-on. | No managed backups or PITR; the operator must design, run, alert on, and rehearse base backups plus WAL recovery. |
| Upgrades | Platform-managed service changes, subject to the managed product's maintenance behavior. | Supabase publishes tested Docker snapshots approximately monthly; individual service versions can be changed, but compatibility is not guaranteed. Breaking changes require an explicit rehearsal. |
| Failure domain | The database is outside the VPS failure domain; the app VPS is still one failure domain. | App, database, Redis/workers, and recovery tooling share the VPS unless separately hosted. |
| Cost/control | More recurring platform cost and less infrastructure control. | More control and potentially lower platform spend, but materially higher operator burden and recovery responsibility. |

Supabase explicitly says self-hosting transfers server maintenance, security hardening, service management, Postgres maintenance, backups/disaster recovery, monitoring, uptime, and scalability to the operator. Its Docker guide also says people new to these operations should start with the managed platform. [Supabase self-hosting](https://supabase.com/docs/guides/self-hosting), [Self-hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker)

Managed backup behavior still needs verification: daily backup retention depends on plan, restores make the project inaccessible during the restore, and the latest PITR point can lag during periods with no recent database activity. Keep a separate logical export and perform a restore test before launch; do not treat a dashboard backup toggle as the whole recovery proof. [Supabase database backups](https://supabase.com/docs/guides/platform/backups)

## Production operating pattern

### Application and worker releases

- CI builds and tests the app/worker image once, publishes it to the registry, and records the resulting digest and commit.
- The VPS pulls `image@sha256:...` and runs that exact artifact. Tags such as `latest` or a SHA-shaped tag are convenient labels, not the rollback identity; Docker and GitHub both document digests as the exact immutable image reference. [Docker image digests](https://docs.docker.com/dhi/explore/security-concepts/digests/), [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- Keep database migrations backward-compatible with the currently running app until the new image is proven healthy. An old image digest cannot undo a database migration.
- Do not add Redis/BullMQ solely because it appears in an old topology draft. Keep the existing asynchronous mechanisms for the pilot unless a measured workload or an approved design shows a queue is required; if a queue is introduced, it needs its own persistence, age/retry monitoring, and recovery test.

### Edge and monitoring

- Cloudflare Tunnel is a suitable low-operations ingress for the pilot: the connector makes outbound-only connections, so the VPS firewall can block inbound origin traffic. [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/), [Tunnel firewall model](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-with-firewall/)
- A Cloudflare Worker Cron Trigger is suitable for black-box reachability and a narrow authenticated readiness check. It does not independently know VPS disk, private Postgres health, worker age, or internal error rates. Add host/service telemetry and alerting for those signals.
- Keep the Cloudflare Worker + Telegram design explicitly as a pilot trade-off: the service path, R2, Tunnel, and watcher share Cloudflare as a possible common-mode dependency. Add a dead-man/heartbeat signal so a silent watcher is detectable. Cron changes can take up to 15 minutes to propagate. [Cloudflare Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)

### R2 and recovery state

- R2 is appropriate for external application objects and S3-compatible recovery storage. R2 is designed for eleven-nines annual durability, but durability does not prevent accidental or intentional deletion. [R2 durability](https://developers.cloudflare.com/r2/reference/durability/), [R2 S3 compatibility](https://developers.cloudflare.com/r2/get-started/s3/)
- Use bucket-scoped Object Read/Write credentials rather than account-wide credentials. [R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/)
- Protect backup prefixes/buckets with R2 Bucket Lock where the retention policy permits it. [R2 Bucket Locks](https://developers.cloudflare.com/r2/buckets/bucket-locks/)
- Database recovery does not restore R2 object bytes. Test the consistency of restored database rows and referenced objects separately; retain or copy objects long enough to support the selected recovery window.

## Self-hosted destination: prepare now, cut over later

When the pilot has a measured need for self-hosting, use Supabase's **official Docker distribution**, not `supabase start` (the CLI local-development stack is not hardened for production). Pin the complete tested snapshot and record `.supabase-version`; Supabase documents approximately monthly snapshots and warns that mixing individual service versions has no compatibility guarantee. Use the supported `update.sh` flow, review breaking changes, and test the exact target snapshot before promotion. [Self-hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker), [Update your self-hosted deployment](https://supabase.com/docs/guides/self-hosting/updating), [Self-hosted Docker changelog](https://github.com/supabase/supabase/blob/master/docker/CHANGELOG.md)

The self-hosted acceptance gate must include:

- a separate restore host and an off-host backup repository;
- a measured latest restore and time-target restore, including database, Auth, Vault/recovery secrets, app configuration, image digests, and proxy/firewall configuration;
- host, Postgres, WAL/archive, container, and worker metrics with alert delivery tested;
- a production-like workload and disk-growth test;
- a documented Supabase snapshot upgrade/rollback rehearsal.

## Migration and rollback boundary

Do not use an unfiltered raw `pg_dump` as the managed-to-self-hosted procedure. Supabase's official procedure exports roles, schema, and COPY-format data separately, filters Supabase internal schemas, restores in a single transaction, and then requires separate setup for JWT/API keys, providers, SMTP, DNS, Edge Functions, and Storage objects. Rehearse that procedure on a test self-hosted instance first. [Restore a platform project to self-hosted](https://supabase.com/docs/guides/self-hosting/restore-from-platform)

The rollback rule is two-phase:

- **Before writes reopen on the new database:** switching the app configuration back to managed Supabase is an acceptable emergency rollback after the target is stopped or isolated.
- **After writes reopen:** the managed source is stale. A blind connection-string switch would lose or fork new jobs, invoices, payments, users, and webhooks. Use a forward fix or a separately rehearsed reverse-sync/reconciliation procedure with an explicit loss policy. This is an operational inference from the one-way restore procedure and must be tested, not promised casually.

During the final cutover, pause API writes, background work, scheduled work, and inbound webhooks; run the final export/restore; verify counts and key journeys; then reopen traffic under a named go/no-go decision.

## Decision path

1. Approve the hybrid pilot pattern: Dockerized app/workers on the VPS, managed Supabase for the pilot database/Auth, external R2, and Cloudflare-based edge/black-box monitoring.
2. Keep the managed project as the source of truth while staging proves the self-hosted stack and recovery contract.
3. Set the pilot RPO/RTO only after the restore rehearsal measures them. If the result does not meet the target, do not cut over.
4. Revisit self-hosting after the pilot has a measured operational reason—cost, data-control/compliance, or a repeatable team runbook—not merely because the destination architecture exists.

## Primary sources consulted

- [Supabase self-hosting overview](https://supabase.com/docs/guides/self-hosting)
- [Supabase self-hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker)
- [Supabase update procedure](https://supabase.com/docs/guides/self-hosting/updating)
- [Supabase managed backups and PITR](https://supabase.com/docs/guides/platform/backups)
- [Supabase managed-to-self-hosted restore](https://supabase.com/docs/guides/self-hosting/restore-from-platform)
- [Supabase self-hosted Docker changelog](https://github.com/supabase/supabase/blob/master/docker/CHANGELOG.md)
- [Docker image digests](https://docs.docker.com/dhi/explore/security-concepts/digests/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Cloudflare Workers Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)
- [Cloudflare R2 durability](https://developers.cloudflare.com/r2/reference/durability/)
- [Cloudflare R2 S3 compatibility](https://developers.cloudflare.com/r2/get-started/s3/)
- [Cloudflare R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/)
- [Cloudflare R2 Bucket Locks](https://developers.cloudflare.com/r2/buckets/bucket-locks/)
