# Deferred sweep 2 — now

**Goal:** Clear the nine deferred tasks that are ready now (approved by Jafar 2026-09-29).
**Plan:** each part's note in `Memory/deferred/` is its spec; delete the note and its INDEX row when fixed.

**In progress:** none

**Next part:** 5 Address names — drop the "Primary property" default label (`properties.label`, client
create) so an unnamed address shows its street alone, like Jobber; clean up existing rows carrying the
fake label. The "Main" badge is the only thing that should say primary.

**Blockers:** none. Do not touch packages or Delete client (Jafar: "not now"). The CLI runs as
`npx --no-install supabase`. Browser testing: tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`,
or headless Playwright against `localhost:5173` (wait ~8 s on a login page before submitting). The script
must sit in the project folder to find Playwright. The owner login is often rate-limited (10 tries / 15 min);
the office test login works. Full `svelte-check` needs `NODE_OPTIONS=--max-old-space-size=12288`.
