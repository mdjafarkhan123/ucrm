# Production release runbook (P9B)

How the app is packaged and moved between releases. Plain English first, commands second. This covers the app
container only; the server, firewall, monitoring and recovery come in P9C–P9D (`docs/production-readiness-plan.md`).

## The idea

Every push to `main` makes GitHub build **one sealed copy of the app** (a Docker image), run the checks, and file it
in GitHub's image storage (GHCR). Each copy has a unique fingerprint called a **digest** (`sha256:…`). The server
never builds anything; it only runs a copy by its fingerprint. Rolling back means running the previous fingerprint.

The image holds **no secrets**. Only the browser-safe `PUBLIC_*` values are baked in; every private key is handed to
the container when it starts.

## One-time GitHub setup (Jafar)

Repository → Settings → Secrets and variables → Actions → **Variables** tab, add three values copied from `.env`:
`PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `PUBLIC_MAPBOX_TOKEN`. They are public by design (they
already reach every visitor's browser). Until they exist, the "Release image" run stops at the build step.

## Finding the copy to deploy

GitHub → Actions → "Release image" → the run → Summary. The last line is `ghcr.io/…@sha256:…`. That whole line is
what you deploy. Never deploy a movable name such as `latest`.

## Starting a copy

```bash
docker run -d --name ucrm --restart unless-stopped -p 127.0.0.1:3000:3000 \
  --env-file /etc/ucrm/app.env <the ghcr.io/…@sha256:… line>
```

`/etc/ucrm/app.env` holds the private settings (same names as `.env.example`), readable only by the server's admin
user, never in Git. It must also contain:

| Setting          | Value                                  | Why                                                                             |
| ---------------- | -------------------------------------- | ------------------------------------------------------------------------------- |
| `ORIGIN`         | `https://app.upliftcontractor.com`     | SvelteKit rejects form posts when it cannot tell its own public address         |
| `ADDRESS_HEADER` | `CF-Connecting-IP` (behind the Tunnel) | Without it every visitor shares one address and every per-address limit is one bucket |

If `ADDRESS_HEADER` is set but the request does not carry that header, sign-in fails with a server error (the app
refuses to guess an address). Set it only where the Tunnel really adds the header, and check by signing in once.

The app listens on port 3000 inside the container and is published only to the server's own loopback, so the
Cloudflare Tunnel is the only way in.

## Is it healthy?

- `/api/health` — "the app is running". Needs nothing else. Docker checks this itself every 30 seconds.
- `/api/health/ready` — "the app can also reach its database". Run it after every deploy:
  `curl -fsS http://127.0.0.1:3000/api/health/ready` must print `{"status":"ready"}`.

## Rolling forward and back

1. Note the fingerprint currently running (`docker inspect ucrm --format '{{.Config.Image}}'`) — that is the
   **known-good** one. Keep it written down.
2. `docker pull` the new one, then `docker rm -f ucrm` and start it as above. Check `/api/health/ready`.
3. If it misbehaves, remove it and start the known-good fingerprint the same way.

An image rollback does **not** undo a database change. So every migration must work with both the old and the new
app copy (add before you remove; never rename in one step). Apply migrations as their own logged step, before the
new copy starts, using the `psql` procedure in `CLAUDE.md`.

## What was proven in P9B

On 2026-10-10 the production build (`npm run build`, then `node build`) ran on its own and a contractor signed in,
reached the dashboard, Clients and Jobs; both health routes answered. The Docker image build itself runs only in
GitHub: Docker is not installed on the development computer, so the first Actions run is the first real image
build, and the "rolls forward and back between two releases" gate is proven on the practice server (P9C).
