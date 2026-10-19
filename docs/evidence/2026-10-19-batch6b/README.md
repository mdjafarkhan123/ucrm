# Batch 6b — approved controls, 2026-10-19

Built from approved Pencil board `Fma1f` and the recorded Batch 6b behaviour in C5. The shared components apply at all callers.

- Filter chips: 36px shape, name/value divider, green filtering edge and clear button; multi-select chips follow the same treatment. Status options carry semantic dots.
- Money: currency block from the business shell, explicit record currency for payment/customer forms, and USD for platform package prices. Amounts display thousands commas on blur; editing remains free text and APIs still receive integer cents. Currency remains available to assistive technology. The redundant currency label was removed from the affected callers.
- Quantity: buttons change by one, decrement stops at one, decimal typing and three-decimal rounding remain. Line-item columns reflow in narrow containers so buttons and amounts fit.
- Tags: persisted palette hex values map to theme tokens. New tags default to the next unused colour and permit choosing another. Colour changes use the existing tag-creation permission (`customers.edit`), with an API check and matching RLS; pick-only members get no colour menu. Colour mutations invalidate tag assignments and client queries. The old record TagPicker now reuses TagSelect, including its loading/error handling. Unknown/empty legacy colours render neutral. Photo labels and setup choices reuse the appearance but remain separate catalogs; no new file-label storage behaviour was introduced.

## Checks

- Focused Vitest: MoneyInput, QuantityInput, TagSelect and tag-colors — **6 tests passed**, 6.28 seconds. Covers decimal input/rounding, minimum quantity, currency/commas/invalid amount, next unused palette colour, palette validation, pick-only UI, and duplicate prevention/loading during creation.
- Focused visual fixture — **1 test passed**. `controls-1440-*` and `controls-390-*` capture the changed controls at those CSS viewport widths in both themes (the test runner scales the saved images). Includes disabled, error, long-name and filled states. This is a shared-control spot check, not a phone-page redesign.
- Scoped Svelte check: **0 errors, 0 warnings**. Final Svelte preprocessing/compilation passed for all changed components. Autofixer run against preprocessed SCSS; no component issues. Existing money/quantity draft-sync effects retained deliberately to protect in-progress typing from external updates.
- Focused ESLint passed for the shared controls and tag API. A wider affected-caller run found three existing unrelated warnings-as-errors: ProductsAndServicesBlock's mutable Set, QuoteDepositCard's raw icon HTML, and unused notesCount on the client page. Confirmed present on main; left for their owning work.
- `git diff --check` passed. No full build, whole-project lint/test suite, release audit or capacity check was run, following Jafar's request.

## Live app proof

Checked the running branch app at localhost:5174 using the existing Raad LTD Owner session:

1. Clients: select Customer and clear it; correct filtered results and clear state (`filters-light.png`).
2. New client: search an absent name, pick Indigo and create **Batch 6b colour proof**. The create button disabled while saving. Database read confirmed `#556acb`.
3. Open its colour menu and choose Teal. Buttons disabled while saving, the chosen chip changed, and a database read confirmed `#118197`. Light menu and dark chip screenshots are included. The test tag remains in the catalog for inspection; no client was saved.
4. New job: add an unsaved line, use the quantity stepper, enter 2.5 and 1250; blur displays **1,250.00** and total **$3,125.00**. Narrow line-item crowding found and fixed. Final `line-inputs-light.png` / `line-inputs-dark.png` show the corrected layout. No job was saved or notification sent.
5. Database permission transaction (rolled back): Owner update affected **1** tag; Field member update affected **0**. Outcome read confirmed the installed update policy has both membership and `customers.edit` in USING and WITH CHECK.

Migration `20261019132605_tag_colour_editing.sql` was applied to the remote development database and recorded in the same transaction. **Do not reapply it.** Supabase MCP verified the policy and saved tag colours. No infrastructure changes.

## Integrated main check

The same six focused tests passed on integrated main (4 files, 24.14 seconds including cold dependency preparation). After merging into main, opened the real tunnel app, selected the saved proof tag on New client and opened its colour menu. Teal remained selected and the persisted colour was reflected in the chip (`tags-main.png`). Left the client unsaved and returned the app to Home.

## Engineering references

Preserved the existing free-text draft/blur-commit input pattern; used native Intl formatting, existing Bits UI popovers and shared Button loading behavior. Kept colour in `tags.color` and reused the existing Supabase permission helpers. Filtered updates follow [Supabase's update API](https://supabase.com/docs/reference/javascript/update). The approved product behaviour is the campaign's source of truth; no new competitor decision was needed.
