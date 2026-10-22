# AI supervisor workflows: verified options for UCRM

Checked on 2026-10-22. Research only: no connector installed, agent workflow changed, worker task launched, or CRM code modified. Documentation establishes supported interfaces; it does not establish that this particular combined setup works on this machine.

## What is established

The supervisor pattern is real. Evidence does **not** establish that a Claude → Codex → Antigravity hierarchy is the standard setup used by “top engineers,” or that Claude is universally the best supervisor.

| Evidence | What it establishes | Boundary |
| --- | --- | --- |
| [Anthropic employee study, 2026-10-16](https://www.anthropic.com/research/employment-at-anthropic) | Employees write specifications for multi-agent runs, loop one agent to review another, and monitor agent pipelines. | A first-party study of Anthropic, not evidence of widespread mixed-vendor adoption. |
| [Claude Code team's power-user practices](https://support.claude.com/en/articles/14554000-claude-code-power-user-tips) | Individual team engineers run 3–5 Claude sessions in separate Git worktrees; one Claude can plan and another review the plan. Verification is emphasized. | The team uses different setups; parallel sessions are not automatically a single supervisor. |
| [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) | A lead assigns work and combines results from independent Claude Code teammates with shared tasks and messaging. | Experimental, disabled by default, higher token use, and documented coordination/resume limitations. These are Claude Code instances. |

Historical evidence needs careful labeling. Nicholas Carlini's [2026-02-05 compiler experiment](https://www.anthropic.com/research/building-c-compiler) used 16 parallel Claude agents, separate container checkouts, task locks, and extensive testing. It explicitly says **no orchestration agent was used**. It proves substantial parallel-agent work was attempted, not the particular supervisor arrangement described here.

## The current interfaces

**Claude as the lead.** [Claude Code's tools](https://code.claude.com/docs/en/tools-reference) include shell execution and background commands, so it can launch an external program and read its results. This supplies the mechanism for CLI delegation. Native [subagent model configuration](https://code.claude.com/docs/en/sub-agents#choose-a-model) documents Claude aliases/full IDs and inheritance; it does not document `model: codex` or `model: antigravity` as backend switches. External workers need an explicit connector or launcher.

**Codex as a worker.** OpenAI documents [`codex exec`](https://learn.chatgpt.com/docs/non-interactive-mode) for non-interactive scripts and pipelines, with JSONL events, configurable sandboxing, and continuation. An integration can supply a bounded task, collect results, and ask for corrections. This uses Codex CLI rather than clicking an existing ChatGPT or Codex desktop conversation.

Documented launch shape, shown for review rather than executed here:

```bash
# First prove read-only delegation in an assigned worker folder.
codex exec --cd /path/to/worker --sandbox read-only --json \
  -o /path/to/run-result.md "Inspect the assigned area and report findings; do not edit files."

# A later authorized implementation task can permit workspace edits.
codex exec --cd /path/to/worker --sandbox workspace-write --json \
  -o /path/to/run-result.md "Implement only the assigned task and report verification evidence."
```

The prompts are examples; replace the paths and task with the actual assignment. CLI invocation alone does not provide task tracking or independent review.

**Antigravity as a worker.** Google's current [headless CLI documentation](https://www.antigravity.google/docs/cli/headless/) documents `agy -p`, JSON/streaming JSON, explicit conversation continuation, and a persistent stdin/stdout conversation protocol. This supports a programmatic worker interface. It uses cached authentication and needs appropriate preconfigured tool permissions. Some denied tool actions allow the overall run to exit successfully, so the supervisor must inspect notices and actual results, not merely exit code zero. Google's [announcement](https://cloud.google.com/blog/topics/developers-practitioners/io26-news-for-agent-developers-on-google-cloud) describes the CLI as sharing the desktop application's harness and agent. Gemini CLI and Antigravity CLI are distinct command targets; a connector listing `gemini` does not by itself prove `agy` support.

**Outdated integration advice.** Current OpenAI documentation says [`codex mcp-server` and its standalone binary were removed](https://learn.chatgpt.com/docs/mcp-server). The old MCP tool/Agents SDK examples are unsupported. Codex's replacement app-server protocol is not an MCP drop-in and is experimental. Avoid old “add `codex mcp-server` to Claude” tutorials. This does not remove Codex's ability to consume external MCP tools.

## Existing connector verified in its own documentation

[PAL MCP](https://github.com/BeehiveInnovations/pal-mcp-server), formerly Zen MCP, provides [`clink`](https://github.com/BeehiveInnovations/pal-mcp-server/blob/main/docs/tools/clink.md), a CLI-to-CLI bridge. Its maintainers document Claude Code launching Codex/Gemini CLI workers, role presets, returned results, and continuity. This is an existing candidate rather than a hypothetical integration. It was **not installed or tested here**, and its existence does not establish adoption by leading engineering teams.

Its shipped presets include `gemini`, `claude`, and `codex`, not a verified Antigravity preset. The documented Codex command uses `codex exec`, not the removed Codex MCP server. Crucially, its default Codex preset bypasses sandboxing/approvals and its Gemini preset uses `--yolo`. Before CRM edits, replace those broad permissions with suitable restrictions and verify isolation. A read-only trial should come first. Compatibility with the installed CLI versions is untested. Changing a preset alone does not establish compatibility with Antigravity's output format.

## Recommended adaptation for this CRM

This is a proposed application of the verified interfaces, **not a claim about an industry-standard configuration**.

```text
Jafar — product decisions and approvals
  └─ Claude Code — the one conversation for planning and coordination
       ├─ Codex CLI worker — one clearly specified implementation task
       ├─ reviewer — independent inspection of the resulting change
       └─ Antigravity CLI worker — optional after its connector is verified
```

1. Start with Claude Code plus **one Codex worker**. Use a small direct CLI launcher, or evaluate PAL's existing `clink` bridge with tightened permissions. Add Antigravity only after its local installation, authentication, command format, permissions, and result handling are confirmed.
2. Give each task a written scope: expected behavior, relevant project instructions/skills, files or domain owned, forbidden outside actions, acceptance checks, and required evidence. The lead must pass context deliberately; an external worker does not inherit the lead's whole conversation automatically.
3. Give each writer its own temporary branch/worktree and reserve the task using this repository's coordination register. The supervisor launches workers from those folders and records worker session IDs, logs, results, and current status so interruptions can be recovered.
4. Have the worker implement and verify its bounded task. Have the supervisor inspect the actual diff and check evidence, ask for repairs, and obtain an independent review when appropriate. Integrate completed changes through the repository's normal main-branch process.
5. Prove the connection with a read-only task; then prove one small reversible code change on a temporary branch. Verify task delivery, progress collection, continuation, cancellation/failure behavior, review, and cleanup before scaling to several writers.

These steps can reduce terminal switching because the lead collects worker output. They do not imply that Claude controls existing open desktop chats, that workers never need input, or that adding more workers always helps. Official Claude guidance recommends [explicit verification evidence and a second opinion](https://code.claude.com/docs/en/best-practices), including tests and screenshots as appropriate. Reviewer agreement does not prove correctness.

Repository-specific constraint: [the existing concurrency rules](../agent-concurrency.md) already require task reservations and isolated worktrees. Worktrees separate files and branches; they **do not isolate remote Supabase, R2, providers, databases, or server ports**. Reserve shared resources too. A supervisor must preserve Jafar's existing product and infrastructure approval boundaries.

## Local readiness and remaining uncertainty

The parent session's read-only audit found Codex CLI `0.163.0` and Claude Code `2.1.307`. Its `codex exec --help` check confirmed the working-directory, sandbox, JSON output, final-message-file, and continuation options. Neither `agy` nor `antigravity` was found in that shell's PATH; this does not prove Antigravity is absent systemwide. Authentication, subscription access, costs, connector behavior, and an end-to-end supervisor run remain unverified. No setup recommendation here requires installing a broad orchestration framework before that first proof.
