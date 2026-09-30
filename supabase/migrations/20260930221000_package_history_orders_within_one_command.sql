-- Package builder P7: history rows written by one command (a publish that also flags the website reminder)
-- keep the order they were written in, so the catalog history reads correctly.

alter table public.package_catalog_events alter column created_at set default clock_timestamp();
