-- A sending address cannot be placed on a domain whose removal has already started.
--
-- validate_communication_email_sender only refused a `removed` domain. While a domain sat in
-- `removal_pending`, a not-yet-enabled sender could still be added (or moved) onto it, and finalizing the
-- removal never touches senders, so that sender was left on a removed domain and could never send.
--
-- Only placing a sender on the domain is refused: a new row, or an update that changes its domain. Any other
-- update to a sender already there (disabling it, marking it removed) must keep working, because that is how
-- a removal cleans up.

create or replace function private.validate_communication_email_sender()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  sender_domain public.communication_email_domains;
  membership_status text;
  is_new_placement boolean;
begin
  if tg_op = 'INSERT' then
    is_new_placement := true;
  else
    is_new_placement := new.domain_id is distinct from old.domain_id;
  end if;

  select * into sender_domain
  from public.communication_email_domains
  where organization_id = new.organization_id and id = new.domain_id;

  if not found
     or sender_domain.purpose <> 'sending'
     or sender_domain.lifecycle_state = 'removed'
     or (is_new_placement and sender_domain.lifecycle_state = 'removal_pending') then
    raise exception 'A sender requires a live sending domain in the same organization.'
      using errcode = 'foreign_key_violation';
  end if;

  if split_part(new.email_address, '@', 2) <> sender_domain.domain_name then
    raise exception 'The sender address must use its sending domain.' using errcode = 'check_violation';
  end if;

  if new.lifecycle_state = 'enabled' and (
    sender_domain.lifecycle_state <> 'verified'
    or not sender_domain.provider_verified
    or not sender_domain.provider_authenticated
    or sender_domain.ownership_status <> 'passing'
    or sender_domain.dkim_status <> 'passing'
  ) then
    raise exception 'A live sender requires a verified healthy sending domain.'
      using errcode = 'check_violation';
  end if;

  if new.assigned_user_id is not null then
    select status into membership_status
    from public.organization_members
    where organization_id = new.organization_id and user_id = new.assigned_user_id;

    if membership_status is distinct from 'active' and new.lifecycle_state = 'enabled' then
      raise exception 'An enabled assigned sender requires an active organization member.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;
