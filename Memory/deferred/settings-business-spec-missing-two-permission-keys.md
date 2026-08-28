---
name: settings-business-spec-missing-two-permission-keys
description: settings-business.spec.ts asserts a stale permissions object missing price_book_manage and quotes_manage
metadata:
  type: project
---

`src/routes/api/settings/settings-business.spec.ts` (around line 386) asserts
`body.permissions` equals an object with only `business_edit`, `team_manage`,
`communications_manage`, and `taxes_manage`. The route now also returns `price_book_manage`
and `quotes_manage`, so the test fails on current `main` — reproduced via `npx vitest run`,
unrelated to any Communications change. Not investigated further; likely a fixture the
Quotes/Settings campaign left behind when those permissions were added.

**Reactivation trigger:** next time the Settings or Quotes campaign touches this route or
its test.
