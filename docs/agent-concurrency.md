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
   it may change or operate on, including shared services such as `remote-db`, `migrations`, `package`
   or the affected feature domain. Reserve a campaign's Memory under that campaign's area; a change to
   Memory's shared structure belongs to `agent-workflow`. Independent branches may edit their own index
   rows, with reconciliation at integration. Use `--area '*'` when the scope is uncertain. Areas are
   planning boundaries, not a guarantee that files cannot overlap.
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

Main is the integration workspace, with one writer at a time. New campaign and feature writers use separate
temporary Git worktrees and branches, each with its own reservation, including planning and documentation
writers. Existing claimed work in main may finish there before integration resumes.
Jafar approved this policy on 2026-10-12. Create branches with the `codex/` prefix from the latest committed
`main`, or an explicitly required dependency branch. A worktree starts with committed files; another
writer's unfinished changes remain in their workspace. Keep the main folder as the final application.
Git worktrees isolate files, but they do not isolate remote Supabase, R2, external providers, ports, or
local databases. A worktree's `node_modules` is a link to the main folder's; Vite keeps its library cache
in each checkout's own ignored `.vite/` (`cacheDir` in `vite.config.ts`) so a worktree's dev server or
test run cannot break the main dev server. Keep it that way. Reserve those resources explicitly and coordinate destructive or irreversible actions.

## Checkpoints and merge cadence

Commit coherent checkpoints and push the branch before handoff or ending a session. Save plans and campaign
Memory in that same worktree, including approved decisions. A pending checkpoint names the branch/worktree,
checks completed, remaining work and **Waiting to merge** status. Main's Memory remains the integrated record.
This lets planning continue while another writer occupies main.

Merge a small complete delivery once its required checks and approvals pass and the main integration slot
is available. Aim for task/session-sized deliveries; split multi-day work into independently checkable
deliveries where possible. Use readiness rather than a fixed hourly or daily timer. Push unfinished work
for recovery without calling it integrated. A campaign need not finish before its ready portions merge;
incomplete features stay behind their approved private/disabled boundary.

Only one integrator brings completed changes into `main` at a time. Before integrating, check the register
and acquire a write claim in the main workspace for the integration task. Wait while another writer holds
main or has unfinished changes there. Keep the source branch's reservation; use a separate nonoverlapping
`main-integration` area for the integrator's workspace claim. This extra claim serializes the merge; the
source claim continues to protect its actual feature areas.

Update the branch against current main, reconcile shared records, resolve conflicts, and rerun checks
appropriate to the combined change. Review the final diff, merge, update checkpoint status to reflect the
integrated state, and push main. An agent commits only its own paths. Release the source and integration
claims after successful integration/checkpoint; remove temporary worktrees/branches only after their
needed work is integrated and recoverable remotely. If integration or push fails, preserve the workspace
and report the exact remaining step.

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

For a missing reservation or a stale main checkpoint, inspect the campaign's pushed branches, attached
worktrees and Git history before starting duplicate work. Verify branch progress against current main;
recover its checkpoint and claim its remaining task before continuing. Never discard pending branch Memory
solely because main has an older copy.
