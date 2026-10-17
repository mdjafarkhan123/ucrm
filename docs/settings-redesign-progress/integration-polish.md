# Settings integration polish

Status: implementation recovered and ready to merge into the combined Settings branch.

## Changes

- Replaced the separate business, workflow and communications page headings with one shared component that keeps each approved presentation.
- Corrected the Automation paused badge, added its heading icon tile, and narrowed the Pipeline save message to the fields that wait for Save.
- Restored the SMS readiness facts to a two-column layout at medium widths and a stacked readiness row.
- Added the approved plus icons to Email sender and Website Chat widget actions, and changed the chat usage meter to a capsule shape.

## Review

- `git diff --check` passed.
- Source review confirmed the warning color tokens are already used elsewhere in the app.
- The local Vite preview could not bind to a port (`listen EPERM`), and Chromium could not start in this shell. No screenshot review of these final shared-header edits was possible here.
- No type checks, tests, lint, or build were run, per Jafar's instruction to defer those until the screens are implemented.

## Next

Merge this branch into `codex/settings-batch-integration`, then complete a lightweight visual review when a browser preview is available. The combined branch remains pending integration into `main`.
