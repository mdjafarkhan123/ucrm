# Deferred sweep 2 — now

**Goal:** Clear the nine deferred tasks that are ready now (approved by Jafar 2026-09-29).
**Plan:** each part's note in `Memory/deferred/` is its spec; delete the note and its INDEX row when fixed.

**In progress:**

- 1 Quote API tests — mock the rate limit in the quote specs

**Next part:** 2 Jobs and Quotes search by client name

**Blockers:** none. Do not touch packages or Delete client (Jafar: "not now"). The CLI runs as
`npx --no-install supabase`. Browser testing: tunnel `cloudflared tunnel run badf2c43-7020-443a-a046-9954d139d711`,
or headless Playwright against `localhost:5173` (wait ~8 s on a login page before submitting).
