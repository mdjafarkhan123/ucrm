# Approved shared batches — active build

**Stage:** Batch 10 verified; next 11 and 12; batches 5 and 6a merged and pushed.
**Workspace:** codex/concept-batch5, /home/jafar/Ucrm/.worktrees/concept-batch5.
**Claim:** 3bd922d6becc, codex-shared-remaining.

Use the approvals and component scope in c5-shared-parts.md, and the design modules there. Pencil stays read-only.

Approach: extend the existing shared components and preserve their public callers, permissions, query invalidation, validation and writes. Approved additions only: quick dates/duration (done); price-book live preview, photo-card grouping and per-opening added count; file-picker tray/unpick. Time-clock styling keeps server offset, one-running-timer rules and recovery. No schema or infrastructure changes. TanStack owns server data; single-result and paged queries must use distinct keys. Existing Bits primitives retain focus and keyboard handling.

Failure paths: price-book item saved/photo failed must retry that item rather than create another; hidden cost never appears in the preview; stale managed edits keep reload. File attachments retain partial refusal and retry only refused ids; selection/tray must survive sections and pages. Label and caption writes show busy until finished. Timer writes remain busy through query refresh and failures stay visible.

Checks: SCSS-preprocessed compiler and MCP autofixer, focused ESLint, relevant existing tests, browser fixtures at 1440/390 light/dark, then main journey on the actual owner app. Merge each completed batch into main under a separate integration reservation and push. Remove fixtures. Evidence goes under docs/evidence/2026-10-20-batchN.

**Next:** merge and push batch 10; release its claim before claiming batch 11. Remaining batch approvals are unchanged.
