# Website Chat live-connection ceiling: re-test on the VPS

- **Priority:** P2
- **Why postponed:** Live testing accepted about 600 open chat sockets before refusals. Supabase's published
  limit for Pro with a spend cap is 500 concurrent Realtime connections (Pro without a cap and Team: 10,000;
  checked 2026-09-28, supabase.com/docs/guides/realtime/limits), so ~600 fits that cap plus enforcement slack (plan tier itself not read from the dashboard).
  The pool is shared: every staff browser tab using live updates counts too, not only chat panels.
- **Reactivate when:** The staging VPS runs self-hosted Supabase (crm-launch-readiness). There the ceiling is
  our own Realtime setting, so repeat the admission test against it; managed numbers no longer apply.
- **Constraint:** Limits simultaneously open panels and tabs, not stored conversations or message throughput.
- **Pointer:** Realtime admission test from the original measurement; `too_many_connections` is the refusal.
