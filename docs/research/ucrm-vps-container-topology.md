# UCRM VPS container topology

Research date: 2026-08-28

## Question

What is the smallest proven production topology for UCRM when the SvelteKit app, background workers,
Redis, and self-hosted Supabase will ultimately run as containers on a VPS, while leaving a safe path
from launch to higher availability?

## Verdict

Use **one deliberately bounded Docker Compose host as the launch tier**, but do not call it highly
available or sized for 40,000 users. A registered-user count does not reveal simultaneous sessions,
requests per second, database writes, Realtime connections, email/SMS fan-out, tenant skew, or burst
duration. Those measurements—not the account count—must choose the VPS and worker concurrency.

The final single-VPS shape should be:

```text
Internet
   |
Caddy: only public ports 80/443, automatic TLS
   |-- app.ucrm.example ------> SvelteKit app container(s)
   `-- api.ucrm.example ------> Supabase Envoy API gateway

private Docker networks
   |-- operational worker ----> Supabase API/RPC + Brevo + R2
   |-- future automation worker -> Postgres truth + Redis dispatch
   |-- Redis (never public)
   `-- official self-hosted Supabase stack
         |-- Auth / PostgREST / Realtime / Storage / Studio / Supavisor
         `-- PostgreSQL (never public)

off-host
   |-- Cloudflare R2 objects
   |-- encrypted Postgres base backups + continuous WAL archive
   `-- external monitoring/alerts
```

This is a sound **launch and restore** design, not an HA design. If the VPS, its disk, network, or
Docker daemon fails, the application and database fail together. Off-host backups make recovery
possible; they do not make the service continuously available.

Do not move every layer in one release. First package and prove the app/worker containers against the
current managed Supabase project. Separately build and rehearse the self-hosted Supabase restore, then
perform a controlled database cutover. The desired final state is still all containers on the VPS; the
staging separates two unrelated failure risks.

## Why this is the proven smallest shape

