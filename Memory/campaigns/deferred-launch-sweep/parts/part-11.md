# Part 11 — Speed on client pages

**Campaign:** deferred-launch-sweep · **Plan:** none — behavior unchanged; speed only
**Code:** `main`
**Done when:** a file list draws its photos with one request, and the side tables a client page reads
(timeline, notes, attachments, tags, client contacts, invoice history, schedule events) no longer re-run the
permission check per row for full-access members — same rows visible for every role, measured before/after.

## Steps

- [x] Photos: file lists hand out signed R2 links (committed "perf: file lists hand out signed photo links");
      verified live on Raad — 12 photos straight from R2, fallback to /view when a link fails.
- [x] RLS: snapshot visible-row fingerprints, 17 tables × 8 users (Raad roles + two other orgs)
- [ ] RLS: one migration — `private.current_linked_entity_view_types()` + hoisted policies
- [ ] RLS: re-count (must match exactly), EXPLAIN before/after, commit
- [ ] Close both deferred notes; finish part

## Next

Migration `20260929150000_side_table_permission_checks_run_once_per_query.sql` written; verify it applied, then re-fingerprint (snapshot SQL: DO block per user, `set local role authenticated` + jwt claims, md5 of rows) and compare. Owner full timeline before: 508 ms / 7791 buffers.

## Outside actions

- RLS migrations `20260929150000` (applied, rows identical) and `20260929160000` — check: `supabase migration list --linked` shows both

## Notes

- The old `AttachmentsCard` is only on a dev-preview page; client pages use `RecordFilesCard` (Files).
- Clients, properties, requests, jobs, invoices, files, file_links SELECT policies were already hoisted.
- Baseline: one quote's 24 timeline rows = 31 ms / 1840 buffers as owner (per-row `can_view_linked_entity`).
