---
name: quote-draft-commands-tax-assertions-are-stale
description: quote_proposal_draft_commands.sql still calls the 4-argument set_quote_draft_tax, so 10 of its 58 assertions fail
metadata:
  type: project
---

`supabase/tests/database/quote_proposal_draft_commands.sql` calls
`public.set_quote_draft_tax(quote_id, revision, name, basis_points)`. The tax-rate library replaced that
signature with
`set_quote_draft_tax(target_quote_id uuid, expected_revision integer, new_source text, new_rate_id uuid,
new_custom_name text, new_custom_rate_basis_points integer, save_as_reusable boolean)`, so every call
dies with `42883 function does not exist`. Ten assertions fail from that one root cause (10 of 58 on
2026-08-31): tests 20, 21, 22, 25, 26, 29, 30, 36, 37 and 50 — the two `lives_ok` tax calls, the
`throws_ok` tax-needs-a-name case, and the seven tax/total figures that depend on a tax ever being set.

Not a product defect. The remaining 48 assertions pass, including the new
`preview_quote_version_totals` price gate. Fix is mechanical: update the three call sites to the new
signature and re-derive the expected tax and total figures.

**Reactivation trigger:** the next Quotes slice that touches draft tax or discount, or any run that needs
this suite green.
