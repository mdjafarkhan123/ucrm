# Client archive and restore are not written to the client's history

- **Priority:** P3

**Why it waits:** merge (2026-09-28, `merge_clients`, audited in `client_merges` and the timeline) and
archive/restore (Part 6B) are built. Archive and restore still leave no line in the client's timeline, which
the client contract's "Delete, restore, purge, archive, unarchive, and merge are audited" asks for. Duplicate
detection stays create-time exact/similar warnings only; there is no "find my duplicates" list, and Jobber has
none either.
**Brings it back:** Jafar asks who archived a client, or the client-history work.
