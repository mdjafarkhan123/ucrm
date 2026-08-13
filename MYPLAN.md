# My plan for long-running AI work

## The decision

If I were managing this CRM, I would keep the idea behind the current `Memory` system, but change its shape.

The system should behave like an indexed database, not like one growing notebook:

- A small index tells the agent which campaign is active.
- A small checkpoint tells the agent what is happening now.
- A roadmap preserves the complete goal and the order of work.
- Separate part files contain the detail for one resumable slice.
- Product documents and ADRs remain the permanent source of truth.
- Git preserves old execution history without putting that history into every new context window.

The agent should be able to receive `read memory and continue` in a fresh session and continue without Jafar manually explaining the next task.

## What the current system gets right

The current system solves a real limitation of coding agents. A large feature cannot safely be designed and built in one context window. The agent needs to preserve:

- the final outcome;
- the approved product behavior;
- the implementation order;
- dependencies between parts;
- completed and remaining work;
- blockers and deferred work;
- the exact next action.

Keeping this information in the repository is the right foundation. It is inspectable, editable, versioned, and available to every future agent.

The problem is not that the roadmap exists. The problem is that the current roadmap is also acting as an index, product specification, session checkpoint, progress log, and archive. Those kinds of information have different lifetimes and should not share one read unit.

## The model I would use

I would call each large multi-session goal a **campaign**.

A campaign is larger than one task. For example, "Complete the Jafar panel" is a campaign. "Build organization directory pagination" is one part of that campaign.

The hierarchy would be:

```text
Repository rules
    -> Memory index
        -> Active campaign checkpoint
            -> Active part packet
                -> Relevant permanent docs and code
```

This is progressive disclosure. Each level is a routing layer. It points to detail instead of copying that detail.

## Proposed file structure

```text
Memory/
  INDEX.md

  campaigns/
    jafar-panel/
      NOW.md
      ROADMAP.md
      parts/
        06-organization-commercial-access.md
        07-team-access-recovery.md
        08-operations-owner-security.md
        09-organization-closure.md
        10-provider-controls.md
        11-final-release-audit.md

  deferred/
    INDEX.md
    database-tests.md
    prospects-detail-page.md

  archive/
    README.md
```

This is an example structure, not a requirement to keep these exact names.

Permanent knowledge stays where it belongs:

```text
docs/PRODUCT.md
docs/Owner.md
docs/jafar-organization-management-mission.md
docs/jafar-onboarding-implementation-contract.md
docs/adr/*.md
source code
migrations
tests
```

## What each file does

### `Memory/INDEX.md`

This is the database index and the only Memory file a fresh agent reads first.

It contains one short entry per active or paused campaign:

```md
## Current campaign

- Name: Complete Jafar panel
- Status: active
- Purpose: Finish the owner workspace from application through organization closure.
- Continue at: `Memory/campaigns/jafar-panel/NOW.md`
- Read when: the user says `read memory and continue`, or asks about Jafar, owner operations, onboarding, organization administration, or provider controls.

## Paused campaigns

- Data cache architecture: `Memory/campaigns/data-cache/NOW.md`
  Read when work touches QueryClient ownership, server-state caching, or invalidation.
```

The index contains no detailed decisions, checklist, session history, or implementation notes.

I would cap it at 100 lines. If it grows, completed entries leave the active index.

### `NOW.md`

This is the campaign's hot working memory. It is a checkpoint, not a diary.

It should contain only:

- the campaign goal in one or two sentences;
- current part and status;
- exact next action;
- open blockers or decisions;
- important uncommitted-work boundaries;
- the exact part file to read;
- the exact permanent document headings needed for that part.

Example:

```md
# Jafar panel checkpoint

Status: active
Current part: 6, Organization and commercial access
Part packet: `parts/06-organization-commercial-access.md`

## Goal

Complete the approved Jafar workspace from public application through safe organization closure.

## Next action

Audit the existing organization directory, package, free-access, payment, and history implementation against Part 6. Present the gap plan before changing code.

## Read for this part

- `ROADMAP.md` for campaign position and dependencies.
- `docs/jafar-organization-management-mission.md`, sections "Commercial rules", "History, transparency, and recovery", and "Organization-detail structure".
- `docs/jafar-onboarding-implementation-contract.md`, sections "Packages and access" and "Renewals and lifecycle".

## Boundaries

- Preserve the user's uncommitted LocationPicker and TimezonePicker work.
- Schema, auth, RLS, and permission changes require approval.

## Completion rule

Complete only the current part packet, update this checkpoint, and stop.
```

I would cap `NOW.md` at 60 to 80 lines. It is rewritten at the end of a session instead of appended to.

### `ROADMAP.md`

This preserves the whole campaign so the agent does not lose sight of the final feature.

Each part gets only:

- a short outcome;
- status;
- dependencies;
- link to its part packet;
- completion gate.

Example:

```md
| Part | Outcome | Status | Depends on | Packet |
| --- | --- | --- | --- | --- |
| 1 | Reconcile foundations | complete | none | archived in Git |
| 2 | Durable operations | complete | 1 | archived in Git |
| 6 | Commercial access | active | 1 to 5 | `parts/06-organization-commercial-access.md` |
| 7 | Team recovery | pending | 6 | `parts/07-team-access-recovery.md` |
```

