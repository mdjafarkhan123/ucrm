---
name: agent-coordination
description: Set up or use safe parallel agent sessions in one Git project. Use for concurrent terminal agents, task claiming, available campaign work, or first-time multi-agent setup in a project without agent rules.
---

# Agent coordination

Independent sessions do not share conversation context. A campaign checkpoint says what remains; it is not
a live reservation. Use this skill when agents may run at the same time, whether their tasks are in one
campaign, different campaigns, or outside campaigns.

## Detect setup on every invocation

Check the project, not the conversation history. Setup is complete only when all of these are true:

1. The project is a Git repository and this skill's bundled `scripts/agent-work.py` is reachable from it.
2. Each agent client used for this project can discover the skill and its entry instructions (`AGENTS.md`
   for Codex, `CLAUDE.md` for Claude Code, or an equivalent file) direct agents to check and claim work.
3. Git ignores `/.agent-work/`, and the register command runs from the project.

If all checks pass, follow **Each agent session** below. If any check fails, treat the project as unconfigured
or partly configured and repair only the missing pieces. The presence or absence of `.agent-work/state.json`
does not indicate setup: it is local, ignored, and created on demand. Existing dirty changes and active
reservations must be inspected separately.

## Setup or repair

1. Preserve existing project instructions, user choices, and active changes. If the project is not yet a Git
   repository, establish its intended repository before using this Git-backed register.
2. Make this skill discoverable in the agent clients the project uses. A skill installed in a user or
   project skill catalog can be invoked for setup; a brand-new project with no instructions cannot make
   every agent load it automatically. Add a short pointer to the appropriate project instruction file(s)
   after setup. If none exist, create minimal `AGENTS.md` for Codex and/or `CLAUDE.md` for Claude Code.
3. The pointer must tell every coding agent to load this skill and run the bundled
   `scripts/agent-work.py list` before selecting a task, then claim the task before writing. Link any
   project-specific coordination guide when one exists. Ignore `/.agent-work/` in Git.
4. Before enabling simultaneous code writers, confirm the project's branch and workspace policy with
   its owner. Separate temporary Git worktrees are the default isolation method where permitted. Keep one
   controlled integration path into the primary branch. Existing dirty changes remain unclaimed until
   their owner is identified.

Repeat the detection checks before calling setup complete. If the skill is only installed locally in one
terminal's environment, explain that other agent clients must receive it too.

## Each agent session

Run `python3 <path-to-this-skill>/scripts/agent-work.py list` from the project. For an available campaign
task, read its roadmap and checkpoint, check dependencies, and choose a part that can progress alongside
active reservations. For any task, inspect Git changes and identify broad code areas and shared external
resources it will touch. Use `--area '*'` when the scope is unknown.

Claim the exact roadmap part identifier before starting. Use `standalone` as the campaign name for work outside a
campaign. A read claim prevents a second agent from taking that same task. A write claim also prevents a
second writer in one worktree or a writer with an overlapping area. The command makes the claim atomically,
so two terminals cannot both win a race for the same task.

```bash
python3 <path-to-this-skill>/scripts/agent-work.py claim campaign-name part-name --owner terminal-label --mode write --area invoices
```

If a claim fails, choose a different ready task or wait. A successful claim does not prove that different
area names are truly independent: check shared files, migration order, remote databases, providers, and
integration dependencies. If scope grows, expand the claim atomically with `expand <id> --area <area>` before
touching the new area. `--adopt-existing` is only for dirty changes positively identified as this session's
own work. Never overwrite unknown work.

Keep a write reservation through integration and any campaign checkpoint update. The integrator releases a
handed-off branch's reservation after integration. Release with
`python3 <path-to-this-skill>/scripts/agent-work.py release <id>`. Reservations do not
expire automatically. Before reclaiming one from an interrupted agent, inspect that agent's worktree,
changes, commits, and external effects. The register is local to one machine; cross-machine work needs a
shared service.