Supabase itself recommends its official Docker Compose distribution for self-hosting, but explicitly
makes the operator responsible for security, Postgres maintenance, backups, disaster recovery,
monitoring, scalability, and high availability. Its CLI development stack is not production-hardened.
The current baseline is 4 GB RAM/2 CPU/40 GB SSD minimum and 8 GB+/4 CPU+/80 GB+ SSD recommended for
the Supabase components alone. Therefore, `8 GB` is not a justified UCRM production size after adding
the app, workers, Redis, proxy, backups and monitoring; choose the actual host from a staging load test
with headroom. [Supabase self-hosting overview](https://supabase.com/docs/guides/self-hosting),
[Docker system requirements](https://supabase.com/docs/guides/self-hosting/docker#system-requirements)

Keep UCRM's Compose project separate from the versioned upstream Supabase Compose project. Join only
the required services to explicit external networks. This preserves Supabase's supported update path
instead of turning its many-service stack into a custom UCRM file. Supabase now publishes versioned
self-host releases and an incremental update script; that script backs up configuration but **not**
Postgres or Storage data, so every update needs an independent data backup and staging rehearsal.
[Supabase Docker installation](https://supabase.com/docs/guides/self-hosting/docker),
[self-hosted updates](https://supabase.com/docs/guides/self-hosting/updating)

Pin UCRM images to an immutable release identifier and pin Supabase to a tested self-host release. Do
not follow `latest` or update individual Supabase services casually: Supabase says its snapshot's images
are tested together and compatibility is not guaranteed for independently chosen versions. Current
self-hosting has material breaking changes that make pinning important: Postgres 17 cannot read an old
Postgres 15 data directory, and Envoy has replaced Kong as the default API gateway.
[Supabase Docker update policy](https://supabase.com/docs/guides/self-hosting/docker#updating),
[Postgres 17 self-host change](https://supabase.com/changelog/46080-self-hosted-supabase-upgrading-from-pg-15-to-17-breaking-change),
[Envoy gateway change](https://supabase.com/changelog/48048-self-hosted-supabase-envoy-becomes-the-default-api-gateway-b)

## Service and security boundaries

- Use SvelteKit's official `adapter-node` to create the standalone Node server. The repository currently
  uses `adapter-auto` and has no production container definition, so packaging is real implementation
  work. Configure the public origin/trusted proxy headers, body limit, health endpoint, and graceful
  shutdown. Adapter Node waits for active requests on `SIGTERM`/`SIGINT`; the worker needs equivalent
  stop-claiming/drain-in-flight behavior. [SvelteKit adapter-node](https://svelte.dev/docs/kit/adapter-node)
- Use Caddy as the one ingress because Supabase ships a Caddy override and documents it as the simplest
  automatic-TLS option. It must proxy WebSockets for Realtime and forward trusted headers. Publish only
  `80/443`; do not publish Redis, Postgres, Supavisor, the raw API-gateway port, or Studio administration.
  Reach administration through a VPN/SSH tunnel or a strict allow-list.
  [Supabase HTTPS proxy guide](https://supabase.com/docs/guides/self-hosting/self-hosted-proxy-https)
- Do not rely on Ubuntu `ufw` alone for published Docker ports: Docker documents that published-container
  traffic is diverted before `ufw`'s normal chains. Avoid unnecessary port mappings and enforce any
  additional filtering in Docker-aware firewall rules.
  [Docker packet filtering](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
- Keep secrets out of images, Git, browser variables and logs. Grant each service only its own secret.
  Compose can mount per-service secret files, while Supabase recommends a production secrets manager;
  a root-owned, permission-restricted deployment file is only the minimum single-host fallback.
  [Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/),
  [Supabase secret management](https://supabase.com/docs/guides/self-hosting/docker#managing-your-secrets)
- Add readiness health checks, dependency conditions and restart policies. Set measured CPU/memory
  boundaries so one worker or analytics service cannot exhaust the database host; Docker containers have
  no resource constraints by default. Use rotated container logging—the Docker `local` driver rotates by
  default—so logs cannot silently fill the only disk.
  [Compose startup order](https://docs.docker.com/compose/how-tos/startup-order/),
  [Docker resource constraints](https://docs.docker.com/engine/containers/resource_constraints/),
  [Docker logging](https://docs.docker.com/engine/logging/configure/)

## Postgres and Supabase connection contract

Keep normal app and worker operations on the existing Supabase HTTP API/RPC path through the internal
gateway. That means browser and Node traffic does not create one direct Postgres connection per request.
Do not expose Postgres to the Internet.

Use a direct private Postgres connection only for migrations, backup/restore, or a demonstrated backend
need. If a future persistent service uses a Postgres driver, choose Supavisor deliberately:

- session mode (`5432`) for persistent clients that need session features such as `LISTEN/NOTIFY`,
  advisory locks or session settings;
- transaction mode (`6543`) for many short-lived connections, accepting that session-level features and
  Supavisor prepared statements are unavailable there;
- direct private connection for migrations and backup utilities.

The pool is not free capacity. Supabase's default self-host settings are a pool size of 20 and 100 client
connections; backend connections from Supavisor plus direct connections and Supabase's own services must
remain below Postgres `max_connections`. Tune from measured peak connections and pool wait, not user
count. [Self-hosted Postgres access](https://supabase.com/docs/guides/self-hosting/accessing-postgres),
[Supabase connection management](https://supabase.com/docs/guides/database/connection-management)

R2 should remain the object system already chosen by UCRM. A database restore does not transfer Storage
objects, provider secrets, auth-provider configuration, SMTP configuration, DNS, or Edge Functions;
these need their own migration inventory and verification. A managed-to-self-host restore may also
invalidate existing JWTs, so the cutover plan must deliberately test re-authentication.
[Supabase platform-to-self-host restore](https://supabase.com/docs/guides/self-hosting/restore-from-platform)

## Redis contract

Redis does **not** become UCRM's business ledger merely because it is installed:

| Responsibility | Decision |
| --- | --- |
| Operational and quote email | **No.** The existing Postgres outbox remains the durable queue and atomic claim/finalize authority. |
| Automation definitions, runs, action results and next-due state | **No.** Store durable workflow truth and idempotency in Postgres. |
| Future Automation dispatch/delays | **Conditional yes.** BullMQ/Redis may carry small execution hints after a Postgres commit when sub-minute scheduling, burst smoothing or distributed workers earn it. A reconciler must redispatch due Postgres work after Redis loss. |
| Short-lived rate limits, leases, debounce or coordination | **Yes when a named path needs them.** Losing Redis must degrade or rebuild safely. |
| General caching | **No by default.** Add a tenant-scoped TTL cache only after an expensive repeated read is measured. |
| Sessions/auth/customer records/provider callbacks | **No.** Supabase/Postgres remains authoritative. |

If BullMQ is introduced, configure a dedicated queue Redis with a named volume, AOF persistence,
periodic RDB backups, authentication/ACLs, an explicit memory ceiling and `noeviction`. BullMQ warns
that arbitrary Redis eviction breaks queues and recommends AOF; Redis recommends RDB+AOF when stronger
data safety is wanted. Never expose port `6379`. If UCRM later needs an evicting cache, use a separate
Redis instance because a cache policy such as `allkeys-lru` conflicts with a queue's `noeviction` policy.
[BullMQ production guidance](https://docs.bullmq.io/guide/going-to-production),
[Redis persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/),
[Redis security](https://redis.io/docs/latest/operate/oss_and_stack/management/security/),
[Redis cache configuration](https://redis.io/docs/latest/operate/oss_and_stack/management/config/)

Redis/BullMQ execution remains at-least-once in the worst case, so every externally visible action needs
a Postgres idempotency key and retry-safe state transition. Redis persistence reduces loss; it does not
remove duplicate execution or the Postgres-to-Redis dual-write gap.
[BullMQ semantics](https://docs.bullmq.io/),
[idempotent jobs](https://docs.bullmq.io/patterns/idempotent-jobs)

## Backup and disaster-recovery gate

Production is blocked until a restore—not merely a backup—has passed on a clean machine.

1. Agree business targets for maximum tolerable data loss (RPO) and recovery time (RTO).
2. Archive WAL continuously to encrypted off-VPS storage and take scheduled physical base backups.
   Keep multiple generations. PostgreSQL's continuous-archive method is what enables point-in-time
   recovery; `pg_dump` alone cannot do that.
3. Also retain periodic Supabase-aware logical dumps for portability and targeted inspection. Back up
   deployment configuration, signing/encryption keys, migrations and a manifest of external R2 objects.
4. Monitor the last successful base backup and WAL archive age. At a fixed cadence, restore to a clean
   isolated host, replay to a chosen timestamp, run schema/row/auth checks, and record the achieved RPO
   and RTO. `pg_verifybackup` helps validate a base backup, but it does not replace a restore drill.
5. Keep backup credentials separate from the runtime credentials and keep at least one copy outside the
   VPS failure domain.

[PostgreSQL continuous archiving and PITR](https://www.postgresql.org/docs/current/continuous-archiving.html),
[`pg_verifybackup`](https://www.postgresql.org/docs/current/app-pgverifybackup.html),
[PostgreSQL logical dumps](https://www.postgresql.org/docs/current/backup-dump.html)

## Staged delivery and rollback

1. **Define the workload and service promise.** Record simultaneous sessions, peak API reads/writes,
   Realtime sockets/events, database size/growth, busiest-tenant skew, communication recipients per burst,
   acceptable request latency, queue completion time, RPO and RTO.
2. **Package without changing the database.** Add `adapter-node`, a multi-stage non-root app image, a
   separate worker command/image, health endpoints, graceful shutdown, structured redacted logs and a
   production Compose overlay. Keep Redis disabled until an approved responsibility uses it.
3. **Build a production-like staging VPS.** Install a pinned official Supabase self-host release in its
   own Compose project, restore a scrubbed/current snapshot, configure Caddy, secrets and off-host backups,
   then run correctness, restart, provider-failure and load scenarios.
4. **Deploy app/worker first against managed Supabase.** Build immutable images in CI, tag by commit,
   scan/test, push to a registry, pull by digest, run migrations as an explicit one-shot step, and retain
   the previous image/config. This proves container networking and lifecycle independently of data move.
5. **Rehearse and execute the Supabase cutover.** Test version/extensions, auth, RLS, Realtime, Cron,
   Storage/R2, callbacks and rollback; schedule a write freeze, take the final dump, restore, verify, switch
   URLs/DNS, and keep the old project untouched until the rollback window closes.
6. **Release safely.** Use backward-compatible expand/migrate/contract schema changes so the previous app
   can run during rollback. Health-check the new app before traffic, stop workers from taking new claims,
   drain in-flight work, and never roll back a database destructively to match old code.
7. **Ramp and observe.** Start with bounded app/worker concurrency and provider limits, then increase only
   against measured latency, error rate, connection use, disk I/O and oldest-work age.

Docker documents production-specific Compose overlays and service recreation; this remains a single-server
deployment mechanism, not a multi-host orchestrator.
[Docker Compose in production](https://docs.docker.com/compose/how-tos/production/)

## Observability and exit thresholds

Send alerts off-host. At minimum collect host/disk/inode pressure, container health/restarts, public uptime,
app request rate/latency/errors, Postgres CPU/I/O/locks/connections/slow queries, Supavisor clients and pool
wait, WAL/archive and backup age, Redis memory/evictions/AOF status/latency, and worker backlog oldest age,
attempts, unknown outcomes and per-tenant skew. Supabase's optional Logflare/Vector overlay is resource-heavy
and not required for Auth, Storage, PostgREST or Realtime, so enable it only after sizing or use a lighter
external log path. [Supabase logs overlay](https://supabase.com/changelog/46084-self-hosted-supabase-making-analytics-and-vector-opt-in)

Split or add machinery when a requirement or measurement crosses a boundary:

- add stateless app replicas when request CPU/latency or release availability requires them;
- add worker replicas when oldest-due age misses its target and Postgres/provider capacity remains healthy;
- move Postgres to a dedicated host first when database I/O/memory competes with app/Redis, maintenance or
  backup blocks the product, or the accepted RTO no longer permits rebuilding the whole VPS;
- add a Postgres standby in a different failure domain only with a tested failover/failback runbook;
  streaming replication is asynchronous by default and can lose the unreplicated tail on failover;
- move Redis off-host when it becomes operationally critical or resource-heavy. Real Redis HA requires a
  primary/replicas and at least three Sentinels on independently failing machines—not three containers on
  one VPS—and even Sentinel does not guarantee every acknowledged asynchronous write survives failover;
- move from single-host Compose to multi-host orchestration or managed stateful services when the business
  uptime target requires surviving a host/zone failure. Do not wait for CPU exhaustion to make that decision.

[PostgreSQL standby replication](https://www.postgresql.org/docs/current/warm-standby.html),
[Redis Sentinel](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)

## Performance design verdict

```text
Growth path       : sessions/requests -> API/Auth -> Postgres; queued work -> workers -> providers;
                    Realtime sockets/events; data/WAL/backups; Redis dispatch keys
Workload contract : unknown beyond about 40,000 registered users; concurrency, rates, skew, bursts,
                    retention, RPO and RTO must be measured/decided before capacity claims
Chosen shape      : one isolated Compose launch host, official pinned Supabase stack, Postgres truth,
                    bounded workers, optional Redis dispatch, Caddy ingress, off-host PITR backups
Complexity cost   : proxy, separate app/Supabase Compose projects, worker lifecycle, backup pipeline,
                    monitoring; Redis only when Automation gives it a named responsibility
Rejected options  : Redis as a second email ledger; public DB/Redis; all-at-once app+DB cutover;
                    same-host replicas presented as HA; premature Kubernetes/Sentinel
Failure behavior  : one host outage stops the product; restore from off-host backup; idempotent worker
                    recovery; bounded pressure; no blind retry of ambiguous provider outcomes
Verification plan : production-like load by tenant skew, connection/pool evidence, queue drain time,
                    provider limits, container restart/kill tests, full clean-host restore and cutover drill
Open decisions    : business RPO/RTO and maintenance tolerance (Jafar); measured workload and host sizing
                    (engineering); Redis activation at Automation design gate
Overall           : Ready as a staged launch design; production remains blocked until restore and load gates pass
```

