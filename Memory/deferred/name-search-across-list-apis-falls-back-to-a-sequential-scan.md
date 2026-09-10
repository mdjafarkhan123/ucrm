# Leading-wildcard list search scales linearly

- **Priority:** P2
- **Why postponed:** Clients, Requests, Jobs and catalog search use leading-wildcard `ilike`; current tenant sizes
  are acceptable and the fix is cross-list schema work.
- **Reactivate when:** A tenant reaches thousands of rows, search latency appears, or shared search is redesigned.
- **Constraint:** Decide pg_trgm and indexes once across affected lists with schema approval.
- **Pointers:** Current Clients, Requests, Jobs and catalog list routes.
