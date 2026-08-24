-- Team & access, part 3A, layer 6 follow-up: the background sweeps must not read settled invitations.
--
-- expire_team_invitations() and sweep_team_invitation_reservations() are cross-tenant jobs -- they carry no
-- organization_id, so organization_member_invitations_organization_state_idx cannot serve them and both
-- branches planned as a Seq Scan over the whole table. Every accepted, expired, cancelled and abandoned row
-- ever created stays in that table, so the scan cost grows forever while the work stays tiny.
--
-- One partial index fixes all three predicates. Its own WHERE clause holds only invitations still in play,
-- so the index stays small no matter how many settled rows accumulate: a row leaves it for good the moment
-- it settles. state leads (every branch tests it for equality), expires_at follows for the two expiry range
-- scans; the reserving branch's created_at filter runs on the handful of rows state = 'reserving' returns.
create index organization_member_invitations_live_state_expiry_idx
  on public.organization_member_invitations (state, expires_at)
  where state in ('reserving', 'invited', 'accepting');
