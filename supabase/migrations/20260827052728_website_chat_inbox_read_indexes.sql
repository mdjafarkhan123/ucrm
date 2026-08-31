-- WC4.5 Layer 2, performance gate: the two indexes the Communications inbox read needs from
-- website_chat_messages.
--
-- Layer 2 makes Website Chat the fourth source in /api/communications/email-history. Its shipped index
-- was written for "this Client's chat history" and was described as mirroring
-- communication_delivery_intents. It did not: both email tables carry TWO read indexes, and Website
-- Chat had only one of them.
--
--   communication_delivery_intents_client_created_idx   (organization_id, client_id, created_at, id)
--   communication_delivery_intents_inbox_read_idx       (organization_id, created_at, id)
--   communication_inbound_messages_org_client_created_idx (organization_id, client_id, created_at, id)
--   communication_inbound_messages_org_created_idx        (organization_id, created_at, id)
--
-- The inbox asks for one organization's newest messages across every contact, so client_id in the
-- second position cannot serve the ordering. Measured on 50,010 messages across 5,001 sessions -- the
-- realistic shape, a handful of messages per conversation rather than one enormous one:
--
--   inbox source, before   Seq Scan, 1,852 buffers, 48,011 rows scanned to return 51, 31.4 ms warm
--   inbox source, after    Index Scan, 144 buffers, 0.4 ms
--
-- The ratio is not the point. The first plan reads the whole table on every inbox load and grows with
-- it; the second stops after one page. At a few million messages the first is a multi-second scan
-- holding a pooled connection every time anyone opens Communications.
--
-- Both indexes are created non-concurrently: this table holds tens of rows today, so the brief lock is
-- measured in milliseconds. Rebuilding either one after real traffic arrives should use
-- CREATE INDEX CONCURRENTLY, outside a transaction.

-- 1. The inbox source ---------------------------------------------------------------------------------

-- Partial, unlike the email tables' equivalents, and deliberately so. A guarded inbound email has no
-- client and still belongs in the same query as everything else, so its inbox index covers every row. A
-- conflicting-identity chat session is addressed by session id instead and is read by its own bounded
-- query, so this predicate is present on every query that will ever use this index. Excluding those
-- rows is what turns 4,049 buffers into 144: without it the scan wades through unresolved rows it can
-- never return.
create index website_chat_messages_inbox_read_idx
  on public.website_chat_messages (organization_id, created_at desc, id desc)
  where client_id is not null;

comment on index public.website_chat_messages_inbox_read_idx is
  'One organization''s newest chat messages across every contact -- the Communications inbox merge. '
  'Partial because that read always excludes conflicting-identity sessions, which are addressed by '
  'session id through their own bounded query.';

-- 2. The per-contact read -----------------------------------------------------------------------------

-- The client Communication tab pages on (created_at desc, id desc), the app's keyset convention, but
-- this index stopped at created_at. Ties therefore could not be resolved from the index, and the
-- planner walked the org-wide index with a client_id filter instead: 4,047 buffers to return 26 rows,
-- against 141 once the tie-break column is present. communication_inbound_messages_org_client_created_idx
-- already has it; this is the same index, finished.
drop index public.website_chat_messages_organization_client_idx;

create index website_chat_messages_organization_client_idx
  on public.website_chat_messages (organization_id, client_id, created_at desc, id desc)
  where client_id is not null;

comment on index public.website_chat_messages_organization_client_idx is
  'One contact''s chat history, newest first, and the covering index for the '
  'website_chat_messages_client_fk foreign key. Partial: a message with no client_id has no key to '
  'check and belongs to a session still awaiting review.';
