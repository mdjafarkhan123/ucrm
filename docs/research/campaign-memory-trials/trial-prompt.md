# Campaign Memory trials

Fresh-session trials for `.claude/skills/campaign-memory`. Each trial gives one fresh agent one of Jafar's
messages inside a made-up copy of the project, then compares what it read and did with the expected behaviour.
Ask Jafar before launching trial agents: each run costs roughly 70,000–160,000 tokens.

## Build the test copies

From the project root, with `<scratch>` outside the project:

```bash
python3 docs/research/campaign-memory-trials/make_fixture.py <scratch>/<name> .claude/skills/campaign-memory .
```

To test an older version, export it first (for example `git archive <commit> .claude/skills/campaign-memory`)
and pass that folder as the second argument. Each copy has five campaigns, two deferred notes, a small app, and
one reservation held by "other-session-opus" from its own worktree.

## Messages and expected behaviour

| Trial | Jafar's message | Expected |
| --- | --- | --- |
| S1 | read memory and continue quote-reminders. btw the client list sorts names in the wrong order, but that's not for now | resumes Part 2; reads the core agreement; claims; finds `QR-TEST-7` in `outbox/sent.log` and never resends; adds the opted-out skip until `checks/reminder_check.py` passes; finishes Part 2; puts the sorting issue in deferred |
| S2 | read memory and continue | asks which of the movable campaigns; names what invoice-export and job-checklists wait for; changes nothing |
| S3 | start a campaign: clients should be able to add photos when they request work | finds `deferred/request-photos.md`, carries its 10-photo limit into the plan and deletes the record; creates plan, `NOW.md`, `ROADMAP.md`, and the index row; asks product questions; builds nothing |
| S4 | read memory and continue price-book-import | runs the done-check; finishes Part 3; finishes the campaign only if nothing agreed is known to be broken (the importer has two real gaps) |
| S5 | fix the spelling mistake in docs/help/notice.md | fixes one word; creates no campaign |
| S7 | read memory and continue staff-timesheets | asks the saved overtime question; does not re-ask the answered one; builds nothing |

## Prompt (replace ROOT and the message)

```text
You are a fresh agent in a test of the project's campaign workflow skill. Act exactly like a normal session
would for Jafar's message below, but only inside this test copy of the project:

ROOT = <test copy>

It is a small made-up copy of Jafar's CRM project with its own Git repository and its own work register. Test rules:

1. Never read or change anything in the real project. Begin every Bash command with `cd ROOT && `. Use
   absolute paths under ROOT for the Read, Edit and Write tools.
2. Load the campaign skill by reading ROOT/.claude/skills/campaign-memory/SKILL.md and follow it as if it had
   been loaded for you. Open any file it points to from that same folder. Do not use the Skill tool for
   campaign-memory or any other skill; when you need another skill, read ROOT/.claude/skills/<name>/SKILL.md.
3. Your project rules are the CLAUDE.md you already have. Run the register from ROOT:
   `cd ROOT && python3 .claude/skills/agent-coordination/scripts/agent-work.py ...`. Work directly in ROOT on
   branch main; do not create worktrees for this test.
4. There is no app server, browser, database, design app, Git remote or text provider. Skip pushing,
   live-app checks, screenshots and Pencil; say which ones you skipped. Install nothing. Keep web research to
   two searches at most.
5. Jafar is not available. When the workflow says to ask him something, put the exact question in your
   report and stop at that point, as if waiting for his reply.
6. Do the work the workflow leads you to, including small code changes in this copy, but do not start another
   part or another campaign after the one you are working on.

Jafar's message: "<message>"

When you stop, reply with:
A. Every file you read, in order (paths relative to ROOT).
B. Every change you made (files created, edited, deleted; claims; commits) and the result of each check you ran.
C. Each decision you made and the skill line that drove it (quote it briefly).
D. Any question for Jafar, word for word.
E. Anything in the skill that was unclear, contradictory or made you guess — quote the line.
```
