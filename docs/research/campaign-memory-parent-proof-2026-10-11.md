# Campaign Memory parent workflow — verification

Checked 2026-10-11 against the approved [workflow](../memory-campaign-workflow-behavior-contract.md).

## Result

The parent guidance, templates, and four planning-helper connections are implemented. Two independent
fresh agents evaluated six isolated requests without the original conversation. Each selected the correct
stage and next action. This is a focused workflow check, not proof of perfect behavior on every future project.
The final read-only trial on the actual memory-skill-upgrade campaign also passed.

## Fresh-session scenarios

| Scenario | Observed result | Assessment |
| --- | --- | --- |
| Unclear idea | Reused the existing Planning campaign, sought evidence, and identified audience/channel choices; did not build from assumptions | Pass |
| Interrupted planning | Resumed the exact client-name visibility question and preserved approved SMS-only, no-send scope | Pass |
| Approved design | Continued to the approved implementation part; reused the recorded example and order without seeking approval again | Pass |
| Partial implementation | Ran the saved check, found missing permission enforcement, and kept the part unfinished | Pass |
| Conflicting progress | Ran the failing permission check, rejected the false Done state, and refused to proceed to sending excluded by the plan | Pass |
| Small change | Corrected only the typo in notice.txt and verified exact content; created no campaign | Pass |

The two implementation fixtures intentionally fail with `AssertionError: Unauthorized user received the
preview`. A passing workflow result means the agent detected that failure and chose the right correction,
not that the fixture feature passed. The small-task content check exited successfully.

Fixtures live outside the product at `/tmp/ucrm-memory-parent-20261011/scenarios/`. They are illustrative
workflow inputs, not new application features. Planning checks were read-only. Only the isolated typo file
was edited; no live data or outside service was used. Neither evaluator read the planted unrelated history.

Planning evaluator read the campaign entry, planning/delivery references, Proven Development, Grilling,
and each request's index, current note, active part or roadmap, product contract, and explicitly relevant
access/design source. Implementation evaluator read the entry, delivery/handover references, request-specific
Memory and plan sources, and provided code/check files. Neither needed the original chat.

## Mechanical checks

- Skill Creator's `quick_validate.py` passes for Campaign Memory, Grill with Docs, To Spec, To Tickets, and Wayfinder.
- YAML parsing confirms automatic selection is enabled in both helper frontmatter and Codex metadata.
- All non-example local Markdown links and section anchors in the changed skills resolve.
- Prettier checks and Git whitespace checks pass on the edited files.
- Touched campaign notes, roadmap, and index row fit their size limits.
- File fingerprints confirm all pre-existing paused app/design changes remain unchanged.

Validation used the bundled Python with PyYAML installed only under the temporary proof directory. No
application dependency or lockfile changed. The helper settings are also now reflected in this session's
available skill catalog. Reading referenced files remains the fallback where a host has no invocation tool.

## Reading size

Counts use whitespace-separated words in actual saved files, not model tokens or a billing measurement.
They measure core instructions only; selected specialist guidance and project sources add reading as needed.

| Core reading path | Before | After |
| --- | --- | --- |
| Parent entry | 1458 words | 924 words |
| Parent plus planning reference | 2109 words | 1713 words |
| Parent plus checkpoint guidance | 1458 words, guidance embedded | 1639 words |

The entry is smaller, while a cold checkpoint read is larger because it now explicitly checks state
consistency and evidence. Conditional delivery guidance adds 334 words when needed. This
upgrade improves completeness and targeted reading; it does not claim a universal token reduction.

## Actual campaign pilot

A third fresh agent received only “read memory and continue memory-skill-upgrade,” the skill path, and
read-only access to saved sources. It correctly identified the approved scope, Part 10 verification stage,
completed Parts 6–9, existing writer claim, required evidence/checkpoint action, and the older Part 2 blocker.
It independently reproduced the entry word counts and did not take over the held claim.

The trial found that the future proof pointer was not yet available at its read time, and that NOW.md's
next-part wording was ambiguous. This durable report resolves the evidence gap. The final checkpoint now
explicitly waits for the older owner-window result before Part 3, matching the roadmap and older pilot note.
No material missing context prevented the read-only resume.

The evaluator read this campaign's index/current/roadmap/part records, approved plan, parent references and
templates, four changed helper skills and metadata, the read-only register, and relevant Git state. It did
not use the original conversation or unrelated campaign bodies.

## Follow-on work

The earlier Part 2 still awaits Jafar's own-window result. The existing checker, wider campaign migration,
and general instruction cleanup remain Parts 3–5. Their status is preserved; no design skill was changed.
