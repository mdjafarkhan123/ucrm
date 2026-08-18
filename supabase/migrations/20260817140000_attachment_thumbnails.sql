-- Attachment thumbnails
--
-- Photos are shown as a grid of previews on the record they belong to, not as file-type icons. Drawing that
-- grid from the originals would make a browser download every full-size phone photo just to paint a handful
-- of small squares, which is punishing on a phone in the field. So the browser shrinks each picked image
-- before upload and stores that small copy as a second object; the grid and the lightbox filmstrip read it,
-- and only the lightbox's main image reads the original.
--
-- Nullable on purpose. Non-image attachments never have one, images uploaded before this migration do not
-- have one, and an image the browser cannot decode (HEIC, most notably) does not either. Every reader falls
-- back to the original object when this is null.

alter table public.attachments
  add column thumbnail_object_key text;

-- Same uniqueness guarantee the original object key carries: one storage object is claimed by one row.
create unique index attachments_thumbnail_object_key_key
  on public.attachments(thumbnail_object_key)
  where thumbnail_object_key is not null;

comment on column public.attachments.thumbnail_object_key is
  'R2 key of the downscaled preview generated at upload. Null for non-images and for rows created before thumbnails existed; readers fall back to object_key.';
