-- Deleting a note sets note_id to null on its attachments (ON DELETE SET NULL), and nothing indexed
-- attachments.note_id, so every note delete scanned the whole attachments table across all tenants.
-- Most attachments have no note, so the index covers only the rows that do.
--
-- The advisor's other collaboration-table flags stay unindexed on purpose:
-- - note_links (organization_id, note_id) and tag_assignments (organization_id, tag_id) are already
--   served by note_links_unique and tag_assignments_unique, which lead with note_id / tag_id.
-- - created_by, edited_by, uploaded_by, completed_by and actor_user_id point at auth.users and are
--   only walked when an account is deleted, which is rare.
-- - tasks.completed_by_outcome_event_id is read only after filtering by opportunity_id, which
--   tasks_opportunity_completed_idx already covers.
create index if not exists attachments_note_id_idx
	on public.attachments (note_id)
	where note_id is not null;
