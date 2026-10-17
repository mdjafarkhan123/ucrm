# Billing Settings — implementation checkpoint

2026-10-17 · `codex/settings-billing-app` · `/tmp/ucrm-settings-billing-app` · port 5212.
Claim `46295b95f941` stays held for parent review/integration. Four approved top-level
routes implemented, pending parent review and deferred final validation. No main merge.

| Route | Implementation |
| --- | --- |
| `/settings/taxes` | Original dark blue business-default hero, real rate/count values, saved-rates card, default badge and existing action menus/dialogs. |
| `/settings/payments` | Shared approved Settings header/cards, existing Stripe state, payment switches, other-payment form, setup/support rail and existing pinned save bar. |
| `/settings/quotes` | Two-column cards; terms/representative first, private margin/signature policy second. Existing independent saves and conflicts preserved; last-editor notes moved into card footers. |
| `/settings/invoices` | Payment-terms table left; Defaults and Opening balances right; accounting export across the full width. Existing protected terms, menus and dialogs preserved. |

Opening-balances import is unchanged and excluded from this four-page batch: no approved
subpage layout exists. Its existing link remains available.

Source: approved originals in live `classic.pen`: Taxes `o1A1w`, Payments `NnzgL`,
Quotes `v8iq7i`, Invoices `KO472`. Settled Jobber-based behavior reused from existing
Settings; this is presentation-only. Query ownership, financial rules, validation,
permissions, conflicts and server/API code unchanged. Reuses shared
`SettingsPresentation` from parent commit `a309defa` (cherry-picked `5088c37b`).

## Evidence

- `npm run dev -- --host 127.0.0.1 --port 5212`: running.
- `node /tmp/billing-browser.cjs`: actual contractor owner, 1440×1100, all four pages
  opened in light/dark; successful full run had no console/page errors or viewport
  overflow. Final Quotes/Invoices rerun after table-fit correction also clean.
- Screenshots: `/tmp/billing-settings-{taxes,payments,quotes,invoices}-{light,dark}.png`.
  Reviewed against Pencil. Fixed missing Tabler icon, card action positioning, table
  horizontal minimum width, quote footer clipping and visible target-margin label.
- `node /tmp/billing-interactions.cjs`: Add tax rate/Add payment term/default dialogs
  opened and dismissed; quote margin and payment-tip drafts restored with Cancel.
  Final run passed with no browser errors and no remote writes.
- Targeted Prettier formatting completed; `git diff --check` clean.

One intermediate screenshot refresh hit Chromium `ERR_INSUFFICIENT_RESOURCES` while
several local previews were active; a later focused Quotes/Invoices refresh succeeded.
Earlier switch-check attempts targeted the hidden checkbox; final run used its visible
label and verified the actual checked value.

## Deferred and next

Typecheck, lint, tests, full build, autofixer and complete save journeys deliberately
deferred at Jafar's request. Desktop-only campaign scope. No saves, Stripe actions,
uploads, destructive controls, imports or downloads executed. Existing shared dark-shell
contrast and button appearance remain outside this assignment. Parent reviews and
combines branches, then runs deferred validation after the screen batch is built.
