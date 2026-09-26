-- Companion to 20260926220000. /api/communications/email-sender answers "which address will this email say it
-- is from", and it did so by re-implementing the enqueue functions' sender rule in PostgREST filters. Now that
-- the rule includes a business-default fallback and an active-member check, that copy would tell a staff member
-- "no sender" while the send itself succeeds. This wrapper lets the endpoint ask the one real resolver instead,
-- so the preview and the send can no longer disagree.

create or replace function public.manual_email_sender_preview(
  target_organization_id uuid,
  target_actor_user_id uuid
)
returns table (display_name text, email_address text)
language sql
security definer
set search_path = pg_catalog, public, private
as $$
  select sender.display_name, sender.email_address
  from private.resolve_manual_email_sender(target_organization_id, target_actor_user_id) as sender
  where sender.id is not null;
$$;

-- Read through the owner client only: sender readiness depends on domain state that RLS hides from ordinary
-- members, and the endpoint already scopes the call to the caller's own organization and user.
revoke all on function public.manual_email_sender_preview(uuid, uuid) from public, anon, authenticated;
grant execute on function public.manual_email_sender_preview(uuid, uuid) to service_role;
