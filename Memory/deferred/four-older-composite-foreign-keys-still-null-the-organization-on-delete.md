# Four older composite foreign keys still null the organization on delete

- **Priority:** P1


- **Campaign:** found during `quotes` Part 2 pgTAP work on 2026-08-20. The three in the Quotes tables were
  fixed there; these four belong to closed campaigns and were left alone on purpose.
- **What is wrong:** a composite foreign key declared `on delete set null` with no column list nulls **every**
  column in the key, including `organization_id`, which is `not null`. The delete then fails with
  `23502` instead of quietly clearing the reference. Proven live: deleting an attachment a pricing line
  pointed at raised `null value in column "organization_id"`, and the cascade statement was
  `SET "organization_id" = NULL, "image_attachment_id" = NULL`.
- **Still affected:** `client_contact_methods_contact_organization_fk`,
  `property_contact_methods_contact_organization_fk`, `opportunities_current_outcome_event_fk`, and
  `tasks_outcome_event_organization_fk`. Each one breaks a delete somebody will eventually try: removing a
  client or property contact that a contact method points at, or deleting an outcome event.
- **The fix:** Postgres 15 added a column list and this project runs 17 — drop and re-add each constraint
  with `on delete set null (<the reference column>)`, exactly as
  `20260820133000_pricing_set_null_clears_only_the_reference.sql` does.
- **Reactivation trigger:** Jafar asks, or anyone reports a delete failing on contacts, contact methods, or
  outcome events.
- **Prerequisites:** None technical. It is four constraint swaps in one migration; it touches closed
  campaigns' tables, which is why it is Jafar's call rather than a quiet edit.
- **Checkpoint:** `supabase/migrations/20260820133000_pricing_set_null_clears_only_the_reference.sql`.