The roadmap lets an agent understand how today's work contributes to the final goal, but it does not include all implementation detail.

I would cap it at roughly 150 lines. If a campaign needs more than that, its parts are too broad or the rows contain too much detail.

### Part packets

One part file is one independently resumable delivery slice. It contains the context needed to finish that slice well:

- outcome;
- why it matters to the campaign;
- approved behavior specific to this part;
- dependencies and prerequisites;
- scoped checklist;
- acceptance checks;
- relevant permanent-document pointers;
- known risks and edge cases;
- current findings that cannot be discovered cheaply from code.

It should not contain completed session narration, command output, file-by-file change lists, or copied sections from permanent docs.

Only the active part packet is read by default. Future part packets remain available but out of context.

I would target 100 to 200 lines per part. A larger packet should be split into smaller independently verifiable subparts.

### Deferred memory

Deferred work needs its own small router because "not now" is different from "next."

Each deferred entry needs:

- what is deferred;
- why it is deferred;
- the trigger that makes it active again;
- any prerequisite;
- its detail-file link if detail is necessary.

The active campaign may link to a deferred entry, but it should not copy the deferred explanation.

### Archive

Most completed implementation history should remain in Git, code, migrations, and tests. Those are better evidence than an AI-written summary.

Use a cold archive only when a completed record contains information that is genuinely needed later and has no proper permanent home. The archive is never read during normal resume behavior.

Completed product decisions do not go into the archive. They go into the appropriate product document or ADR.

## Automatic resume behavior

The phrase `read memory and continue` should trigger this exact query plan:

1. Read `Memory/INDEX.md`.
2. Follow its single current-campaign pointer.
3. Read that campaign's `NOW.md`.
4. Read the linked active part packet.
5. Read only the permanent document sections named by that packet.
6. Inspect the relevant code and current Git state to verify that the checkpoint is still accurate.
7. Work on the first unfinished checklist item in the active part.
8. Stop at the part's completion gate.
9. Replace the checkpoint with the next accurate state.

The agent should not glob or read every file under `Memory`. It should follow the index path and expand only when a named dependency requires it.

If there are several campaigns, `INDEX.md` must identify one as current. A plain resume command continues that campaign. A user can select another campaign by name.

## Session write protocol

At the end of every working session, the agent should perform a small transaction:

1. Update the active part checklist.
2. If the part is incomplete, replace `NOW.md` with the new exact next action and blockers.
3. If the part is complete, mark its roadmap row complete and point `NOW.md` at the next ready part.
4. Move any newly approved durable decision into its permanent document or an ADR.
5. Add a deferred item only when it has a clear reactivation trigger.
6. Remove details that no longer change what the next session will do.

This matters: `NOW.md` is a current-state projection, not an append-only log. Git already keeps previous versions.

## Retention rules

Every fact should have one home:

| Information | Authoritative home |
| --- | --- |
| Agent working procedure | `AGENTS.md` or a skill |
| Approved product behavior | Product or domain document |
| Important technical decision and reason | ADR |
| Full campaign outcome and ordering | Campaign `ROADMAP.md` |
| Current execution position | Campaign `NOW.md` |
| Current slice detail | Active part packet |
| Implemented behavior | Code, schema, and tests |
| Old execution history | Git |
| Work intentionally postponed | Deferred index or packet |

If the same decision appears in several places, future agents can see conflicting versions. Links are safer than copies.

## Compaction rules

Compaction should happen continuously, not after a file becomes huge.

When a file reaches its budget:

1. Keep the final goal and open acceptance conditions.
2. Keep unresolved decisions, blockers, risks, and the exact next action.
3. Replace duplicated background with a pointer to its authoritative source.
4. Collapse a completed part to one roadmap row.
5. Remove test counts, tool output, session narration, and lists of touched files.
6. Keep past content recoverable through Git.
7. Split the active part if it is not independently completable within one session.

The agent should never compact an unresolved product rule into vague wording. If the rule is durable, promote it to the product document first.

## How this maps to a database

The analogy is useful:

| Database idea | Repository memory equivalent |
| --- | --- |
| Primary index | `Memory/INDEX.md` |
| Row for current state | `NOW.md` |
| Data pages | Part packets |
| Normalized tables | Product docs and ADRs with one source of truth |
| Query plan | Index, checkpoint, active part, relevant sources |
| Materialized view | Small current checkpoint derived from the real project |
| Cold storage | Git or optional archive |
| Vacuum or compaction | Remove completed narration and stale duplicates |

The checkpoint can become stale just like a materialized view. That is why every session verifies it against code, Git status, and canonical docs before making changes.

## Why I would not add vector search now

Vector search is useful when there are hundreds or thousands of loosely named documents and exact search repeatedly fails. This repository currently has a small number of structured Markdown files with known domain terms.

Adding embeddings now would create:

