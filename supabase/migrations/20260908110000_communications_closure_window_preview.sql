-- ---------------------------------------------------------------------------------------------------
-- Communications Part 8.3 -- the recoverable closure window.
--
-- 8.1 stopped a closing organization's outbound mail. The other half of the contract
-- (docs/contractor-email-contract.md, "Suspension, closure, and deletion") is what must NOT stop:
-- for the whole 30-day window the organization keeps its reply aliases, its receiving domains and
-- the provider resources behind them, so a customer who replies during the window still lands in the
-- right conversation and a restore finds the account intact. Nothing in the database removes those
-- today, and nothing here changes that -- the accompanying pgTAP file is the standing proof, because
-- the way that guarantee would break is a future cleanup sweep, not a missing feature.
--
-- What is missing is the second half: an owner who asks to delete permanently before the 30 days are
-- up is destroying live things, and the contract says they see what those are first -- active reply
-- aliases, queued messages, recent replies. This migration adds that preview as one read-only RPC so
-- the owner surface (8.5) and the purge path read the same numbers from the same place.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.preview_organization_closure_impact(
  target_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  organization_row public.organizations%rowtype;
  open_closure public.organization_closure_records%rowtype;
  -- Replies are counted from the moment closure started, because that is the window the owner is
  -- cutting short: mail that arrived while the account was already closing is exactly what an early
  -- delete throws away. With no open window there is nothing to cut short, so the preview falls back
  -- to the same 30 days the window itself would have covered and says so in its answer.
  replies_since timestamptz;
  active_alias_count integer;
  queued_message_count integer;
  recent_reply_count integer;
begin
  select * into organization_row
  from public.organizations
  where id = target_organization_id;

  if not found then
    raise exception 'Organization was not found.' using errcode = 'foreign_key_violation';
  end if;

  -- Matches organization_closure_records_one_open_idx, the partial unique index on the open window,
  -- so at most one row can come back here.
  select * into open_closure
  from public.organization_closure_records
  where organization_id = target_organization_id
    and status in ('pending_closure', 'purge_in_progress');

  replies_since := coalesce(open_closure.started_at, now() - interval '30 days');

  -- An alias is "active" while it can still route: past expires_at an inbound reply is already held
  -- for review rather than attached, so it is not something the delete takes away.
  select count(*)::integer into active_alias_count
  from public.communication_reply_aliases
  where organization_id = target_organization_id
    and expires_at > now();

  -- Everything the outbox has not finished with. 'failed' is included deliberately: a message parked
  -- for manual sender review is still unsent mail the owner would lose, not a closed outcome. Uses
  -- communication_outbox_events_organization_status_idx.
  select count(*)::integer into queued_message_count
  from public.communication_outbox_events
  where organization_id = target_organization_id
    and status in ('pending', 'processing', 'failed', 'submission_unknown');

  -- Uses communication_inbound_messages_org_created_idx.
  select count(*)::integer into recent_reply_count
  from public.communication_inbound_messages
  where organization_id = target_organization_id
    and created_at >= replies_since;

  return jsonb_build_object(
    'organization_id', target_organization_id,
    'lifecycle_status', organization_row.lifecycle_status,
    'closure_record_id', open_closure.id,
    'closure_started_at', open_closure.started_at,
    'closure_deadline_at', open_closure.deadline_at,
    'active_reply_aliases', active_alias_count,
    'queued_messages', queued_message_count,
    'recent_replies', recent_reply_count,
    'recent_replies_since', replies_since
  );
end;
$function$;

comment on function public.preview_organization_closure_impact(uuid) is
  'What an early permanent deletion would destroy right now: active reply aliases, unfinished queued messages, and replies received since closure started.';

revoke all on function public.preview_organization_closure_impact(uuid)
  from public, anon, authenticated;

grant execute on function public.preview_organization_closure_impact(uuid) to service_role;
