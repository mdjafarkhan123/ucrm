# Production Readiness Plan (CRM Launch Readiness — Part 9)

Status: **recommended for Jafar's approval; no infrastructure work is authorized by this document.**

This plan is for the controlled first launch: a few closely supported paying contractors. It deliberately uses
the smallest production shape that is safe for one owner/developer to operate. It does not claim support for
40,000 customers; wider capacity must be earned with a named workload and measured results.

## Recommendation in plain English

Launch the application on the planned VPS, but keep the database, Auth, Realtime, and Supabase platform on the
existing managed Supabase service during the controlled pilot.

This is the easiest robust option because a VPS failure can take down the application without also destroying
the database platform. Supabase continues operating database backups, platform upgrades, Auth, and Realtime
while Jafar learns one new production responsibility at a time: releasing and monitoring the application.

Self-hosted Supabase remains the intended later destination. Build and rehearse it in disposable staging first;
do not make the first paying customers depend on it until clean-machine recovery, upgrades, security, migration,
rollback, and production-like load have all been proven.

## Recommended controlled-pilot topology

| Area | Pilot choice | Why this is the smallest safe choice |
| --- | --- | --- |
| Application | SvelteKit Node server in one Docker container on the Hostinger VPS | One deployable application; no source build on the server |
| Application releases | GitHub Actions builds once, tests, publishes to GHCR, and records the image digest | The VPS pulls an exact immutable artifact; rollback uses the last known-good digest |
| Database and Auth | Existing managed Supabase project | Removes day-one database, Auth, Realtime, backup, and platform-upgrade operations from Jafar |
| Background work | Keep the existing Postgres `pg_cron`/`pg_net` wake pattern and internal application routes | It already exists and is tested; the separate `workers/` and Redis/BullMQ code is empty |
| Files | Existing external Cloudflare R2 | No file migration is needed for the pilot |
| Ingress | Existing Cloudflare Tunnel to the app container; no public VPS application/database ports | Keeps the origin private and matches the current working edge path |
| Monitoring | External Cloudflare Worker reachability check to Telegram, plus a small VPS health check for disk, containers, and worker freshness | External check detects a dead VPS; local check sees private host state |
| Recovery copy | Managed Supabase backups plus a tested encrypted logical export to a separate locked R2 backup bucket | Avoids relying on only one provider control while keeping the procedure understandable |

Do **not** add Redis, BullMQ, a worker fleet, Kubernetes, a database proxy, replicas, or high availability for the
pilot without measured evidence that the current shape cannot meet the workload. One VPS remains one application
failure domain; this is acceptable only for a closely supported pilot with tested recovery and clear customer
expectations.

## Reliability and recovery contract

The proposed goals are at most **15 minutes of database data loss** and service restoration within **4 hours**.
They remain targets—not promises—until the staging restore rehearsal measures them.

Before launch:

1. Confirm the managed Supabase plan and PITR/backup retention that can meet the target.
2. Produce an encrypted logical export into a separate R2 backup bucket using a bucket-scoped credential.
3. Protect recovery objects with an approved retention/Bucket Lock policy.
4. Restore onto a separate clean test project and verify Auth, tenant isolation, key CRM journeys, and row counts.
5. Test recovery of R2 application objects separately; a database restore does not restore object bytes.
6. Store the secrets inventory and recovery procedure outside the VPS. Never put secrets in Git, image layers,
   browser payloads, or monitoring responses.

The production database remains managed during the pilot, so there is no managed-to-self-hosted database
cutover in the launch path.

## Release and rollback contract

- Change the project from `adapter-auto` to the supported Node adapter.
- Build a multi-stage production image in CI. Run checks and the production build before publishing it.
- Deploy by `image@sha256:digest`, not `latest` and not only a movable Git-SHA tag.
- Keep the previous known-good digest recorded and immediately deployable.
- Make database migrations backward-compatible with the previous application image. An image rollback does not
  undo a database migration.
- Apply migrations as a separate, logged release step with a preflight and post-deploy smoke test.
- Never build the application or install development dependencies on the VPS.

## Monitoring and owner experience

Jafar should have one short status view/runbook, not a collection of infrastructure dashboards.

The minimum alerts are:

- the public application is unreachable or repeatedly unhealthy;
- the app container is restarting or stopped;
- VPS disk space or inode space is approaching the stop threshold;
- an expected background job is stale or repeatedly failing;
- database backup/export or restore verification is stale;
- application error rate crosses the tested alert threshold.

