-- Four composite foreign keys outside the Quotes campaign that share the same mistake Part 2 fixed in
-- 20260820070305_pricing_set_null_clears_only_the_reference.sql: `on delete set null` without a column list
-- nulls every column in the key, including the paired `organization_id`, which is `not null`. Deleting the
-- referenced row would fail with `23502: null value in column "organization_id"` instead of quietly clearing
-- the reference. Postgres 15 added the column list this needs, and this project runs 17.
--
-- Logged in Memory/deferred/four-older-composite-foreign-keys-still-null-the-organization-on-delete.md;
-- this closes that item.

alter table public.client_contact_methods
  drop constraint client_contact_methods_contact_organization_fk;

alter table public.client_contact_methods
  add constraint client_contact_methods_contact_organization_fk
  foreign key (organization_id, client_contact_id)
  references public.client_contacts(organization_id, id)
  on delete set null (client_contact_id);

alter table public.property_contact_methods
  drop constraint property_contact_methods_contact_organization_fk;

alter table public.property_contact_methods
  add constraint property_contact_methods_contact_organization_fk
  foreign key (organization_id, property_contact_id)
  references public.property_contacts(organization_id, id)
  on delete set null (property_contact_id);

alter table public.opportunities
  drop constraint opportunities_current_outcome_event_fk;

alter table public.opportunities
  add constraint opportunities_current_outcome_event_fk
  foreign key (organization_id, current_outcome_event_id)
  references public.opportunity_outcome_events(organization_id, id)
  on delete set null (current_outcome_event_id);

alter table public.tasks
  drop constraint tasks_outcome_event_organization_fk;

alter table public.tasks
  add constraint tasks_outcome_event_organization_fk
  foreign key (organization_id, completed_by_outcome_event_id)
  references public.opportunity_outcome_events(organization_id, id)
  on delete set null (completed_by_outcome_event_id);
