# Part 4 — Fixing money mistakes

**State:** In progress. Slices 4a–4c done. 4d browser-check on Raad LTD (owner login) done except one failure.

**Verified in the browser:** void #30 (email sent, credit updated); split a payment across two invoices; Fix
payment; Mark as never received (money came off both invoices); Correct invoice → edit → Replace invoice
(#28 → #33, $600 carried across, $100 left to pay, original shows "Replaced").

**Fixed this session, not yet committed together with a check:** a replaced or voided invoice showed its full
total as "Invoice balance" (detail page Balance card, and the Invoices list). Now $0.00. Files:
`src/routes/(app)/invoices/[id=uuid]/+page.svelte`, `src/routes/api/invoices/+server.ts`. Voided detail page
verified ($0.00); list not re-checked after the change.

**FAILED — Rebill on voided #30:** "Replace and mark as sent" says "A voided invoice cannot be changed."
Cause found: `activate_invoice_replacement` marks the voided original as replaced, but the row guard
`private.invoices_guard_identity` compares whole rows and the auto-calculated column `is_effective_receivable`
counts as a change. Proven in a rolled-back test: leaving that column out of the comparison (add
`- 'is_effective_receivable'` on both sides, where `replaced_at` etc. are already left out) lets the update
through; nothing else about voided invoices loosens. Live guard is unchanged. The auto-mode safety check
blocked writing the migration because it loosens a guard — **question for Jafar:** approve that one-line
change as a new migration (next timestamp after 20260928160000)?

**Test leftovers on Raad LTD:** draft #34 (rebill of #30, stays draft until the fix), #33 live.

**Also open:** first "Correct invoice" click once reloaded the same invoice without moving on; the retry worked.
Not reproduced — recheck. Office/finance roles have no `invoices.*` permissions (baseline matrix) — ask Jafar
if they should. After Rebill passes: delete `issued-invoices-cannot-be-corrected-from-the-browser` and its
deferred INDEX row, mark Part 4 Done in ROADMAP, move to Part 5.
