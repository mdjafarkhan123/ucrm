-- Performance review: claim_communication_inbound_attachment_imports orders by (created_at, id) but the
-- queue index led with claimed_at, which doesn't serve that ORDER BY -- it would force a sort (or a full
-- partial-index scan with no ordering benefit) instead of an in-order index scan. The claimed_at OR
-- condition (null or older than the stale threshold) is cheap to apply as a row filter once the partial
-- index has already narrowed the scan to pending_import rows in created_at order.

drop index public.communication_inbound_attachments_import_queue_idx;

create index communication_inbound_attachments_import_queue_idx
  on public.communication_inbound_attachments (created_at, id)
  where status = 'pending_import';
