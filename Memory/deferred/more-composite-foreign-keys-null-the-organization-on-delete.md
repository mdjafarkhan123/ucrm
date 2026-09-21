# Four more composite foreign keys null the organization on delete

- **Priority:** P3
- **Found:** 2026-09-21, by a catalogue query while closing the earlier four-key note.
- **Why postponed:** Not known to bite yet; it only fails when the referenced row is deleted, and these parents
  (tax rate, replaced email domain, SMS registration) may never be hard-deleted.
- **Reactivate when:** Deleting a tax rate, replaced email domain, or SMS registration is built, or fails with `23502`.
- **Constraint:** Same fix as `20260921130000_four_older_composite_fks_clear_only_the_reference.sql`: `on delete set null (<reference column>)`.
- **Keys:** `properties_tax_rate_organization_fk`, `quote_versions_tax_rate_organization_fk`,
  `communication_email_domains_replacement_fk`, `communication_sms_sender_identities_registration_fk`.
