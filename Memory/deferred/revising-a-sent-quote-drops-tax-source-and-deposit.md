# Revising a sent quote does not carry over its tax source or deposit

- **Priority:** P1
- **Found:** 2026-09-21, by the migration-baseline proof (pgTAP `quote_deposit_schema_and_calculation`, tests 28-34).
- **Evidence (read from live):** `clone_quote_version_to_draft`, which `revise_quote` calls, copies `tax_name` and `tax_rate_basis_points`
  but not `tax_source` or `tax_rate_id`, and copies no deposit type or deposit installment. `create_similar_quote` does copy the deposit.
  Rewritten in `339516b` (branding freeze) after the tax-source and deposit columns existed.
- **Likely effect (follows from the code, not reproduced in a browser):** the new draft starts with `tax_source = 'not_configured'`. A quote that
  had tax >0 should then fail the `quote_versions_tax_source_consistency` check; a no-tax quote is refused at send ("Choose a tax rate…").
  The deposit is silently dropped either way.
- **Reactivation trigger:** Jafar decides. Fix = one new migration recreating the function, with a browser check of "Revise" on a taxed, deposit quote.
  Changes a live database function, so it needs Jafar's approval first.
