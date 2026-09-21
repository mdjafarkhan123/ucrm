-- R1 live inbox: broadcast ids-only inbox activity to the staff org channel so an open Communications
-- inbox updates without a reload. This reuses the exact mechanism Website Chat already uses for staff
-- (see 20260906090000_website_chat_wc45_staff_commands.sql): a Postgres trigger calls `realtime.send`
-- inside the writing transaction, WAL-based and best effort, on the existing private topic
-- `wc-org:{organization_id}`. Staff-topic RLS (private.website_chat_staff_topic_permitted) already
-- authorizes that topic for members with conversations.view_team/view_assigned, so no new grants are
-- needed. The payload carries ids only, never a body: the client invalidates and re-reads through the
-- permission-filtered API, so a socket never routes around the assigned-only view.

-- Inbound email arrival -> tell the org an inbound message landed. Ids only.
create or replace function private.publish_communication_inbound_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform realtime.send(
      jsonb_build_object(
        'message_id', new.id,
        'client_id', new.client_id,
        'review_status', new.review_status
      ),
      'communication_inbox_activity',
      'wc-org:' || new.organization_id::text,
      true
    );
  exception
    when others then
      -- Best effort, like the Website Chat publisher: the message is already durable and the inbox's
      -- background revalidation and read-marks path pick it up. A Realtime outage must never fail the
      -- inbound write.
      null;
  end;
  return null;
end;
$$;

comment on function private.publish_communication_inbound_activity() is
  'Broadcasts ids-only inbox activity to the org staff topic when an inbound message arrives. Best '
  'effort: a publish failure never fails the write.';

revoke all on function private.publish_communication_inbound_activity()
  from public, anon, authenticated;

create trigger communication_inbound_messages_publish_activity
  after insert on public.communication_inbound_messages
  for each row
  execute function private.publish_communication_inbound_activity();

-- Outbound delivery state changes -> tell the org the message's status moved. The inbox status the user
-- sees is derived from BOTH `status` (queued -> claimed -> submitted -> failed/cancelled, moved by the
-- worker) AND `delivery_outcome` (delivered/bounce/complaint/deferred/blocked/unsubscribed, moved by the
-- provider-callback processor). Watching only one column would miss half the ladder -- in particular the
-- delivered/bounced transition, which is exactly what R1 must show live -- so the trigger watches both.
-- Opens/clicks never write `delivery_outcome` (the callback processor's guard excludes them), so this
-- fires only on real delivery-state transitions, not on engagement noise.
create or replace function private.publish_communication_delivery_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform realtime.send(
      jsonb_build_object(
        'intent_id', new.id,
        'client_id', new.client_id,
        'status', new.status,
        'delivery_outcome', new.delivery_outcome
      ),
      'communication_inbox_activity',
      'wc-org:' || new.organization_id::text,
      true
    );
  exception
    when others then
      null;
  end;
  return null;
end;
$$;

comment on function private.publish_communication_delivery_activity() is
  'Broadcasts ids-only inbox activity to the org staff topic when an outbound delivery intent changes '
  'status or delivery outcome. Best effort: a publish failure never fails the write.';

revoke all on function private.publish_communication_delivery_activity()
  from public, anon, authenticated;

create trigger communication_delivery_intents_publish_activity
  after update of status, delivery_outcome on public.communication_delivery_intents
  for each row
  when (
    new.status is distinct from old.status
    or new.delivery_outcome is distinct from old.delivery_outcome
  )
  execute function private.publish_communication_delivery_activity();
