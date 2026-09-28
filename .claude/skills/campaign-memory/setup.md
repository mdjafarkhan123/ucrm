# Setting up Memory in a new project

Read this once, when a project has no `Memory/` folder.

1. Choose where plans live: one file per feature in the project's docs folder. Follow the project's existing
   naming pattern if it has one; otherwise use `docs/plans/<feature>.md`.
2. Create `Memory/INDEX.md` and `Memory/deferred/INDEX.md` from the templates, naming the plan location in the
   `INDEX.md` header.
3. Add this rule to the project's agent instructions (`CLAUDE.md`, `AGENTS.md`, or both):

   > **Campaigns.** Work that cannot finish well in one session is a campaign. Load the `campaign-memory` skill
   > before starting, planning, resuming, checkpointing, pausing, deferring, or finishing one — including when
   > Jafar says `read memory and continue`.

4. If several sessions may work at once and the instructions have no rule for claiming work, set one up with
   the `agent-coordination` skill before the first parallel session.
5. Commit.

Setup is done when a fresh session reading only the agent instructions would load this skill for a campaign
and find `Memory/INDEX.md`.
