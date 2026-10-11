# Campaign Memory as the parent workflow

**Status:** First-version workflow and build order approved by Jafar on 2026-10-11. First-version guidance and templates built and verified on 2026-10-11; follow-on migration remains outside this delivery. Design skills are outside this upgrade; visual planning remains supported without them.

## Summary

Jafar should be able to say “start a campaign for Unified Inbox” and receive guided planning, design, building, and checking without remembering separate skill commands. Later, “read memory and continue Unified Inbox” should let a fresh AI continue the right unfinished work. Campaign Memory explains the current stage, necessary documents, relevant skills, and what to save. The product plan explains what Jafar wants; the handover explains where work stopped. Simple tasks take a short path. This is a written guide followed by each session, rather than a background service.

## The problem and first version

The existing skills cover much of the work, but their connection is incomplete. Sessions can follow different processes; some planning skills require direct user invocation; some campaign records depend on old chats or disagree about progress.

The first version improves Campaign Memory, its supporting guidance, and its templates. It is proven on safe examples before older campaigns are moved over. Existing approvals and unfinished work remain valid.

## One entry point, throughout the journey

The AI finds the relevant campaign and approved decisions, then chooses the stage from what is actually missing. Campaigns can start during planning; the next action may be a question, research, or design rather than code.

| Situation | Guidance to use | What must exist afterward |
| --- | --- | --- |
| The idea needs facts or product examples | Proven Development and Research where needed | Relevant evidence, its limitations, and a recommendation |
| Product choices remain unclear | Grilling; Grill with Docs when terminology or lasting decisions need recording | Jafar's answers saved in the product plan; remaining questions visible |
| Planning exceeds one session | Wayfinder's decision-mapping approach | A small map of unresolved decisions and their dependencies, linked from the campaign |
| The behavior is understood | To Spec's writing approach | One readable product plan, with approval distinguished from proposals |
| Screens or interactions need agreement | Available project guidance or tools; Prototype when trying something helps | Reviewable designs, recorded feedback, and the applicable approval |
| The plan is ready to divide | To Tickets' approach | Small complete deliveries, dependencies, and observable completion checks |
| A part is ready to build | Relevant development skills from the project's rules | The approved behavior implemented and checked, or its unfinished position saved |
| A session starts or ends | Campaign Memory's resume and checkpoint guidance | A verified starting position or a useful handover |

Campaign Memory routes to specialist instructions instead of copying them. A campaign request authorizes routine skill selection. Selected planning skills must become usable through the parent where invocation settings currently prevent it; their direct use and host permissions remain supported. Unrelated skills are outside this change.

Reuse approved work. New discoveries return only affected work to planning. Small clear tasks take a shorter path without unnecessary campaigns, interviews, or research.

## The agreed product plan

The plan explains the user's problem, audience, first version, important journeys, permissions, failure situations, exclusions, and success checks. Confirmed decisions are distinguished from proposals, questions, and assumptions. Approval records its scope and date.

Checks describe observable results: “An authorized staff member receives a customer's message and replies; the customer receives that reply.” Performance and business promises require their own appropriate evidence.

A fresh reviewer reads the plan and its named sources without the original chat. Repair important gaps from evidence; ask Jafar only about remaining product choices. Routine technical choices stay with the AI.

## Documents and efficient reading

Keep the existing document homes:

- `docs/<feature>-behavior-contract.md`: the permanent product agreement, linking approved design and research where relevant.
- `Memory/campaigns/<campaign>/NOW.md`: the current stage, goal, plan pointer, blockers, and next part.
- `ROADMAP.md`, with stage files only when needed: the parts, their dependencies, checks, and current state.
- `parts/<part>.md`: unfinished progress, relevant source pointers, and the exact next action.
- Existing architecture decision records: lasting technical choices and reasons. Unfinished technical reasoning stays with the part; larger implementation plans use a linked focused document.

Read the index, current note, active part, and relevant source sections. Load specialist guidance when needed. Store each agreement once and link to it. Use existing campaign files for work tracking; research holds evidence and the plan holds our choices.

## Resume, checking, and completion

A new session identifies the goal, approved behavior, stage, completed work, blockers, next action, and completion check. It verifies the saved position against files and relevant external outcomes. Resolve conflicts from evidence; changes to approved scope go to Jafar.

At a checkpoint, notes and roadmap agree. Preserve important reasoning, questions, and proof pointers within existing size limits. Outside actions that could cause harm if repeated retain their identifier and outcome check.

A part finishes when its check passes in the integrated project; built-but-unverified work remains unfinished. Before deleting finished notes, keep necessary evidence and decisions reachable elsewhere. Campaign completion checks the whole agreed promise.

## Approved build order

1. **Part 6 — Agree this workflow:** review this plan and its build order; preserve the older pilot's outstanding owner check.
2. **Part 7 — Write the parent guidance:** update the entry point and relevant specialist connections. A fresh session can choose the right stage and usable guidance.
3. **Part 8 — Improve the templates:** add the missing purpose, first-version, success, stage, and proof pointers without duplicate document homes.
4. **Part 9 — Prove a fresh start:** use temporary safe examples for an unclear idea, interrupted planning, an approved design awaiting build, partial implementation, conflicting progress, and a small task. A fresh AI must take the correct next action using the saved sources.
5. **Part 10 — Pilot and measure:** try one campaign, report actual reading size and behavior, repair demonstrated failures, and retain only necessary guidance.

The [existing roadmap](../Memory/campaigns/memory-skill-upgrade/ROADMAP.md) retains Parts 1–5 and adds Parts 6–10. The [older pilot](../Memory/campaigns/memory-skill-upgrade/parts/part-2.md) still awaits its owner-window result. Review the earlier checker, wider migration, and cleanup after the new pilot; preserve their unfinished status.

## Still unclear

- No unresolved first-version product choices. Verification may uncover implementation gaps.

## Not doing

- New memory infrastructure, a second tracker, or a required design app: use existing files and skills.
- Immediate migration of all campaigns or changes to app features: prove the workflow first.
- Every skill and stage for every task: use what is needed and respect existing approvals.
- Guaranteed perfection or unmeasured token savings: report actual evidence and limitations.

## Research and existing sources

- [Existing planning guidance](../.claude/skills/campaign-memory/planning.md), [To Spec](../.claude/skills/to-spec/SKILL.md), [To Tickets](../.claude/skills/to-tickets/SKILL.md), and [Wayfinder](../.claude/skills/wayfinder/SKILL.md) supply the starting workflow. This plan adapts their outputs to the existing campaign homes.
- [Matt Pocock's published To Spec](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md) separates the user's problem, solution, stories, testing decisions, and exclusions; [To Tickets](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md) supplies complete slices and acceptance checks.
- [Superpowers' builder check](https://github.com/obra/superpowers/blob/main/skills/brainstorming/builder-check-prompt.md) tests whether a new builder still needs important answers. We adapt it to a fresh campaign session.
- [GitHub Spec Kit's specification template](https://github.com/github/spec-kit/blob/main/templates/spec-template.md) provides prioritized journeys, concrete acceptance scenarios, and success outcomes. Its [analysis guidance](https://github.com/github/spec-kit/blob/main/templates/commands/analyze.md) checks missing coverage and contradictions; applying that principle at campaign checkpoints is our adaptation.

- [Verification and reading measurements](research/campaign-memory-parent-proof-2026-10-11.md) — six isolated scenarios, one actual campaign resume, and mechanical checks.
