# Leading-wildcard list search scales linearly

- **Priority:** P2
- **Why postponed:** Clients, Requests, Jobs and catalog search use leading-wildcard `ilike`; current tenant sizes
  are acceptable and the fix is cross-list schema work.
- **Reactivate when:** A tenant reaches thousands of rows, search latency appears, or shared search is redesigned.
- **Constraint:** Decide pg_trgm and indexes once across affected lists with schema approval.
- **Pointers:** Current Clients, Requests, Jobs and catalog list routes.

Also known (2026-09-25): the File Manager's caption/name search (`public.list_files`) has the same shape —
`file.display_name ilike` / `file.caption ilike` with no backing index. Measured on a schema-identical local
rebuild at 25,000 files in one organization: a common term matches in ~10ms, but a rare or non-matching term
costs ~50ms because it must walk nearly the whole organization's un-trashed files before giving up. Fine at
this size; add it to the pg_trgm decision above if a real organization's file count grows enough to notice.
