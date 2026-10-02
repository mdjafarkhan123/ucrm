# Concurrent agent work

This repository may have several independent terminal sessions. Campaign Memory records durable progress;
the local reservation register records who is working **now**. Run `python3 .claude/skills/agent-coordination/scripts/agent-work.py list` before
choosing any task, including work outside a campaign. The register lives in the main worktree's ignored
`.agent-work/` directory and is shared by linked worktrees on this machine. Its claim operation is atomic.

## Choose and reserve

1. Name the campaign and task. For "start an available task," read that campaign's `ROADMAP.md`, check
   dependencies and its `NOW.md`, and choose a part that can progress independently. Inspect current Git
   changes and active reservations. Separate campaigns may still touch the same code or external service.
2. Decide whether this session only reads (`read`) or will change anything (`write`). Name every broad area
   it may change or operate on, including shared services such as `remote-db`, `migrations`, `package`,
   `Memory/INDEX.md`, or the affected feature domain. Use `--area '*'` when the scope is uncertain. Areas
   are planning boundaries, not a guarantee that files cannot overlap.
3. Reserve before work starts. Example:

   ```bash
   python3 .claude/skills/agent-coordination/scripts/agent-work.py claim deferred-launch-sweep part-4d --owner codex-tab-2 --mode write --area invoices --area migrations
   ```

   Keep the returned ID. The command refuses a second claim on the same task, a second writer in one
   worktree, or a writer with an overlapping area. If it refuses, pick a genuinely independent task or wait.
   If the scope grows, add areas atomically with `expand <reservation-id> --area <area>` before touching them.
4. A dirty worktree with no matching claim may belong to another terminal. Stop and identify its owner.
   `--adopt-existing` is only for changes positively identified as this session's own work; it does not
   override another active claim. Never remove or overwrite unknown changes.

## Workspaces and shared effects

One writer may work in the main folder on `main`. Simultaneous code writers use separate temporary Git
worktrees and branches, each with its own reservation. The user has authorized this exception for
concurrent work; it does not create a second product. Keep the main folder as the final application.
Git worktrees isolate files, but they do not isolate remote Supabase, R2, external providers, ports, or
local databases. A worktree's `node_modules` is a link to the main folder's; Vite keeps its library cache
in each checkout's own ignored `.vite/` (`cacheDir` in `vite.config.ts`) so a worktree's dev server or
test run cannot break the main dev server. Keep it that way. Reserve those resources explicitly and coordinate destructive or irreversible actions.

Only one integrator brings completed changes into `main` at a time. The integrator checks all affected
changes together, resolves conflicts, verifies the combined result, and commits the completed work.
An agent commits only its own paths; it does not sweep unrelated dirty files into a commit. Update campaign
checkpoints after integration so they describe the state actually present on `main`.

## Finish and recover

Release a reservation after the work is safely integrated and its checkpoint is updated. For a temporary
branch, the integrator releases its claim after bringing the change into `main`:

```bash
python3 .claude/skills/agent-coordination/scripts/agent-work.py release <reservation-id>
```

Reservations never expire automatically. If an agent stops unexpectedly, inspect its terminal, Git
changes, worktree, commits, and any external operation before releasing its ID. A missing process or an old
timestamp alone does not prove that work is safe to reassign. The register is local to this machine; agents
on other machines need a shared coordination service before they can write concurrently.
