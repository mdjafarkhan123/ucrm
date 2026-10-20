# Approved shared batch 9 — 2026-10-20

Reference: `concept.pen` board `KuOmH` (read-only screenshots), `design/notes.md` and `design/files.md`. Existing shared components retain server routes, save timing and permissions. No new provider, database or product behavior.

Changes: author names over times with Edited tags and keyboard-accessible exact-time tips; teal mention emphasis; 96×72 note photos and wrapping document chips; labelled Add on record file cards; pending-file photo badges, document progress rings, save counts and red-edged failures with busy retry. Removed old compact NotesPanel overrides so shared author and body styles reach record pages.

## Focused checks

- Svelte compiler with the project's SCSS preprocessing: **all seven changed components passed, zero warnings**.
- Svelte MCP autofixer on preprocessed components: **no issues**. Retained pre-existing function-valued derived lookup helpers in NotesPanel (callers need functions), pending-count notification effect (synchronizes the parent's dirty state), and input DOM reference (opens the file selector).
- Focused ESLint on the seven components: **passed**.
- `git diff --check`: **passed**.
- Browser fixture at **1440 and 390**, **light/dark**: author, Edited tag, long text and names, teal mentions, available/checking photos and documents, staged photos and documents. No horizontal overflow or page errors. Screenshots included.
- Browser assertions: download busy and disabled; rejected file removed; pending file removed; empty state restored; viewer opens and Escape closes. Mocked upload: first attempt fails, Retry shows busy/disabled, second attempt completes, queue empties; exactly two attempts. No storage/database write in this fixture.
- Visual fixes during review: compact author layout override, pending badge wrapping, checking photo fill, always-visible photo removal.

No full build, full TypeScript check, project-wide lint or test suite. No capacity claim or storage scanning revalidation. Temporary fixture is removed before commit. Main integration remains pending until the main workspace is released by the Pencil designer.

## Live branch app

Signed in through the real login as the existing Raad LTD Owner on localhost:5175. Opened existing client WC4 Check1 and its Notes / Photos and files cards. On New client, selected a PDF and a refused executable, removed the refused file, saw the remaining **Not saved** document, removed it, and confirmed the empty message returned. No client was saved, no file uploaded, no page errors. Screenshots: `live-client.png`, `live-new-client-files.png`.
