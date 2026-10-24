-- Index the message tables' link to a customer's phone or email (docs/data-privacy-deletion-engine.md,
-- Performance verification at a 1M-text business, 2026-10-24).
--
-- Deleting a contact method makes Postgres check its ON DELETE RESTRICT links from delivery intents and inbound
-- messages. Those foreign keys are (organization_id, client_contact_method_id) with no index, so the check could
-- only narrow by organisation: in a business holding most of the table the planner read every row. Measured on a
-- local copy with 1.5M texts (1M in one business): each permanent delete read 3.6M rows for its two contact
-- methods. With these indexes the reads are gone and the delete fell from 1.6-2.2 s to 1.2 s. Partial, because
-- messages with no contact method never take part in the check.

create index communication_delivery_intents_contact_method_idx
  on public.communication_delivery_intents (organization_id, client_contact_method_id)
  where client_contact_method_id is not null;

create index communication_inbound_messages_contact_method_idx
  on public.communication_inbound_messages (organization_id, client_contact_method_id)
  where client_contact_method_id is not null;
