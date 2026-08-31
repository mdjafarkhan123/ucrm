create index if not exists quotes_decided_by_idx on public.quotes(decided_by) where decided_by is not null;

create or replace function public.publish_quote(
  target_quote_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  published_row public.quote_versions;
  draft_row public.quote_versions;
  priced_line_count integer;
  frozen jsonb;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.send'
     ) then
    raise exception 'You do not have access to send this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status = 'awaiting_response' then
    select * into published_row from public.quote_versions
    where id = quote_row.current_published_version_id;
    if published_row.id is not null and published_row.revision = expected_revision then
      return jsonb_build_object(
        'quote_id', quote_row.id, 'quote_version_id', published_row.id,
        'version_number', published_row.version_number, 'document_hash', published_row.document_hash,
        'sent_at', quote_row.sent_at, 'status', quote_row.status,
        'calculation', published_row.calculation, 'already_published', true
      );
    end if;
  end if;

  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be sent.' using errcode = 'check_violation';
  end if;

  select * into draft_row from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'draft'
  for update;

  if draft_row.id is null then
    raise exception 'This quote has no draft to send.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  select count(*) into priced_line_count
  from public.quote_version_lines
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and quote_version_id = draft_row.id
    and line_kind = 'priced';
  if priced_line_count = 0 then
    raise exception 'Add at least one line before sending this quote.' using errcode = 'check_violation';
  end if;

  frozen := public.freeze_quote_version(quote_row.id, expected_revision);

  update public.quotes
  set status = 'awaiting_response',
      sent_at = coalesce(sent_at, now()),
      decision = null, decided_at = null, decision_method = null,
      decision_note = null, decided_by = null
  where id = quote_row.id
  returning * into quote_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.published',
    'Sent version ' || (frozen ->> 'version_number') || ' to the customer',
    (select auth.uid()),
    jsonb_build_object(
      'quote_version_id', frozen ->> 'quote_version_id',
      'version_number', (frozen ->> 'version_number')::integer
    )
  );

  return frozen
    || jsonb_build_object('sent_at', quote_row.sent_at, 'status', quote_row.status,
                          'already_published', false);
end;
$$;

revoke all on function public.publish_quote(uuid, integer) from public;
revoke execute on function public.publish_quote(uuid, integer) from anon;
grant execute on function public.publish_quote(uuid, integer) to authenticated;
