-- Quotes, Part 2: three `on delete set null` foreign keys that could never actually fire.
--
-- Found by the pgTAP assertions written for the line photo. A composite foreign key that says
-- `on delete set null` nulls **every column in the key**, not just the one pointing at the deleted row. All
-- three of these pair the reference with `organization_id`, which is `not null`, so the cascade tried to
-- write a null organization and the delete failed instead:
--
--   ERROR 23502: null value in column "organization_id" of relation "request_pricing_lines"
--   CONTEXT: UPDATE ... SET "organization_id" = NULL, "image_attachment_id" = NULL
--
-- In plain terms: a contractor deleting a photo from a request's Attachments card, while a pricing line
-- still pointed at it, got a database error rather than a line that quietly forgot its photo. Postgres 15
-- added the column list this needs, and this project runs 17, so the pairing stays and only the reference
-- is cleared.
--
-- The same shape exists on four older tables outside this campaign (client and property contact methods,
-- opportunities' current outcome event, and tasks' completing outcome event). Those are logged in
-- `Memory/deferred/INDEX.md`; nothing here changes them.

alter table public.request_pricing_lines
  drop constraint request_pricing_lines_image_organization_fk;

alter table public.request_pricing_lines
  add constraint request_pricing_lines_image_organization_fk
  foreign key (organization_id, image_attachment_id)
  references public.attachments(organization_id, id)
  on delete set null (image_attachment_id);

-- Catalog items are archived rather than deleted, so this one has never fired in practice. It is the same
-- mistake and it is fixed the same way, rather than left as a trap for the first real delete.
alter table public.request_pricing_lines
  drop constraint request_pricing_lines_catalog_organization_fk;

alter table public.request_pricing_lines
  add constraint request_pricing_lines_catalog_organization_fk
  foreign key (organization_id, catalog_item_id)
  references public.catalog_items(organization_id, id)
  on delete set null (catalog_item_id);

-- A quote pointing at the draft version it owns. Part 2 never deletes a version, but Part 4 will.
alter table public.quotes
  drop constraint quotes_draft_version_organization_fk;

alter table public.quotes
  add constraint quotes_draft_version_organization_fk
  foreign key (organization_id, draft_version_id)
  references public.quote_versions(organization_id, id)
  on delete set null (draft_version_id);
