-- Corrective migration: the 6A suspension_category check constraint only tolerated a category on
-- 'organization_suspended' events. Part 6E's 'pending_setup_resolved' event also needs to carry a
-- category when the reconciliation outcome is suspend, and must carry none when it is activate.

alter table public.organization_commercial_events
  drop constraint organization_commercial_events_suspension_check;

alter table public.organization_commercial_events
  add constraint organization_commercial_events_suspension_check check (
    case event_kind
      when 'organization_suspended' then suspension_category is not null
      when 'pending_setup_resolved' then true
      else suspension_category is null
    end
  );
