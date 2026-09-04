-- Schedule Part 7a-6: persist a manual route order.
--
-- On the contextual Map a dispatcher drags an employee's Anytime Visits into the sequence they want to drive
-- them. Until now that order lived only while the Map was open. This table remembers it.
--
-- What a saved order IS: a dispatch preference for ONE employee on ONE day -- "visit these stops in this
-- sequence". It records the ids of that route's stops in the chosen order. It is NOT an appointment-time
-- change: fixed-time Visits and every Assessment stay anchored to their clock, and the front end re-settles
-- those anchors into chronological order however the list was saved (see route-order.ts). So the saved order
-- only ever meaningfully moves the Anytime stops around the anchors.
--
-- A stop is a Visit or an Assessment, and those live in different tables, so the order cannot be a set of
-- foreign keys -- it is a plain list of ids. A stop that has since been deleted or moved off the day is simply
-- dropped when the order is applied (applySavedOrder), so no per-id referential integrity is needed or wanted.
--
-- Scope is (organization, employee, day): a shared Visit appears once in each employee's route at that
-- employee's saved position, which falls out naturally because each (employee, day) owns its own row.
--
-- Permission: saving is gated on jobs.schedule in the API layer, exactly like a visit move or a Schedule
-- Event -- it is a calendar-change authority. RLS here enforces tenant membership.

create table public.schedule_route_orders (
  organization_id uuid not null,
  -- The employee whose route this is. A composite foreign key to the membership guarantees the pair is a real
  -- member of this tenant and drops the saved order when they leave the organization.
  employee_id uuid not null,
  route_date date not null,
  -- The stop ids (Visit or Assessment) in the dispatcher's chosen order. Ids that have since gone are ignored
  -- on read, so this is a soft preference list, never a set of enforced references.
  stop_order uuid[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (organization_id, employee_id, route_date),
  constraint schedule_route_orders_member_fk
    foreign key (organization_id, employee_id)
    references public.organization_members (organization_id, user_id) on delete cascade,
  -- A day's route can hold no more stops than a day's window read returns (SCHEDULE_VISIT_LIMIT = 500), so
  -- this bounds the array against a runaway payload.
  constraint schedule_route_orders_stop_count check (cardinality(stop_order) <= 500)
);

comment on table public.schedule_route_orders is
  'The manual stop order a dispatcher saves for one employee on one day on the contextual Map. A dispatch '
  'preference (a list of Visit/Assessment ids in the chosen sequence), not an appointment-time change. '
  'Unknown ids are ignored when the order is applied. Gated on jobs.schedule in the API; RLS enforces tenancy.';

-- The read is always the whole primary key -- one employee, one day -- so the primary-key index is the only
-- access path and no secondary index is needed.

create trigger schedule_route_orders_set_updated_at
before update on public.schedule_route_orders
for each row execute function public.set_updated_at();

alter table public.schedule_route_orders enable row level security;

-- The lookup is a single-row primary-key hit, so RLS cost is negligible here; the membership check is still
-- wrapped in a select so it is evaluated once rather than per row, per Supabase's RLS guidance.
create policy "members can view route orders"
on public.schedule_route_orders for select to authenticated
using ((select private.is_organization_member(organization_id)));

create policy "members can create route orders"
on public.schedule_route_orders for insert to authenticated
with check ((select private.is_organization_member(organization_id)));

create policy "members can update route orders"
on public.schedule_route_orders for update to authenticated
using ((select private.is_organization_member(organization_id)))
with check ((select private.is_organization_member(organization_id)));

create policy "members can delete route orders"
on public.schedule_route_orders for delete to authenticated
using ((select private.is_organization_member(organization_id)));

grant select, insert, update, delete on public.schedule_route_orders to authenticated;
