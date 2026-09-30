-- Package builder P12: Pipeline, the shared inbox, and review requests become sellable.
--
-- Each was checked on 2026-09-30 with the capability switched off for a test organization and then on
-- again: menu items, screens, APIs, and background work (the review senders, migration 20261001160000)
-- all follow the package. Only a verified build changes `sellable`, so the builder can now publish them.

update public.package_capabilities
set sellable = true
where capability_key in ('sales.pipeline', 'communications.inbox', 'growth.reputation')
	and kind = 'extra';
