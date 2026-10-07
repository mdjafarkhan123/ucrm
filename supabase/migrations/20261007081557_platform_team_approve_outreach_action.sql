-- Jafar business B3: approving who to contact (and undoing Do not contact) is its own sensitive action.
alter table public.platform_team_members drop constraint platform_team_members_action_grants_known;
alter table public.platform_team_members add constraint platform_team_members_action_grants_known check (
  action_grants <@ array['payments', 'client_setup', 'packages', 'client_accounts', 'approve_outreach']::text[]
);