Telegram alerts must be deduplicated and must send a recovery message. The external Cloudflare check covers total
VPS failure; the local health check covers disk and private container state. A dead-man heartbeat must reveal when
the monitor itself stops running. Logs must be rotated so they cannot fill the VPS.

## Staged delivery and approval gates

### P9A — approve the operating shape

Jafar approves or changes the topology, pilot recovery targets, one-VPS limitation, and staged spending. No
infrastructure is provisioned before this gate.

### P9B — package the application

Add the Node adapter, production Dockerfile, health/readiness contract, CI checks, GHCR publishing, digest-based
release, and rollback instructions. Completion: the same image runs locally and in disposable staging, contains
no secrets, and can roll forward/back between two compatible releases.

### P9C — build disposable staging

Use a separate VPS or temporary clean machine with the production container, Cloudflare path, firewall, secrets
shape, and monitoring. It may use a separate Supabase test/staging project. Completion: a fresh operator can
deploy from the runbook without undocumented steps.

### P9D — prove recovery and operations

Test backup/export, clean-project restore, R2 object recovery, credential rotation, monitoring alerts, a dead VPS,
full disk warning, container restart, and a failed background job. Completion: measured recovery meets the
approved target and Jafar can follow the short runbook.

### P9E — close launch security and abuse controls

Rotate production credentials, prove private origin/network exposure, audit public endpoints and webhook
validation, and complete the shared authenticated rate-limit policy needed before wider traffic. Completion:
security checks and tenant/role tests pass without exposing administrative services or secrets.

### P9F — measure the actual pilot workload

Write the workload before running k6: tenant count and skew, staff and active sessions, database size, expected
read/write mix, bursts, Realtime connections, background arrival rate, provider limits, and important journey
latency/error targets. Run smoke, average, stress, spike, soak, backup-overhead, and bounded fault tests from
outside the VPS.

Report only the tested workload, duration, latency percentiles, errors, resource use, database connections,
background age, and recovery behavior. If the measured workload fails, fix that specific bottleneck and retest;
do not add speculative infrastructure.

### P9G — controlled launch

Deploy the proven digest, verify key Lead → Request → Quote → Job → Invoice → Payment journeys, admit only the
named pilot contractors, watch alerts and background queues closely, and keep a written go/no-go owner and
rollback step. Wider rollout waits for customer evidence and another capacity/security review.

## Later self-hosted Supabase gate

Self-hosting is a separate migration after the pilot—not part of the simplest pilot launch. Before proposing
cutover:

- use Supabase's official self-hosted Docker distribution, never `supabase start`;
- pin and test one complete official snapshot rather than mixing service versions;
- prove latest and time-target database recovery on a separate blank host, including Auth and the Vault root key;
- prove host, Postgres, WAL/archive, container, and job monitoring;
- rehearse Supabase's supported roles/schema/COPY-data migration, not a raw unfiltered `pg_dump`;
- pause writes, schedules, workers, and inbound webhooks during the final copy;
- allow connection-switch rollback only before writes reopen on the new database;
- after writes reopen, use a rehearsed forward-fix/reconciliation process rather than switching blindly to a
  stale managed database;
- pass production-like load, disk-growth, upgrade, rollback, and failure tests.

That cutover requires a new explicit approval because it materially increases Jafar's operating responsibility
and changes the production failure domain.

## Performance design verdict

```text
Performance Design – controlled pilot production path
Growth path       : active sessions, API/database traffic, Realtime connections, background arrivals,
                    stored rows/objects, logs, and backup volume
Workload contract : not yet established; P9F must name the pilot tenants, usage mix, bursts, and targets
Chosen shape      : one immutable app container on one VPS, managed Supabase, external R2, existing DB-driven jobs
Complexity cost   : CI image publishing, two small health checks, tested logical recovery copy; no new queue/cache
Rejected options  : self-hosting Supabase before pilot, Redis/BullMQ, replicas, Kubernetes, and speculative HA
Failure behavior  : app outage alerts externally; database remains outside the VPS; digest rollback; tested restore
Verification plan : P9B–P9F build, recovery, security, workload, soak, and bounded failure evidence
Open decisions    : Jafar approves the hybrid pilot, RPO/RTO targets, one-VPS limit, and staging cost
Overall           : Blocked by Jafar's explicit P9A approval
```

## Evidence

- `docs/research/production-readiness-validation-2026-09-18.md` — corrections required in the earlier draft.
- `docs/research/production-operations-pattern-2026-09-20.md` — current primary-source support for the hybrid
  managed-first pilot and later self-hosted destination.
