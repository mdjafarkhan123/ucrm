-- The 3B cleanup worker deletes invitation-owned Auth users. Postgres checks every FK into auth.users on
-- that delete, so invited_by and cancelled_by need covering indexes once the invitation table can grow.

create index organization_member_invitations_invited_by_idx
  on public.organization_member_invitations (invited_by)
  where invited_by is not null;

create index organization_member_invitations_cancelled_by_idx
  on public.organization_member_invitations (cancelled_by)
  where cancelled_by is not null;