- another index that can become stale;
- new dependencies and maintenance;
- less predictable retrieval rankings;
- a risk that copied or untrusted text is treated as authority;
- no solution for duplicated or badly organized truth.

I would first use stable filenames, headings, explicit `read when` triggers, aliases, direct links, and `rg`. I would measure real retrieval failures. Only repeated failures would justify semantic search later.

## Edge cases the system must handle

### A part becomes too large

Split it before implementation into numbered subparts, each with its own checkable outcome. Keep the parent part as a short index.

### Work uncovers a new product decision

Stop and ask Jafar. After approval, record it once in the permanent product document or an ADR. The checkpoint links to it.

### Code disagrees with Memory

Do not silently trust Memory. Inspect the current code, migrations, tests, and Git status. Correct the checkpoint or report the conflict.

### Several tasks are active

The global index names one current campaign. Other campaigns are paused or explicitly selected. This prevents a vague resume command from choosing arbitrarily.

### A task is blocked

Record the blocker and reactivation condition in `NOW.md`. If another campaign or independent part can safely proceed, point the current-campaign field to it. Do not load the blocked task every session.

### Uncommitted user work exists

Record only the boundary that affects the next session, such as protected paths or ownership. Do not copy the full Git status into Memory because it changes constantly. Every session checks Git again.

### An old decision is needed later

It should be in a permanent doc or ADR. If it exists only in Git history, retrieve it deliberately. Do not keep all old sessions hot just in case.

### A summary accidentally drops an important condition

Part packets link to authoritative headings and contain explicit acceptance checks. The agent verifies them before implementation. Memory is a navigation and continuity layer, not final authority.

### External research contains instructions or false claims

External text stays research evidence. Only Jafar-approved decisions and trusted repository sources become durable project memory.

## How I would migrate the Jafar roadmap

I would do this as a small, reversible pilot:

1. Preserve the current roadmap in Git and do not rewrite product behavior during migration.
2. Create the global index and mark Jafar as the current campaign.
3. Create `jafar-panel/NOW.md` pointing to Part 6.
4. Convert the existing execution checklist into a compact roadmap table.
5. Collapse Parts 0 through 5 into one line each. Code, tests, migrations, and Git remain their evidence.
6. Move the details for Parts 6 through 11 into separate part packets.
7. Remove copied locked decisions from campaign memory only after confirming that each one exists in an authoritative permanent document. Promote any missing decision before removing it.
8. Split deferred work by trigger and remove resolved entries.
9. Update the Memory rules in `AGENTS.md` and keep the matching rule in `CLAUDE.md` synchronized if both remain active instruction files.
10. Test the system with several fresh-session prompts before deleting the old combined roadmap.

The first retrieval tests should include:

- plain `read memory and continue`;
- a request phrased as "work on commercial access" rather than "Part 6";
- a request for a paused cache task;
- a request that needs two permanent documents;
- a stale checkpoint that disagrees with current code;
- two campaigns with only one marked current.

The test passes when the agent reaches the correct active packet and authoritative sources without reading unrelated campaign files.

## Proposed hard limits

I would begin with these budgets and adjust only after observing real use:

- `Memory/INDEX.md`: maximum 100 lines.
- Campaign `NOW.md`: target 60 lines, hard maximum 80.
- Campaign `ROADMAP.md`: maximum 150 lines.
- One part packet: target 100 to 200 lines; split before 250.
- Pointer depth: normally index, checkpoint, part, source. Avoid deeper chains.
- Current campaigns: one default current campaign; any number may be paused.
- Completed session narratives in hot memory: zero.

A simple check script could enforce file existence, budgets, valid statuses, one current campaign, and non-broken local links. It should not generate summaries or decide what information is important.

## Proposed change to the project rule

The current rule says one Memory file per multi-session task. I would replace that idea with one campaign folder per large goal and one active packet per independently resumable part.

The essential rule would be:

> Start from `Memory/INDEX.md`. Follow only the selected campaign's checkpoint and active part pointers. Memory routes work; it does not duplicate permanent product truth or preserve session narration. Replace the checkpoint after each session. Store approved behavior in permanent docs, implementation truth in code and tests, and old execution history in Git.

I would keep the existing one-part-per-session boundary. It is a good safety control. The improvement is that the active part becomes a bounded packet and the complete campaign remains available through the roadmap without being fully loaded every time.

## Final recommendation

Your original idea is directionally correct. I would not replace it with chat history, a database, or a vector store. I would normalize it.

The finished system should have:

- one small global router;
- one small mutable checkpoint per campaign;
- one compact complete roadmap per campaign;
- one file per independently resumable part;
- permanent decisions stored outside Memory;
- completed history stored outside the active context;
- an exact automatic resume protocol;
- mechanical size and link checks;
- retrieval tests using fresh sessions.

This preserves the intelligence of the full plan while preventing every session from paying the cost of every past and future part.

## Research basis

The supporting research and primary-source links are in [`docs/research/ai-agent-memory-without-context-bloat.md`](docs/research/ai-agent-memory-without-context-bloat.md). The main sources cover progressive disclosure, agent memory tiers, context compaction, retrieval, long-context failure, event-log projections, and memory poisoning.
