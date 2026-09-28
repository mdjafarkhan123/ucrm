# File Manager search cannot use an index

**Why it waits:** `list_files` matches a file's name, its caption, or a linked record's name in one condition,
so Postgres scans every file in the organization whatever index exists. Fine at today's file counts. Split
out of the trigram name-search work on 2026-09-28.
**Brings it back:** File Manager search is reported slow, or an organization passes roughly 50,000 files.
**Known constraints:** restructure `list_files` first (e.g. search each part separately and combine the
results), then add a trigram index on `files (organization_id, display_name, caption)` like the ones in
`20260929130000_trigram_name_search.sql`.
