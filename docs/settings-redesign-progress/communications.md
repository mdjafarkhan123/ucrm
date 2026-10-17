# Communications pages — build progress (group: communications)

**Branch:** `codex/settings-communications-app` · **Folder:** `/tmp/ucrm-settings-communications-app` ·
**Port:** 5214 · **Claim:** `8f01ab1601d5` (settings-communications-ui, settings-communications-progress)
**Brief:** `/tmp/ucrm-settings-approval/docs/settings-redesign-parallel-build.md` ·
**Design source:** `classic.pen` batch‑2 frames `QEixl` / `C70C3` / `fAAvd` (approved by Jafar 2026‑10‑17),
spec extracted in `communications-design-spec.md` next to this note.

## Route-by-route status

| Route (under `src/routes/(app)/settings/communications/`) | Status | Notes |
| --- | --- | --- |
| `email/+page.svelte` | Built, pending final validation | Header (breadcrumbs + informative icon tile, no back button / eyebrow / last-changed chip), usage meters restyled (green/`--color-warning` fills, reset line), `DataTable variant="card"` sender table with `Avatar`, dark Default chip, `StatusBadge size="compact"`, Edit behavior unchanged. `EmailSetupCard` untouched. |
| `sms/+page.svelte` | Built, pending final validation | Readiness fact row with dividers, registration groups re-laid (3-column grids, Messaging two-column, group icons), lower two-column row (Phone numbers + Holds stacked left, Compliance right), number rows with icon tile/badges/handlers unchanged. All conditional states preserved. |
| `website-chat/+page.svelte` | Built, pending final validation | Header, usage block with meter (only-numeric logic preserved), widgets `DataTable variant="card"` (icon tile, launcher cell, domain count, status pill, Edit). New/edit dialog untouched. Balance/blocked-addresses/templates/snippets were NOT in this batch (unassigned). |

## Evidence

- Svelte MCP `svelte-autofixer` on all three final files: zero issues (SMS: remaining suggestions target the
  pre-existing `$effect` hydration pattern kept verbatim to preserve typing-clobber behavior).
- Incidental (before Jafar stopped browser checks): the Email page loaded once at ~1010px in dark mode and
  rendered with real data (usage tiles, sender row with Default chip and Ready pill). No deeper browser check ran.
- Dev server log showed one unrelated client error (`TypeError: … waitForRepaint`, app shell/theme area);
  not investigated per instruction.

## Deferred at Jafar's request

TypeScript checks, svelte-check, lint, unit tests, production builds, full-project scans and the per-page
live browser checks (desktop 1440px, light + dark, console-error inspection, screenshots against the Pencil
frames). All deferred until the batch's wider screens are implemented.

## Known gaps / decisions to flag

- Header and card tables are page-local implementations of the approved frame pattern; a shared
  "Settings page header" piece could be requested from the Codex reviewer later to avoid per-page repetition.
- The shared `Breadcrumbs` part renders the "Settings" crumb as an interactive green link (its approved style);
  the frame shows neutral small text. Kept the shared part as-is.
- Framed tile radius uses `--radius-base` (the spec's `radius-control` token is Pencil-only).
- Holds "No active holds" notice uses the success surface per the frame's green check styling.
- No new behaviour, API, schema or permission change; all saving/validation/loading/empty/error states untouched.

## Next action

Leave the claim held; Codex parent reviews these three files and merges into main with the other
Settings groups. Deferred checks run after the batch's screens are all implemented.
