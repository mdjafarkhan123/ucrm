-- Part 5C-iii: dropping a Request card onto Draft turns it into a Quote.
--
-- The drag gate is the authority on which moves exist, and it did not know about this one, so the route
-- could not have dispatched a conversion no matter what it asked for. Nothing else changes: the command
-- that does the work (`public.convert_request_to_quote`) already exists and already owns its own
-- permission check, its own idempotency, and its own status allow-list.
--
-- Three pairs, not four. `assessment_scheduled` is deliberately absent: a request with a booked visit is
-- not convertible -- `convert_request_to_quote` refuses status `scheduled`, and the board must refuse it
-- at the drop rather than letting somebody drag a card only to be told no. This is what makes Draft a
-- per-card drop target inside the collapsed Assessment column instead of a per-column one.
--
-- Forward-only and single-command, the same rule the existing six pairs follow. Conversion is confirmed
-- in the browser before it is asked for, because it is terminal: the request becomes `converted` and a
-- Quote now exists.

create or replace function private.pipeline_drag_transition_allowed(from_stage text, to_stage text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select (from_stage, to_stage) in (
    ('new_request', 'assessment_unscheduled'),
    ('new_request', 'assessment_scheduled'),
    ('assessment_unscheduled', 'assessment_scheduled'),
    ('assessment_unscheduled', 'assessment_completed'),
    ('assessment_scheduled', 'assessment_completed'),
    ('new_request', 'quote_draft'),
    ('assessment_unscheduled', 'quote_draft'),
    ('assessment_completed', 'quote_draft'),
    ('quote_draft', 'quote_awaiting_response')
  );
$$;

revoke all on function private.pipeline_drag_transition_allowed(text, text) from public;

comment on function private.pipeline_drag_transition_allowed(text, text) is
  'Part 5B, widened by 5C-iii. The closed list of drags the board allows. Each pair is satisfiable by one '
  'existing domain command; the command still applies its own rules underneath. assessment_scheduled has '
  'no path to quote_draft because a request with a booked visit is not convertible.';
