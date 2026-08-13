# AI agent memory without context bloat

Research date: 2026-08-13

## Question

How should a coding repository preserve long-running project context without making an agent read an ever-growing Markdown file? The preferred solution should work with plain files and normal repository search. A vector database may be added later, but must not be required.

## Conclusion

Use **progressive disclosure with a bounded index**. Keep a small router that tells the agent what exists, keep the current work packet small, and store detail in narrowly scoped files that are opened only when the current task needs them. Summaries help retrieval and continuation, but canonical product documents, ADRs, code, migrations, and tests remain the source of truth.

This is the filesystem equivalent of an index plus data pages. The index identifies likely pages; it does not duplicate all of their contents.

The current `Memory/jafar-complete-roadmap.md` is about 300 lines and 25 KB. Its real problem is not Markdown itself. It combines routing, current execution state, durable decisions, and the detailed backlog in one read unit.

## Evidence from primary sources

### 1. Load a small working set, then retrieve detail

Anthropic's Agent Skills use three-stage progressive disclosure: lightweight metadata is always available, the main instructions load only when triggered, and supporting resources load only when needed. Anthropic describes the filesystem as the mechanism that makes this staged loading possible. Its authoring guidance also recommends splitting an entry file that grows beyond 500 lines, avoiding deeply nested references, and giving longer reference files a table of contents. [Anthropic Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview), [Anthropic Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

Anthropic's own project-memory design is even closer to this use case: `MEMORY.md` is a concise index, detailed notes live in topic files, and topic files are read on demand. Only the first 200 lines or 25 KB of the index are loaded at session start. The same documentation warns that larger always-loaded instruction files consume context and may reduce adherence. [Claude Code memory documentation](https://code.claude.com/docs/en/memory)

Anthropic's context-engineering guidance says agents can navigate files and retrieve information incrementally. It recommends doing the simplest thing that works and identifies context pollution as a problem even when a model has a large context window. [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

**Practical inference:** use a small Markdown index and normal file search before adding embedding infrastructure.

### 2. Separate current state, durable knowledge, experience, and procedure

LangGraph's official memory model separates short-term thread state from cross-session long-term memory. It further distinguishes semantic memory (facts), episodic memory (past experiences), and procedural memory (rules). Its documentation notes that one growing profile becomes error-prone and may need to be split into multiple documents; collections improve recall but require search and lifecycle management. It also explicitly distinguishes semantic memory from embedding-based semantic search. [LangGraph memory overview](https://docs.langchain.com/oss/python/concepts/memory)

**Practical inference for a repository:**

- Current task state belongs in a small checkpoint or work packet.
- Durable product facts belong in canonical product documents or ADRs.
- Agent procedure belongs in `AGENTS.md` or a relevant skill.
- Past execution details normally belong in Git history or a cold archive, not in the active checkpoint.

### 3. Preserve history, but retrieve a compact subset

