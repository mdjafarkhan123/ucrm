\set ON_ERROR_STOP on
begin;
DO $$
declare r record; n integer; stamp timestamptz := clock_timestamp();
begin
 select id,organization_id,updated_at into strict r from public.communication_messenger_connections where status='active' order by id limit 1 for update;
 update public.communication_messenger_connections set last_checked_at=null where id=r.id;
 update public.communication_messenger_connections set last_checked_at=stamp
 where id=r.id and organization_id=r.organization_id and status='active' and updated_at=r.updated_at
 and (last_checked_at is null or last_checked_at<=stamp-interval '1 hour');
 get diagnostics n=row_count;
 if n<>1 then raise exception 'first claim failed'; end if;
 update public.communication_messenger_connections set last_checked_at=stamp
 where id=r.id and organization_id=r.organization_id and status='active' and updated_at=r.updated_at
 and (last_checked_at is null or last_checked_at<=stamp-interval '1 hour');
 get diagnostics n=row_count;
 if n<>0 then raise exception 'duplicate claim succeeded'; end if;
 update public.communication_messenger_connections set updated_at=stamp+interval '1 second',last_checked_at=stamp+interval '1 second' where id=r.id;
 update public.communication_messenger_connections set status='needs_reconnect',needs_reconnect_reason='token_invalid'
 where id=r.id and organization_id=r.organization_id and status='active' and updated_at=r.updated_at and last_checked_at=stamp;
 get diagnostics n=row_count;
 if n<>0 then raise exception 'stale health overwrote reconnect'; end if;
 raise notice 'PASS: single claim, overlapping claim skipped, reconnect wins';
end $$;
explain (analyze,buffers) select id,organization_id,page_id,updated_at from public.communication_messenger_connections
where status='active' and (last_checked_at is null or last_checked_at<=now()-interval '1 hour')
order by last_checked_at nulls first,id limit 6;
rollback;
