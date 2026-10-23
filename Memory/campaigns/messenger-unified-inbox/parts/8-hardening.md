# Part 8 — Hardening and performance

**State:** Verified, waiting to merge `codex/messenger-part8` from `.worktrees/messenger-part8`.
**Claims:** source `0e673be6bb0a`, integration `1e04b3d888c8` (main reserved).

**Built:** hourly token/permission/subscription checks, six Pages per cron wake, three concurrent checks, oldest due
first. Conditional claims avoid duplicate checks; stale completion cannot overwrite reconnect/disconnect. Only
confirmed failures set existing reconnect reasons; temporary Facebook or credential-decryption problems wait for
the next check. Existing reconnect flow restores subscriptions. Fixed the existing phone Settings layout and
misleading automatic-reconnect sentence. Fixed duplicate Messenger login-session and missing echo/receipt types.

**Proof:** `docs/evidence/messenger-part8/README.md`, screenshots, SQL rollback checks. Messenger suites 81 passed;
focused type check and ESLint passed; actual test Page health passed (read-only). Performance verdict supports
bounded checks; numerical service capacity remains unverified. App-level callback auto-disable with an intact
Page subscription needs dashboard recovery proof in Part 9/10.

**Migration:** CLI created the file, then its version was moved after the repo's existing future-dated migrations:
`20270104090000_messenger_connection_health.sql`. Creation and claims tested in a rolled-back transaction; not yet
applied persistently. No auth/RLS or credential changes.

**Next:** merge current main into branch, commit/push, merge into main, apply/record migration once with project
psql recipe, prove the due-check cron wakes with no messages, restore the preserved local tool config from stash
(hash in `/tmp/messenger-part8-config-stash-id`), push and release claims. Then Part 9 live walkthrough.
