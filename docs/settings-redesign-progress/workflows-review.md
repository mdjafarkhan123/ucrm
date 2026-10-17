# Claude Settings review — 2026-10-17

Reviewed `codex/settings-workflows-app` at `3a56eb88` against its implementation
base `df26dc1d`: commits `2b672e3d` and `3a56eb88`. Five routes: Price book,
Pipeline settings, Checklists, Automation index and Request forms index.

## Standards

No confirmed substantive violation affecting data ownership, permissions, query
ownership or persistence was found in the changed source. Existing mutations,
permission gates and save handlers remain. Component-local SCSS/BEM, existing
controls and Tabler icons are reused.

One minor wording correction: `src/routes/(app)/settings/pipeline/+page.svelte:546`
adds “Nothing is saved until you press Save,” while Lost reasons on the same page
still save immediately. Restrict that reassurance to the staged stage/assessment
settings. This is newly misleading copy, not a newly introduced persistence bug.

No judgement-call maintainability smell warrants a separate finding. Header reuse
across concurrent groups is an integration follow-up: consolidate WorkflowPageHeader
with the shared Settings presentation, preserving actions and semantic tones.

## Spec

Two minor differences from the approved original Automation frame `n0kJri`:

1. `src/routes/(app)/settings/automation/+page.svelte:127` makes Paused grey via
   `inactive`; original status node `g2X8N` uses the warning surface/text/dot. Restore
   the approved yellow. The original approval already settles this visual choice.
2. `src/routes/(app)/settings/automation/+page.svelte:265` renders the list title
   without its approved yellow robot tile (`Q4nwK` / `lER1H`). Add the existing
   icon presentation without duplicating the list component.

Governing agreement: the campaign contract requires “every screen already designed
in Pencil … is built in the app”; Jafar approved the original Settings designs.
No grounded introduced change to permissions, filtering or save behaviour was found.

## Browser evidence and limits

`node /tmp/settings-workflows-review-browser.cjs` opened all five routes from the
real owner session on port 5215, at 1440×1100, in light and dark mode. Every route
loaded without document-width overflow. No page exceptions were reported. Price
book's existing photo returned HTTP 409, also named in Claude's handover; the other
four pages reported no console errors. A first capture attempt stopped at the two
Pipeline h1 elements; the capture locator was corrected to select the first one.
The app's original form header is CSS-hidden; this is not reported as a UI defect.

Fresh screenshots: `/tmp/workflows-review-{price-book,pipeline,checklists,automation,forms}-{light,dark}.png`.
The parent inspected these against the original approved direction and Claude's
earlier screenshots. Pencil read-only inspection confirmed Automation's status and
heading icon. Source reviewers ran independently for Standards and Spec.

Numeric automation allowance, additional roles and full mutation journeys remain
unproven. Phone-width concerns are outside this desktop-only campaign. The
hardcoded Needs attention zero predates this diff; it is not an introduced finding.
Type checks, lint, automated tests, autofixer and full builds remain deferred at
Jafar's request. No settings writes or invitations were made for this review.

Outcome: Standards — one minor wording correction, no confirmed substantive
violation. Spec — two minor visual corrections. Apply corrections, consolidate the
shared heading during integration, then recheck only affected screens. The branch
is not yet merged or fully validated.
