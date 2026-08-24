# Client duplicate detection, merge, archive, restore, and audit history

- **Priority:** P2


- **Campaign:** `clients-properties` Part 8, deferred out of scope on 2026-08-17.
- **Reason:** Buildable today, but worth far more once clients carry real work — merge and archive are mostly
  about what happens to the work attached to a client, and there is none yet.
- **What exists now:** Create-time duplicate warnings only, using unindexable `ilike '%term%'`, bounded per
  organization and capped at 5 rows. Fine at this size; real fuzzy matching needs `pg_trgm` and Jafar's
  approval. There is no merge, no archive, no restore, and no audit history.
- **Reactivation trigger:** Clients carry requests, quotes, jobs or invoices, or Jafar reports real duplicates
  in live data.
- **Prerequisites:** A transactional merge must move every child row without history loss or tenant crossing.
- **Checkpoint:** `src/routes/api/clients/`, `docs/client-property-behavior-contract.md`.

