-- Package builder P14: custom automations become sellable.
--
-- Checked on 2026-10-01: the platform safety values Jafar agreed are set (20261001190000) and checked when an
-- automation is saved and switched on; the active-automations limit holds on activation and on resume, with
-- concurrent switch-ons counted one at a time (20261001191000); every automation message, including the
-- review step (20261001193000), stops when the plan drops Automations, and no new runs start. Team seats
-- count the owner, active members, and pending invitations, and a cancelled or expired invitation frees its
-- seat at once (20260928090000, 20261001192000).

update public.package_capabilities
set sellable = true
where capability_key = 'automations'
	and kind = 'extra';
