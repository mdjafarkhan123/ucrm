# OpenCode communications review — 2026-10-17

Branch `codex/settings-communications-app`, pinned head `c1405242`; review diff
`git diff df26dc1d...c1405242`. Scope: Email, Phone & SMS and Website chat.
Review claim `bda80bee10f6`. Implementation claim stays with OpenCode.

## Standards

No substantive Standards findings. The three page diffs preserve existing query
ownership, save handlers, registration edit restrictions, field bindings and action
availability. Shared DataTable replacements retain row labels and row semantics.
Repeated page-header markup is a later consolidation opportunity, rather than a
blocking source finding.

This is a source review, not a promise that every state works in the browser.

## Spec

Two findings against the contract's requirement that “every screen already
designed in Pencil … is built in the app” and Jafar's original-design approval:

1. **P2 — Approved card layout incomplete on all three pages.**
   `src/routes/(app)/settings/communications/email/+page.svelte:308`,
   `sms/+page.svelte:466` and `website-chat/+page.svelte:346` retain
   `PageContainer variant="fill"`, a padded white sheet. Original frames `QEixl`,
   `C70C3` and `fAAvd` place independent white cards on the app background. The
   page-local SectionBlock rule only sets the notch color (Email:714, SMS:1123,
   Chat:711). Base SectionBlock still positions titles/actions across its border;
   its App-look card rules require `.record-detail--cards`, absent here. SMS
   Readiness also lacks the approved horizontal title-and-facts strip `QynF6`.
   Correct the page container and reuse or extend the shared Settings card
   presentation. Preserve all existing controls, restrictions and handlers.
   The old primitives predate the diff; this is missing redesign work, not an
   introduced behavior regression. The author's extracted statement that
   SectionBlock “already matches” is contradicted by the component and canvas.
2. **P2 — Email and Website chat header typography differs from the approved
   originals.** Email:740 and Chat:761 use font weight 700; original title nodes
   `pT25z/rKF1T` and `phSnX/rKF1T` specify 36px, weight 900. Email:746 uses the
   16px large token for its description; the original specifies 14px. SMS already
   uses weight 900. Align these rules with the approved shared heading pattern.

No source-visible changes to provider logic, saving handlers, queries, permissions
or dialog controls were found. No fictional sample content was introduced.

## Evidence and limits

Independent Standards and Spec reviewers inspected the pinned diff. Parent and
Spec reviewer used read-only Pencil Get calls to confirm original root/card fills,
heading placement and typography. Relevant component implementations were read:
PageContainer, SectionBlock, DataTable and StatusBadge.

OpenCode's handover explicitly marks live browser checks deferred at Jafar's
request. It records one incidental Email load around 1010px in dark mode, and an
uninvestigated shell/theme error. This review ran no new browser automation.
SMS and Website chat still need live visual evidence; desktop light/dark and
browser-error checks remain pending. No typecheck, lint, tests, full build,
autofixer or full-project scan ran.

Outcome: Standards — 0 substantive findings. Spec — 2 design findings; page/card
structure is the larger correction. OpenCode should fix these under its held
claim, then record affected-screen evidence when browser checking resumes.
The branch is not yet merged or fully validated.
