---
name: packages-editor-seat-and-email-allowance-fields-have-an-unsound-null-check
description: pre-existing TS "possibly undefined" errors in the packages editor's openEditor for employeeSeatState/operationalEmailState/essentialEmailState
metadata:
  type: project
---

`npm run check` fails on `src/routes/jafar/(protected)/packages/+page.svelte` at the `seats`,
`operationalEmail`, and `essentialEmail` lookups in `openEditor()`: the guard uses
`x?.limit_value !== null` but the true-branch then reads `x.limit_value` without the `?.`,
so TypeScript can't narrow away `undefined`. Found while adding the two Website Chat limit
fields (WC1) right next to this code — fixed the same pattern in the two new fields
(`websiteChatWidgets`/`websiteChatAcceptedConversations` now use `x && x.limit_value !== null`)
but left the three pre-existing instances alone since they're outside WC1's scope.

**Reactivation trigger:** next time this file is touched for an unrelated reason, apply the
same `x && x.limit_value !== null` fix to the three pre-existing fields.
