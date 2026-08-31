-- Performance-review gate follow-up on 20260826090100/090200: get_advisors flagged two real FK-covering
-- gaps (the "index not used" and created_by/sender_id gaps are expected noise on a brand-new, empty
-- table and match existing precedent -- communication_delivery_intents has no created_by or sender_id
-- index either).
--
-- source_inbound_message_id: a real access pattern (showing whether/how a specific inbound message has
-- already been forwarded), not just FK-check coverage.
create index communication_forward_events_message_idx
  on public.communication_forward_events (organization_id, source_inbound_message_id);

-- inbound_attachment_id is the join table's second FK direction; org_event_idx only covers the first.
create index communication_forward_attachments_org_inbound_attachment_idx
  on public.communication_forward_attachments (organization_id, inbound_attachment_id);
