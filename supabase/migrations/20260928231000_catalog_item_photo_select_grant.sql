-- Deferred sweep Part 7e follow-up: members read catalog_items through a column-level SELECT grant (so
-- unit_cost_minor stays hidden from anyone who may not see cost). 20260928230000 added image_file_id without
-- adding it to that grant, so every price list read that asks for the photo was refused outright.
grant select (image_file_id) on public.catalog_items to authenticated;
