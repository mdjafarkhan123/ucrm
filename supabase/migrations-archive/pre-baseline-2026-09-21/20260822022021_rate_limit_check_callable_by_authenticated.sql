-- check_rate_limit is the only sanctioned way to touch platform_rate_limit_buckets (RLS enabled, zero
-- policies, by design). It shipped without security definer and without a grant for `authenticated`, so
-- any caller using a normal per-request session client -- rather than a privileged client like every
-- other rate-limited route in the app uses -- was rejected outright. That broke every Contractor Settings
-- write (branding save, logo upload, business profile save, business hours save), which all rate-limit
-- through this function using the caller's own session.

alter function public.check_rate_limit(text, integer, integer) security definer;

grant execute on function public.check_rate_limit(text, integer, integer) to authenticated;
