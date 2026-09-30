-- Package builder P13: website chat and marketing email become sellable.
--
-- Checked on 2026-09-30: their allowances restart on each monthly service start day, also on yearly
-- packages (migration 20261001180000); every limit reads "not included" while its feature is off
-- (20261001181000); at the chat limit a new visitor is refused while open chats continue; widget and
-- marketing limits are enforced in the database; the team screens and APIs follow the feature.

update public.package_capabilities
set sellable = true
where capability_key in ('website_chat', 'marketing')
	and kind = 'extra';
