-- Generic fixed-window rate limiter shared by any route that needs to cap attempts per caller
-- (IP address for public endpoints, owner session email for authenticated ones). One row per
-- (bucket_key, window) is upserted and incremented atomically through the unique primary key
-- below, so concurrent requests from the same caller cannot race past the configured limit.
create table public.platform_rate_limit_buckets (
  bucket_key text not null check (char_length(trim(bucket_key)) between 1 and 200),
  window_start timestamptz not null,
  attempt_count integer not null default 0 check (attempt_count > 0),
  primary key (bucket_key, window_start)
);

alter table public.platform_rate_limit_buckets enable row level security;

revoke all on public.platform_rate_limit_buckets from anon, authenticated;
grant select, insert, update, delete on public.platform_rate_limit_buckets to service_role;

create or replace function public.check_rate_limit(
  target_bucket_key text,
  target_window_seconds integer,
  target_max_attempts integer
)
returns table(allowed boolean, retry_after_seconds integer)
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  bucket_window timestamptz;
  current_count integer;
begin
  if target_window_seconds <= 0 or target_max_attempts <= 0 then
    raise exception 'target_window_seconds and target_max_attempts must be positive.'
      using errcode = 'check_violation';
  end if;

  bucket_window := to_timestamp(
    floor(extract(epoch from now()) / target_window_seconds) * target_window_seconds
  );

  -- Opportunistic cleanup, scoped to this bucket_key only (cheap: hits the primary key index,
  -- never a full table scan) so the table doesn't grow unbounded across many distinct callers.
  delete from public.platform_rate_limit_buckets
  where platform_rate_limit_buckets.bucket_key = target_bucket_key
    and platform_rate_limit_buckets.window_start < bucket_window;

  insert into public.platform_rate_limit_buckets (bucket_key, window_start, attempt_count)
  values (target_bucket_key, bucket_window, 1)
  on conflict (bucket_key, window_start)
  do update set attempt_count = platform_rate_limit_buckets.attempt_count + 1
  returning platform_rate_limit_buckets.attempt_count into current_count;

  return query select
    current_count <= target_max_attempts,
    case
      when current_count <= target_max_attempts then 0
      else greatest(
        1,
        ceil(extract(epoch from (bucket_window + make_interval(secs => target_window_seconds) - now())))::integer
      )
    end;
end;
$$;

revoke all on function public.check_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.check_rate_limit(text, integer, integer) to service_role;
