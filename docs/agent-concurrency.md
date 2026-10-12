# Concurrent agent work

Agents can work together when each owns a clear task and uses a separate working folder.
A Git **branch** keeps its changes separate. A **worktree** provides that branch's working folder.
**Merge** means combining completed changes into `main`, the final application.

## Choose and reserve work

1. Read the campaign's current note and check dependencies. Run:
   `python3 .claude/skills/agent-coordination/scripts/agent-work.py list`
   Inspect unfinished files and existing reservations before choosing a task.
2. Reserve the exact campaign/task before starting; use `standalone` for work outside a campaign.
   Choose `read` for inspection or `write` for changes. Name every affected feature and shared resource:
   database, migrations, dependencies or external services. Use `--area '*'` if scope is uncertain.
3. Claim from the workspace where you will work:

   ```bash
   python3 .claude/skills/agent-coordination/scripts/agent-work.py claim campaign task --owner session-name --mode write --area invoices
   ```

   Keep the returned ID. The command prevents duplicate tasks, two writers in one workspace,
   and writers with overlapping areas. If refused, choose independent work or wait.

4. Check actual dependencies too: different campaign names do not prove independence.
   Before adding scope, run `expand <id> --area <area>`.
   Use `--adopt-existing` only for unfinished files positively identified as your own.

Reserve each campaign's notes under its feature area. Reserve changes to the shared Memory format
under `agent-workflow`. Separate branches may change their own index rows; preserve both when merging.

## Work separately

New campaign and feature writers use temporary branches and worktrees, including planning writers.
Main accepts one writer at a time for combining completed work. Existing claimed work may finish there.
Use branch names beginning with `codex/`, starting from current committed main or a required dependency branch.
Other agents' unfinished files stay in their workspaces; preserve them.

Worktrees share Git history and remain one application. They do not separate remote Supabase, R2,
providers, local databases or server ports; reserve shared resources before using them.
Link worktree `node_modules` to main's, retaining the separate Vite cache configured for each worktree.

## Save and merge

Commit clear steps and push before ending a session or handing work over.
Save plans, approvals and Memory in the same branch. Record its branch, folder, completed checks,
remaining work and next action. Mark pending integration **Waiting to merge**.
Main's notes describe combined progress; branch notes describe pending progress.

Merge a small, complete portion after required checks and approvals pass and main is available.
Aim for portions that fit one task or session; split longer work where possible.
Use readiness rather than a fixed timer. Unfinished work can be pushed for recovery.
Keep incomplete features within their approved private or disabled boundary.

Keep the source task reserved. From a clean main workspace, claim a separate integration task
with `--area main-integration`; wait while another writer owns main.
Update the branch against current main, resolve conflicts, preserve other campaigns' notes,
and run checks appropriate to the combined changes. Review, merge, update the checkpoint and push main.
Commit only your changes. Release both reservations after successful integration.
Remove temporary workspaces only after needed work is merged and successfully pushed.
If a check, merge or push fails, keep the workspace and report what remains.

## Stop and recover

Before stopping with unmerged work, save and push a checkpoint. Keep its reservation until
integration, an explicit handover, or recovery establishes who owns the remaining work.
For handover, record the branch, folder, reservation ID and next action.
Release a reservation with:
`python3 .claude/skills/agent-coordination/scripts/agent-work.py release <id>`

Reservations never expire automatically. Before taking over, inspect changes, commits,
checkpoints and external actions; an old timestamp alone proves nothing.
When main's notes are stale or a reservation is missing, inspect pending branches and worktrees
before duplicating work. Claim the remaining task before continuing.
The register is shared by linked worktrees through main's ignored `.agent-work/` folder.
It protects agents on this machine only; multiple machines need a shared reservation service.