The Generative Agents paper stores a complete natural-language memory stream, then retrieves a compact subset using relevance, recency, and importance. It periodically synthesizes higher-level reflections rather than placing the full stream into every prompt. Its ablation found that memory, reflection, and planning components each mattered to behavior. [Park et al., *Generative Agents: Interactive Simulacra of Human Behavior*](https://arxiv.org/abs/2304.03442)

MemGPT applies the same broad idea as a memory hierarchy: a small in-context tier is backed by larger external storage, with information moved between tiers as needed. [Packer et al., *MemGPT: Towards LLMs as Operating Systems*](https://arxiv.org/abs/2310.08560)

**Practical inference:** retaining a record does not mean loading that record. Git or a cold archive can preserve history while the active context contains only the current working set.

Microsoft's official event-sourcing guidance makes the database analogy precise: append-only history is costly to replay, so systems build query-optimized projections and periodic snapshots. It also warns that full event sourcing adds substantial complexity and that traditional storage is sufficient for most systems. [Microsoft Azure Architecture Center, Event Sourcing pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)

**Practical inference:** do not build an event-sourced memory system for this repository. Git already provides recoverable history. Treat the current checkpoint as the small read projection and rebuild or correct it from canonical sources when necessary.

### 4. Compact for continuity, not authority

Anthropic describes compaction as summarizing an overgrown context and starting a fresh one. Its implementation preserves architectural decisions, unresolved bugs, and implementation details while discarding redundant messages and tool output. It couples the summary with recently accessed source files. [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

**Practical inference:** a checkpoint should preserve the goal, current status, locked decisions that are not canonical elsewhere, open risks, and the exact next action. It should link to authoritative files rather than copy them. Compaction output is a navigation aid and continuity record, never a new source of truth.

### 5. More context can reduce accuracy

The *Lost in the Middle* study found that models often use information at the beginning or end of a long context better than information in the middle. Adding retrieved documents showed diminishing gains, and longer context increased the material the model had to reason over. [Liu et al., *Lost in the Middle: How Language Models Use Long Contexts*](https://arxiv.org/abs/2307.03172)

**Practical inference:** success should be measured by whether the right small set is retrieved, not by how much memory is available or loaded.

## Recommended repository pattern

This is a proposed pattern, derived from the evidence above. Names are examples, not a request to create these files immediately.

```text
Memory/
  INDEX.md                       # bounded router, not a knowledge dump
  active/
    jafar-roadmap/
      NOW.md                     # current part, blockers, exact next step
      ROADMAP.md                 # short status line and link per part
      parts/
        01-public-application.md # detail loaded only for this part
        02-prospect-review.md
        ...
  archive/                       # optional cold records, never loaded by default
```

Canonical knowledge remains outside task memory:

```text
docs/PRODUCT.md                  # approved product behavior
docs/Owner.md                    # owner/operator context
docs/adr/*.md                    # durable decisions and rationale
code, migrations, tests         # implemented truth
```

### Bounded index contract

Keep `Memory/INDEX.md` deliberately small, for example under 100 to 150 lines. Each entry should contain only:

- task or topic name;
- status: active, blocked, deferred, complete, or archived;
- one-sentence purpose;
- exact file path;
- `read when` trigger or a few stable search terms;
- last verified date, if staleness matters.

Do not copy decisions, checklists, or session notes into the index. If the index approaches its limit, split the underlying task more narrowly or archive completed entries. Do not solve index bloat by making a second always-loaded index.

### Retrieval protocol

1. Read the small index.
2. Match the user's request to an active task or topic.
3. Open that task's `NOW.md` and only the linked part file needed now.
4. Use exact repository search such as `rg` for named entities, routes, table names, decisions, and aliases.
5. Open linked canonical documents and relevant code to verify the memory before acting.
6. After work, update only the current checkpoint and checklist. Promote a durable decision to its canonical document or an ADR.
7. When a part completes, remove it from the active working set. Keep history in Git or move a genuinely necessary audit record to the cold archive.

This gives deterministic retrieval without a vector database. Add semantic search only after measured retrieval failures show that filenames, links, headings, aliases, and exact search are insufficient.

### Compaction rules

When an active work packet exceeds its budget:

1. Preserve the approved goal and acceptance boundary.
2. Preserve open checklist items, blockers, unresolved risks, and the exact next action.
3. Replace copied background with links to canonical sources.
4. Remove completed-session narration, command output, repeated decisions, test counts, and file-by-file change stories.
5. Do not silently rewrite product decisions. If a fact conflicts with a canonical source, flag the conflict for the owner.
6. Keep the pre-compaction version recoverable through Git; do not require the agent to load it.

## Failure modes to prevent

- **A mega-index:** moving all detail into `INDEX.md` recreates the same problem.
- **Imports mistaken for retrieval:** splitting a file but automatically importing every child improves organization, not context size. Anthropic explicitly notes that imported instruction files still enter startup context. [Claude Code memory documentation](https://code.claude.com/docs/en/memory)
- **Summary becomes truth:** repeated summaries can omit qualifications or preserve stale claims. Require source links and verify against canonical files.
- **Duplicate truth:** copying the same decision into a roadmap, checkpoint, product document, and ADR creates conflicts. Store it once and link to it.
- **Task scope is too broad:** one file for an entire multi-month mission will continue to grow even with disciplined prose. Split by independently resumable part.
- **Deep link chains:** agents can stop before reaching the needed detail. Prefer index to task to canonical source, with no more nesting unless necessary.
- **Silent truncation:** a large entrypoint can hide late content under tool or product limits. Keep important routing data within an explicit budget and check it mechanically.
- **No freshness signal:** a relevant but stale note is dangerous. Track status and, where needed, a last-verified date.
- **Over-insertion:** recording every observation lowers precision and makes retrieval noisy. Save only information that changes a future session's action.
- **Over-compaction:** removing unresolved constraints or rationale can make continuation unsafe. Compact completed narration first.
- **Premature vector search:** embeddings add dependencies, ranking behavior, cost, and another index to maintain. They do not fix duplicate or stale truth.
- **Untrusted text promoted to memory:** retrieved webpages, emails, tool output, and generated text can contain malicious or false instructions. A NeurIPS 2024 paper demonstrated that poisoning a very small portion of agent memory or a RAG knowledge base could cause high attack success while leaving normal behavior largely unaffected. Only trusted project sources or owner-approved decisions should become durable memory; external text stays evidence, not instructions. [Chen et al., *AgentPoison: Red-teaming LLM Agents via Poisoning Memory or Knowledge Bases*](https://papers.nips.cc/paper_files/paper/2024/file/eb113910e9c3f6242541c1652e30dfd6-Paper-Conference.pdf)
- **No retrieval evaluation:** test the scheme with real resume prompts and verify that an agent reaches the correct task file and canonical sources without reading unrelated memory.

## Suggested first move for UCRM

Do not add a database. First, convert the Jafar roadmap into a small campaign router plus one file per independently resumable part, with a tiny current-state checkpoint. Keep approved product decisions in the existing mission, contract, product, and ADR documents and link to them. Update the resume instruction so the agent reads the index, current checkpoint, and current part only.

Before changing the structure, agree on three budgets:

- maximum index size;
- maximum current checkpoint size;
- the unit that counts as one independently resumable part.

Then test retrieval against several realistic prompts, including a task named differently from its file, a stale completed task, and a task that needs two linked canonical decisions.
