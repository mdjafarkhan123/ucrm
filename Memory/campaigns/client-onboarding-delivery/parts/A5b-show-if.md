# A5b — Show-if rule

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint `docs/client-onboarding-setup-content-blueprint.md` "Conditional" rows
**Code:** `main`
**Done when:** A question shows only after its earlier answer matches; a hidden required question never blocks Done

## Steps

- [x] Migration: `setup_items.show_if`, catalogue output, save + publish checks, onboarding list counts only shown questions — applied to dev (`20261008100000`, fix `20261008101000`); proved in an undone test
- [x] Catalogue code: `shownFacts` in `src/lib/setup/catalogue.ts`; package rules settled in `catalogueForServices`; progress, Done, reminders, sections API (`earlier_answers`) and `onboarding-list.ts` (`rules`) use it
- [x] Client wizard hides and reveals questions live (not yet browser-checked: no rule is published)
- [ ] Editor: "Show this question" control per question
- [ ] Tests, svelte-check, browser check, commit

## Next

Step 4, the editor. `src/lib/jafar/setup-editor.ts`: add `show_if` to `SetupEditorItem`, `DraftItem`, and
`itemsPayload` (a same-stage source with no key yet goes as `{ item: <1-based index>, values }`).
`src/lib/server/validation/setup-editor.schema.ts`: accept `show_if` (max 5; `{fact_key|item, values}` or
`{service_key}`); refuse a built-in source whose `BUILT_IN_FACTS` kind is not choice/choice_other/country,
or values outside its options (country: ISO code). `src/lib/components/jafar/setup/SetupQuestionList.svelte`:
"Show this question: Always / Only when…" listing earlier pick-one, yes/no and built-in choice questions
(other stages from `editor.draft.stages`), tick-box values, and "package includes [service]". A new
pick-one's choices must be saved before use. Then unit tests for `shownFacts` and `catalogueForServices`,
svelte-autofixer, and a browser check.

## Outside actions

- Migrations `20261008100000` and fix `20261008101000` applied to dev, versions renamed to match the files — done

## Notes

Design (SurveyJS `visibleIf` / Jotform show-hide pattern), decided 2026-10-03 from the blueprint's needs:
- `show_if` is null or 1–5 conditions, all must hold: `{fact_key, values[]}` (earlier answer is one of) or
  `{service_key}` (client's package includes). Chains allowed: a hidden source hides its dependants.
- A source is an earlier question (earlier stage, or earlier in the same stage) that is pick-one, yes/no, or a
  built-in choice/country. "Need help" / "not yet" on a source counts as no match.
- Hidden answers stay stored and uncounted; B13's snapshot must leave them out.
- In the save, a new source in the same list is named by `item` (1-based index); a new pick-one's choices
  must be saved before they can be used in a rule.
- Stage reorder that puts a source after its dependant is caught at publish with a named message.
- Jafar has his own draft (version 2) open on dev. Test in it only with changes you undo; never Discard it.
