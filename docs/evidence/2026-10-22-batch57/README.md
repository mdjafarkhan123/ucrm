# Batch 57 — Plan details and price

Approved B: Pencil `S4I7i`, 2026-10-22. Built from the saved approval and `design/modals.md`; package terms,
amounts, selection, and application submission rules are unchanged. No new database or provider actions.

## Live proof

Checked in Codex's integrated browser on 2026-10-22 against the isolated app preview on port 5197.
The real public journey used the published **Starter Check** plan: Business → Package → View details →
Choose Starter Check → plan radio selected; switching to yearly → details → Keep this package preserves
selection. Escape dismisses and returns focus to View details. Header/footer stay visible while the body
scrolls. The public `/packages/starter-check?billing=year` page shows one price hero, the shared details,
and switching Monthly updates both Apply links to `billing=month`. No application submitted.

- `integrated-dark-yearly.png`, `integrated-dark-payment.png`: real dialog and its payment section.
- `public-page-yearly.png`: real public package page; its full frame awaits the later page redesign.
- `fixture-light.png`, `fixture-dark-yearly.png`: synthetic display fixtures for services, extra features,
  long labels, numeric and Unlimited allowances, exclusions, offer deadline, regular price, introductory
  offer, yearly saving and large price. Fixtures were served temporarily and removed before commit.
- `fixture-minimal.png`: optional data absent, monthly-only package, no intro offer.

Screenshots use the integrated browser's available desktop viewport (1368×801 for the real dialog;
1270×714 for subsequent views), compared with the approved drawing. No phone viewport proof in this
session; this campaign targets desktop. The inherited third-party verification widget was not changed.

## Focused checks

- Svelte preprocess + compile for all five changed Svelte files: no warnings/errors.
- Svelte MCP autofixer on preprocessed code: no issues in changed shared components; Get started has no
  issues, only existing suggestions concerning the third-party verification widget and step classes.
- Prettier check on the five changed files: passed. `git diff --check`: passed.
- A focused ESLint run found two trusted-icon raw-SVG annotations; these were explicitly annotated using
  the existing project convention. Full type check, build, lint suite and tests were deferred as requested.

## Integration scope

PackageDetails/PackagePrice update every existing call site. PackageOfferPage suppresses the extra price
hero inside its details because its existing page hero already contains the selected price. IconTile now
handles the brand `interactive` tone using existing tokens. No existing call site used that tone.
Pencil board cleanup remains with the design session holding `pencil-concept`; no shared canvas changed.
