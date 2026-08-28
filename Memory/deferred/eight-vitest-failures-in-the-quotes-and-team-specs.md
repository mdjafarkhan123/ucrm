# Quote route tests lack the RPC mock

- **Priority:** P1
- **Why postponed:** Six quote.spec.ts failures come from locals.supabase missing rpc while the route calls quote_ready_for_job; unrelated earlier Team and tax failures are resolved.
- **Reactivate when:** Quotes next runs its suite or a green full suite is required.
- **Constraint:** Repair the test mock to match the route; do not change production behavior to satisfy it.
- **Pointer:** src/routes/api/quotes/[id]/quote.spec.ts.
