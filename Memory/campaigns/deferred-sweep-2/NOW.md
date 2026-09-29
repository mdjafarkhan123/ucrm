# Deferred sweep 2 — now

**Goal:** Clear the nine deferred tasks that are ready now (approved by Jafar 2026-09-29).
**Plan:** each part's note in `Memory/deferred/` is its spec; delete the note and its INDEX row when fixed.

**In progress:** Part 7 — uncommitted work-in-progress sitting in the working directory from another session
writing concurrently in the main folder. See `parts/part-7-client-work-schedule.md` before touching any file
it lists — check `git status` fresh and confirm that session has stopped first.

**Next part:** 7 Client work + schedule — fill the client page's empty Work overview and Client schedule boxes
with the client's real work (spec: `Memory/deferred/client-work-overview-and-schedule-sections-are-empty.md`).

**Blockers:** none. Do not touch packages or Delete client (Jafar: "not now"). The CLI runs as
`npx --no-install supabase`. Browser testing: tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`,
or headless Playwright against `localhost:5173` (wait ~8 s on a login page before submitting). The script
must sit in the project folder to find Playwright. The owner login is often rate-limited (10 tries / 15 min);
the office test login works. Full `svelte-check` needs `NODE_OPTIONS=--max-old-space-size=12288`.
