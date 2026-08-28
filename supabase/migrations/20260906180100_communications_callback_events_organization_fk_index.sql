-- Part 7.1 follow-up: the org-scoped reputation index on communication_provider_callback_events is
-- partial (processed_at is not null), so it cannot cover the ON DELETE CASCADE from organizations for
-- rows that are still unprocessed. A plain FK index does.

create index communication_provider_callback_events_organization_idx
  on public.communication_provider_callback_events (organization_id)
  where organization_id is not null;
