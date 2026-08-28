---
name: typecheck-failures-unrelated-to-website-chat-wc1
description: two pre-existing npm run check errors found incidentally while verifying WC1, in files this session never touched
metadata:
  type: project
---

`npm run check` (2026-09-02, during Website Chat WC1) reported two failures in files unrelated
to WC1's package-limit work; confirmed pre-existing via `git diff --stat` (no diff on either
file this session):

- `src/lib/components/jafar/EmailDomainActions.svelte:324` — a handler typed
  `(domain?: Domain) => void` passed where `(event: MouseEvent) => void` is expected.
- `src/routes/(app)/quotes/[id]/+page.svelte:530` — an `onclick` handler's implicit return type
  is `any` because it lacks a return-type annotation.

**Reactivation trigger:** next time either file is touched for an unrelated reason, fix its
error then.
