-- Messenger Part 4 (docs/messenger-implementation-plan.md § Server shape, Connect): what connecting a Facebook Page
-- needs beyond the Part 3 tables. GoHighLevel's flow: log in to Facebook in a small window, tick the Pages, connect.
--
-- 1. Login sessions. Facebook's window hands back a user key that can list the person's Pages. It is kept only
--    long enough to pick Pages (30 minutes), only as AES-256-GCM ciphertext, and is deleted once Pages are
--    connected. Page keys are fetched again at connect time, so no Page key waits here.
-- 2. Which Facebook account connected a Page, for the "Logged in to Facebook as …" line on the Settings card.
--
-- No browser reads these tables: row level security is on with no policies. The server checks who is asking.

-- 1. Login sessions -------------------------------------------------------------------------------------------

create table public.communication_messenger_login_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  facebook_user_id text not null,
  facebook_user_name text not null,
  encryption_key_id text not null,
  user_token_nonce bytea not null,
  user_token_ciphertext bytea not null,
  user_token_tag bytea not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 minutes',
  constraint communication_messenger_login_sessions_facebook_user_id_check
    check (facebook_user_id ~ '^[0-9]{1,32}$'),
  constraint communication_messenger_login_sessions_facebook_user_name_check
    check (char_length(btrim(facebook_user_name)) between 1 and 200),
  constraint communication_messenger_login_sessions_key_check check (
    encryption_key_id ~ '^[A-Za-z0-9._-]{1,64}$'
      and octet_length(user_token_nonce) = 12
      and octet_length(user_token_ciphertext) > 0
      and octet_length(user_token_tag) = 16
  ),
  constraint communication_messenger_login_sessions_expiry_check check (expires_at > created_at)
);

comment on table public.communication_messenger_login_sessions is
  'Short-lived Facebook login for picking Pages. AES-256-GCM ciphertext only; a plaintext user token must never enter Postgres.';

create index communication_messenger_login_sessions_member_idx
  on public.communication_messenger_login_sessions (organization_id, user_id, created_at desc);

create index communication_messenger_login_sessions_user_idx
  on public.communication_messenger_login_sessions (user_id);

alter table public.communication_messenger_login_sessions enable row level security;
revoke all on table public.communication_messenger_login_sessions from public, anon, authenticated;
grant select, insert, update, delete on table public.communication_messenger_login_sessions to service_role;

-- 2. Which Facebook account connected a Page ------------------------------------------------------------------

alter table public.communication_messenger_connections
  add column facebook_user_name text,
  add constraint communication_messenger_connections_facebook_user_name_check
    check (facebook_user_name is null or char_length(btrim(facebook_user_name)) between 1 and 200);
