-- Quotes Part 8 / Jobs Part 5: the convert permission now turns something on, so it is seeded.
--
-- `quotes.convert` was named in the Quote contract from the start but deliberately left out of the
-- permission tables while there was nothing to convert to. public.convert_quote_to_job exists as of
-- 20260901002848, so the switch is real and the Team access editor may show it.

insert into public.permissions (key, description)
values ('quotes.convert', 'Turn an approved quote into a job')
on conflict (key) do update set description = excluded.description;

-- The contract's proposed defaults: the roles that build and close quote work convert it. Finance holds
-- money permissions, not commercial commands, and Field only ever sees a quote.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'quotes.convert'),
  ('admin', 'quotes.convert'),
  ('office', 'quotes.convert'),
  ('sales', 'quotes.convert')
on conflict (role, permission_key) do nothing;
