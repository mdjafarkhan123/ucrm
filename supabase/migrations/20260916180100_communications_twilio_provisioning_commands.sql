-- Communications A2 / Stage 2B: atomic credential transitions for the Twilio provisioning saga.
-- AES-256-GCM encryption happens in Node (Postgres never sees plaintext), so these functions receive only
-- ciphertext + envelope and own the multi-row invariant transitions that must be atomic: the "one current
-- credential per purpose" rule (enforced by communication_twilio_credentials_one_lifecycle_key) can never be
-- momentarily broken across separate client calls. service_role only.

-- Provisioning step 1: create the account record and its first Auth Token together. The subaccount exists at
-- Twilio and its Auth Token is returned exactly once; account row and encrypted token must commit atomically
-- so a crash can never leave a subaccount whose only credential is lost.
create or replace function public.communication_twilio_store_provisioned_subaccount(
  p_organization_id uuid,
  p_subaccount_sid text,
  p_auth_token_credential_id uuid,
  p_encryption_key_id text,
  p_nonce bytea,
  p_ciphertext bytea,
  p_authentication_tag bytea
) returns public.communication_twilio_accounts
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  acct public.communication_twilio_accounts;
begin
  insert into public.communication_twilio_accounts (organization_id, subaccount_sid)
  values (p_organization_id, p_subaccount_sid)
  returning * into acct;

  insert into public.communication_twilio_credentials (
    id, organization_id, twilio_account_id, credential_purpose, lifecycle_state,
    encryption_key_id, nonce, ciphertext, authentication_tag
  ) values (
    p_auth_token_credential_id, p_organization_id, acct.id, 'auth_token', 'current',
    p_encryption_key_id, p_nonce, p_ciphertext, p_authentication_tag
  );

  return acct;
end;
$$;

-- Auth Token rotation cutover. The new token is already staged (durable) and verified; the old primary has
-- just been promoted away at Twilio. This flips the pointers atomically: the old current becomes prior with an
-- explicit local retirement time (webhook-retry compatibility only -- Twilio no longer accepts it), and the
-- staged token becomes current. Requires exactly one staged and one current, or it refuses.
create or replace function public.communication_twilio_complete_auth_token_rotation(
  p_account_id uuid,
  p_retire_after timestamptz
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  staged_count integer;
  current_count integer;
begin
  select count(*) into staged_count
  from public.communication_twilio_credentials
  where twilio_account_id = p_account_id
    and credential_purpose = 'auth_token'
    and lifecycle_state = 'staged';

  select count(*) into current_count
  from public.communication_twilio_credentials
  where twilio_account_id = p_account_id
    and credential_purpose = 'auth_token'
    and lifecycle_state = 'current';

  if staged_count <> 1 or current_count <> 1 then
    raise exception 'auth token rotation requires exactly one staged and one current credential'
      using errcode = 'P0001';
  end if;

  delete from public.communication_twilio_credentials
  where twilio_account_id = p_account_id
    and credential_purpose = 'auth_token'
    and lifecycle_state = 'prior';

  update public.communication_twilio_credentials
  set lifecycle_state = 'prior', retire_after = p_retire_after, updated_at = now()
  where twilio_account_id = p_account_id
    and credential_purpose = 'auth_token'
    and lifecycle_state = 'current';

  update public.communication_twilio_credentials
  set lifecycle_state = 'current', retire_after = null, updated_at = now()
  where twilio_account_id = p_account_id
    and credential_purpose = 'auth_token'
    and lifecycle_state = 'staged';
end;
$$;

-- Restricted API key rotation cutover. A Restricted key authenticates only outbound API calls (never webhook
-- verification), so there is no retry window: the old key is dropped and the staged key becomes current. The
-- old key's deletion at Twilio happens in Node after this commits.
create or replace function public.communication_twilio_complete_restricted_key_rotation(
  p_account_id uuid
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  staged_count integer;
  current_count integer;
begin
  select count(*) into staged_count
  from public.communication_twilio_credentials
  where twilio_account_id = p_account_id
    and credential_purpose = 'restricted_api_key'
    and lifecycle_state = 'staged';

  select count(*) into current_count
  from public.communication_twilio_credentials
  where twilio_account_id = p_account_id
    and credential_purpose = 'restricted_api_key'
    and lifecycle_state = 'current';

  if staged_count <> 1 or current_count <> 1 then
    raise exception 'restricted key rotation requires exactly one staged and one current credential'
      using errcode = 'P0001';
  end if;

  delete from public.communication_twilio_credentials
  where twilio_account_id = p_account_id
    and credential_purpose = 'restricted_api_key'
    and lifecycle_state = 'current';

  update public.communication_twilio_credentials
  set lifecycle_state = 'current', updated_at = now()
  where twilio_account_id = p_account_id
    and credential_purpose = 'restricted_api_key'
    and lifecycle_state = 'staged';
end;
$$;

revoke all on function public.communication_twilio_store_provisioned_subaccount(
  uuid, text, uuid, text, bytea, bytea, bytea
) from public, anon, authenticated;
grant execute on function public.communication_twilio_store_provisioned_subaccount(
  uuid, text, uuid, text, bytea, bytea, bytea
) to service_role;

revoke all on function public.communication_twilio_complete_auth_token_rotation(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.communication_twilio_complete_auth_token_rotation(uuid, timestamptz)
  to service_role;

revoke all on function public.communication_twilio_complete_restricted_key_rotation(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_twilio_complete_restricted_key_rotation(uuid)
  to service_role;
