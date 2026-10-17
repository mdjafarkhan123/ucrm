# Communications Settings — handover to Claude

Jafar explicitly transferred OpenCode's three pages to Claude on 2026-10-17.

**Worktree:** `/tmp/ucrm-settings-communications-claude`
**Branch:** `codex/settings-communications-claude`
**Claim:** `e54334278ed5`, owner `claude-settings-comms`, areas
`settings-communications-ui` and `settings-communications-progress`.
The claim is already reserved for this handover; use it rather than claiming again.
OpenCode's prior claim `8f01ab1601d5` was released. Its clean branch and pushed
implementation `c1405242` remain preserved as the starting point.

## Work to finish

Read `AGENTS.md`, the campaign's core contract, relevant design/Svelte skills and
`docs/settings-redesign-progress/communications-review.md` before editing. Inspect
the original live Pencil frames through MCP, read-only: Email `QEixl`, Phone & SMS
`C70C3`, Website chat `fAAvd`. The extracted communications-design-spec.md contains
an incorrect claim that default SectionBlock already matches; the review corrects it.

1. Apply independent white cards on the app background, replacing the old padded
   white sheet. Place card headings/actions inside their cards, replacing the old
   notched border presentation. Include SMS Readiness's original horizontal strip.
2. Match the original Email/Chat title typography (36px, weight 900), Email
   description 14px and all other approved frame details.
3. Preserve current logic, queries, permissions, registration locks, field bindings,
   save/submit handlers, dialogs and loading/empty/error states. Build on existing
   implementation; this is a visual correction, not a new communications feature.

Scope is only these three page files and the communications progress note. Parent
owns shared UI; request shared component edits first. Parent shared presentation
commit `a309defa` is available as a reuse option; coordinate its adoption/any tone
extensions with Codex. Keep global styles, providers and database untouched.

Jafar deferred typecheck, lint, tests, builds, autofixer and expensive validation.
OpenCode also recorded browser checks deferred. Keep those deferrals; report the
remaining live evidence gap instead of claiming full validation. Use port 5214
only if browser checking resumes and its old preview is free.

Commit/push corrections, update communications.md with exact coverage and remaining
gaps, and return the branch to Codex for review. Leave merging to Codex and keep
the claim through handoff/integration. No work has been performed by Claude merely
because this handover file and reservation exist.
