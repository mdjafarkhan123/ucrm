# Approved shared batches 7–8 — 2026-10-20

Built from approved Pencil boards `eJ0QQ` and `b4BxuV`, inspected read-only. Existing shared components apply their approved appearance at all callers. PencilButton already used the approved shared icon button; its accessible name, title and disabled appearance were checked. Other changes cover counted list footers, form error cards, number cards, paper document previews, photo slots, the photo viewer and the upload queue.

## Focused checks

- Changed Svelte preprocessing/compilation: **36 files passed**, no compiler warnings. Used Svelte's installed compiler and the project's SCSS preprocessor against only changed files.
- Focused ESLint on the eight shared components: **passed**. Fixed unused props found during the first pass.
- Svelte MCP autofixer: **no issues**. Retained existing DOM references for field focus/file selection and the viewer's DOM-scrolling effect; its effect does not assign reactive state.
- `git diff --check`: **passed**.
- Browser fixture at 1440 and 390 CSS pixels in light/dark mode: count footer, final/search state, error checklist, number-card tones, edit buttons, file families, pending/failed/quarantined previews, empty/disabled/uploading/filled photo slots, long names, and the viewer. Screenshots included. Fixed the primitive close button's styling and photo-tool contrast during review.
- Browser interaction assertions passed: Load more becomes busy and disabled, field links focus their field, viewer arrow keys and Escape work, download becomes busy and disabled.
- Mocked upload transport checked active/failed/checking states and retry: **passed**, exactly two attempts for the retried file. No storage or database write occurred in this fixture. Failed item removal/clear and rejected type/empty-file messages checked. Percent rings and batch progress remain based on the existing upload progress callbacks.

## Live app proof on the branch

Signed in through the real login as the existing Raad LTD Owner, on localhost:5174:

1. Jobs displays **All 17 jobs are showing** (`jobs-footer-light.png`).
2. Automation displays real Active / Paused & drafts / Needs attention counts in the approved number cards (`automation-light.png`).
3. Files displays existing photos and pending files. Selecting a refused `.exe` produces the failure card; Clear removes it (`files-failure-light.png`). No file was uploaded by this test.
4. Opened existing `kitchen-photo.png` → Open full size; real stored image, caption and count appear. Arrow navigation and Escape work (`real-photo-viewer.png`). The small gradient is the existing test image itself.
5. New job → Save with no client: the summary displays **Choose a client to continue**, scrolls into view and receives focus (`job-form-error.png`). No job was saved.

No page errors were observed. The test-only fixture route and local authentication state were removed afterward.

## Limits and handoff

No full build, full TypeScript check, whole-project lint/test suite, performance audit or capacity claim. This is shared-control verification; it does not certify every page's full layout. Successful storage scanning and provider delivery were not retested because their code did not change. Jafar confirmed main released on 2026-10-20. Batches 7–8 were merged into main, preserving the newer batches 9–11 design approvals. The temporary integration handoff has been closed.


## Integrated main check

Signed in through the real login on the main app (localhost:5173, the same server used by the tunnel). Jobs showed **All 17 jobs are showing**, Automation showed **3** number cards with real counts, and Files rendered **27** file pictures. No browser page errors. Screenshots: `main-jobs-footer.png`, `main-automation.png`. `git diff --check` passed. No app code changed during integration, so the already-passing focused compiler, lint and interaction checks were not repeated.
