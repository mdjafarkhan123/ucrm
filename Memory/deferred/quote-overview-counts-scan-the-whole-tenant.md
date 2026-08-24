# Quote Overview counts scan the whole tenant

- **Priority:** P2


- **Campaign:** `quotes` Part 3A, deferred 2026-08-20 after its performance review.
- **Reason:** `public.quote_status_counts` counts live, the way Jafar chose for the Requests card. Measured on
  the dev project at 20,000 quotes in one organization: Seq Scan, 769 buffers, 12.9 ms per call. A narrow
  `(organization_id, status)` index was measured and made it worse, so no index was added.
- **Reactivation trigger:** a tenant passes roughly 50,000 quotes, or the call shows up in Supabase Query
  Performance above 100 ms mean.
- **Prerequisites:** copy the Pipeline's precomputed approach (`pipeline_stage_counts_read_model`) rather than
  inventing a second one, and decide refresh timing against how stale the Overview card may be.

