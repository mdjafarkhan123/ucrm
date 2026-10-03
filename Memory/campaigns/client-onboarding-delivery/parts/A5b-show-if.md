# A5b — Show-if rule

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint `docs/client-onboarding-setup-content-blueprint.md` "Conditional" rows
**Code:** `main`
**Done when:** A question shows only after its earlier answer matches; a hidden required question never blocks Done

## Steps

- [x] Migration: `setup_items.show_if`, catalogue output, save + publish checks, onboarding list counts only shown questions — applied to dev (`20261008100000`, fix `20261008101000`); proved in an undone test
- [ ] Catalogue code: rules on facts, package rules resolved per client, shown-questions pass, progress uses it
- [ ] Client wizard hides and reveals questions live
- [ ] Editor: "Show this question" control per question
- [ ] Tests, svelte-check, browser check, commit

## Next

Step 2, catalogue code in `src/lib/setup/catalogue.ts`: `showIf` on `SetupFact`, package conditions resolved in
`catalogueForServices`, a shown-questions pass, and `sectionStatus`/`missingRequiredFacts`/`setupSummary` plus
`onboardingCatalogue` (`rules`) using it.

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
- Jafar has his own draft (version 2) open on dev; tests must not leave changes in it.
