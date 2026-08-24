# `EntityType` covers only clients and properties

- **Priority:** P2


- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** Nothing else exists to attach notes, tags or files to yet.
- **What is missing:** `EntityType` in `src/lib/collaboration/api.ts` lists `client` and `property` only.
  Requests, quotes, jobs and invoices each need it extended plus a matching database check constraint before
  their pages can attach anything.
- **Reactivation trigger:** The first non-client, non-property page needs notes, tags or attachments.
- **Prerequisites:** Extend the union and the database check in the same migration, or attachments will fail
  at write time with a constraint error.
- **Checkpoint:** `src/lib/collaboration/api.ts`.

