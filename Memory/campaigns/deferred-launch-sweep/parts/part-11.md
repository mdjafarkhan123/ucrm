# Part 11 — Speed on client pages

**Campaign:** deferred-launch-sweep · **Plan:** none — behavior unchanged; speed only
**Code:** `main`
**Done when:** a file list draws its photos with one request, and the side tables a client page reads
(timeline, notes, attachments, tags, client contacts, invoice history, schedule events) no longer re-run the
permission check per row for full-access members — same rows visible for every role, measured before/after.

## Steps

- [x] Photos: file lists hand out signed R2 links (committed "perf: file lists hand out signed photo links");
      verified live on Raad — 12 photos straight from R2, fallback to /view when a link fails.
- [ ] RLS: snapshot visible-row counts per table for owner, field, office, sales, finance (Raad)
- [ ] RLS: one migration — `private.current_linked_entity_view_types()` + hoisted policies
- [ ] RLS: re-count (must match exactly), EXPLAIN before/after, commit
- [ ] Close both deferred notes; finish part

## Next

Snapshot visible-row counts per role before writing the migration.

## Outside actions

- RLS migration push — check: `supabase migration list --linked` shows the new version — pending

## Notes

- The old `AttachmentsCard` is only on a dev-preview page; client pages use `RecordFilesCard` (Files).
- Clients, properties, requests, jobs, invoices, files, file_links SELECT policies were already hoisted.
- Baseline: one quote's 24 timeline rows = 31 ms / 1840 buffers as owner (per-row `can_view_linked_entity`).
