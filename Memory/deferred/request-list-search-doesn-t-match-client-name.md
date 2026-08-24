# Request list search doesn't match client name

- **Priority:** P2


- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Jafar didn't decide during the browser pass whether to add it; not blocking real use.
- **What is wrong:** The list search only queries `title` and `service_type`
  (`src/routes/api/requests/+server.ts`). Searching "Priya" finds nothing even though she has requests;
  searching her request's title does. Jobber's request search matches client name too.
- **Reactivation trigger:** Jafar reports the search missing a client he expected to find, or asks for it.
- **Prerequisites:** Join to `clients.display_name` (and `company_name`) in the existing `.or()` filter;
  check the query plan once request volume is non-trivial.
- **Checkpoint:** `src/routes/api/requests/+server.ts`.

