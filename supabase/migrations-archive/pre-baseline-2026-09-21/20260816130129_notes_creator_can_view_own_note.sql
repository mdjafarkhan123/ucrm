-- Bug found while verifying the Part 3 collaboration components: `notes` is created via two sequential
-- inserts (notes, then note_links). The API route does `.insert(...).select().single()` on notes first,
-- which is INSERT ... RETURNING under the hood -- Postgres requires the SELECT policy to also permit
-- reading back the just-inserted row. The notes SELECT policy only allowed viewing a note through an
-- existing note_links row, so the very first insert always failed RLS: no link exists yet at that point.
-- Never caught before because Part 3 was only smoke-tested unauthenticated. Letting the creator see their
-- own note unconditionally (in addition to the existing link-based visibility) fixes the immediate
-- read-back and is also correct standalone behavior.

drop policy "permitted members can view notes" on public.notes;

create policy "permitted members can view notes"
on public.notes for select to authenticated
using (
  created_by = (select auth.uid())
  or exists (
    select 1 from public.note_links link
    where link.note_id = notes.id
      and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
  )
);
