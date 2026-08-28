# Four composite foreign keys null the organization on delete

- **Priority:** P1
- **Why postponed:** Four closed-domain constraints use ON DELETE SET NULL without a column list, so deletes try to null the non-null organization_id.
- **Reactivate when:** Contact/contact-method or outcome-event deletion is touched or fails.
- **Constraint:** Re-add each constraint with SET NULL limited to the reference column.
- **Pointer:** supabase/migrations/20260820133000_pricing_set_null_clears_only_the_reference.sql.
