-- Supports the composite Website Chat widget foreign key so widget updates and deletes do not
-- scan the owner-only authority history table.

create index communication_website_chat_authority_events_widget_fk_idx
  on public.communication_website_chat_authority_events (organization_id, widget_id)
  where widget_id is not null;
