-- Part 4 (inbound replies and attachments): reply-alias correlation foundation.
--
-- A reply alias is an opaque address on a verified 'receiving' communication_email_domains row,
-- scoped to (sender, client, contact method). Outbound sends set it as Reply-To so a customer's
-- reply can be correlated back to the right tenant and conversation without any organization,
-- contact, or work-object identifier appearing in the address itself
-- (docs/contractor-email-contract.md § Conversations and replies).

create table public.communication_reply_aliases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  receiving_domain_id uuid not null,
  sender_id uuid not null,
  client_id uuid not null,
  client_contact_method_id uuid not null,
  alias_local_part text not null,
  last_activity_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 days'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_reply_aliases_domain_fk
    foreign key (organization_id, receiving_domain_id)
    references public.communication_email_domains (organization_id, id) on delete restrict,
  constraint communication_reply_aliases_sender_fk
    foreign key (organization_id, sender_id)
    references public.communication_email_senders (organization_id, id) on delete restrict,
  constraint communication_reply_aliases_client_fk
    foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete cascade,
  constraint communication_reply_aliases_contact_method_fk
    foreign key (organization_id, client_contact_method_id)
    references public.client_contact_methods (organization_id, id) on delete restrict,
  -- The routable address must be unique per receiving domain.
  constraint communication_reply_aliases_unique_local_part unique (receiving_domain_id, alias_local_part),
  -- One enduring alias per (mailbox, customer, customer address) conversation; reused and refreshed
  -- rather than minted again on every send.
  constraint communication_reply_aliases_unique_conversation
    unique (organization_id, sender_id, client_id, client_contact_method_id)
);

create index communication_reply_aliases_org_client_idx
  on public.communication_reply_aliases (organization_id, client_id);
create index communication_reply_aliases_sender_idx
  on public.communication_reply_aliases (organization_id, sender_id);

-- A same-table CHECK cannot see the referenced domain's purpose/lifecycle_state, so a trigger enforces
-- that a reply alias only ever points at a verified receiving domain for its own organization.
create or replace function private.validate_communication_reply_alias_domain()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  domain public.communication_email_domains;
begin
  select * into domain from public.communication_email_domains
  where id = new.receiving_domain_id and organization_id = new.organization_id;
  if domain.id is null or domain.purpose <> 'receiving' or domain.lifecycle_state <> 'verified' then
    raise exception 'The reply alias domain must be a verified receiving domain for this organization.'
      using errcode = 'foreign_key_violation';
  end if;
  return new;
end;
$$;

create trigger communication_reply_aliases_validate_domain
  before insert or update of receiving_domain_id, organization_id on public.communication_reply_aliases
  for each row execute function private.validate_communication_reply_alias_domain();

alter table public.communication_reply_aliases enable row level security;
revoke all on public.communication_reply_aliases from anon, authenticated;
grant select, insert, update on public.communication_reply_aliases to service_role;

-- Outbound sends record which conversation alias (if any) they used, so the worker can set Reply-To
-- and so a later inbound reply's In-Reply-To header can be matched straight back to this row.
alter table public.communication_delivery_intents
  add column reply_alias_id uuid references public.communication_reply_aliases (id) on delete set null;

create index communication_delivery_intents_reply_alias_idx
  on public.communication_delivery_intents (reply_alias_id) where reply_alias_id is not null;

-- Reuses an existing alias for this (sender, client, contact method) conversation, refreshing its
-- retention window, or mints a new opaque one on the organization's verified receiving domain.
-- Returns null (not an error) when the organization has no verified receiving domain yet -- outbound
-- send simply proceeds without a Reply-To until Jafar provisions one, exactly like every other
-- eligibility gap in this send path.
create or replace function public.ensure_communication_reply_alias(
  target_organization_id uuid,
  target_sender_id uuid,
  target_client_id uuid,
  target_contact_method_id uuid
) returns public.communication_reply_aliases
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  alias public.communication_reply_aliases;
  receiving_domain public.communication_email_domains;
begin
  update public.communication_reply_aliases
    set last_activity_at = now(), expires_at = now() + interval '90 days', updated_at = now()
    where organization_id = target_organization_id and sender_id = target_sender_id
      and client_id = target_client_id and client_contact_method_id = target_contact_method_id
    returning * into alias;
  if alias.id is not null then
    return alias;
  end if;

  select * into receiving_domain from public.communication_email_domains
  where organization_id = target_organization_id and purpose = 'receiving' and lifecycle_state = 'verified'
  order by created_at
  limit 1;
  if receiving_domain.id is null then
    return null;
  end if;

  loop
    begin
      insert into public.communication_reply_aliases (
        organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id, alias_local_part
      ) values (
        target_organization_id, receiving_domain.id, target_sender_id, target_client_id, target_contact_method_id,
        encode(gen_random_bytes(16), 'hex')
      ) returning * into alias;
      exit;
    exception when unique_violation then
      -- Either a local-part collision (astronomically unlikely) or a concurrent caller already
      -- created this exact conversation's alias; re-read rather than retrying blind.
      select * into alias from public.communication_reply_aliases
        where organization_id = target_organization_id and sender_id = target_sender_id
          and client_id = target_client_id and client_contact_method_id = target_contact_method_id;
      if alias.id is not null then exit; end if;
    end;
  end loop;

  return alias;
end;
$$;

revoke all on function public.ensure_communication_reply_alias(uuid, uuid, uuid, uuid) from public;
grant execute on function public.ensure_communication_reply_alias(uuid, uuid, uuid, uuid) to service_role;
