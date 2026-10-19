-- The approved Schedule concept allows the team to mark an event complete.
-- Nullable with no default: existing events stay open, and existing app versions keep working.
alter table public.schedule_events add column completed_at timestamptz;
comment on column public.schedule_events.completed_at is
  'When this Schedule-owned event was marked complete. Null means it is still open.';
comment on table public.schedule_events is
  'A Schedule-owned lightweight calendar block (team meeting, holiday, training). Single-day, timed or anytime, whole-team. No client, assignment or recurrence. Members with schedule access read it; jobs.schedule authority writes and completes it.';
