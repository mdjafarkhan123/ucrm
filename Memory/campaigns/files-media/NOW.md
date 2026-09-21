# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** Part 4 — the File Manager workspace and the reusable File picker. Parts 1, 2, 3A and 3B are
complete and every migration is pushed.

**Exact next action:** Build Part 4 in a fresh session. Before any UI, load the `design` and `jobber` skills and
check `Design/Files and Media/` for the saved Jobber screenshots. The catalog, the upload/scan pipeline and the
480px JPEG previews all exist server-side; nothing reads them yet, and no `/api/files` list or detail route
exists.

**Blockers:** Part 4 cannot show an upload finishing in a running environment until deployment sets the values
in ROADMAP "Approval gates" (worker secret, scanner host/port, two Vault secrets, and the cron job that ships
switched off).

**Non-obvious risks:**

- **Open defect.** `files_available_means_verified_check` (Part 3A) is `not valid`, which exempts existing rows
  but still checks every new one, so `private.backfill_files_from_attachments` can no longer insert a legacy
  attachment as available. Part 5's re-sync depends on that function. The catalog pgTAP file stops there
  (41 of 49 assertions run, none failed). Jafar decided 2026-09-21 to fix it inside Part 5 rather than now:
  scope the constraint to Files whose key is under the pipeline's own `<org>/files/` prefix, which lets it be
  validated instead of exempted. Nothing is waiting to be backfilled today.
- Backfilled Files keep whatever thumbnail their old attachment had; only new uploads get a pipeline preview.
- The local ClamAV container reports unhealthy while clamd itself answers fine on TCP — its own health check
  uses the `LocalSocket` in `docker/clamav/clamd.conf`, which the app does not use.

**Pointers:**

- `docs/files-media-behavior-contract.md` — the whole approved model, the shipped allowlist, and the settled
  HEIC/video decisions
- `src/lib/server/files/` — policy, scanner, derivatives, worker
