# A5g — Reuse and confirm

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** A confirmed phone is not stored twice; a different one is kept separately

## Steps

- [x] Migration `20261011090000_setup_reuse_answers` written: answer type `reuse` + `reuse_from`, carried like `pick_from`
- [ ] Apply it to dev
- [ ] Catalogue: a reuse copies its earlier question's answer rules; "Yes" saves `{"same_as": key}`; server checks and clears confirmations when the earlier answer is cleared
- [ ] Client box: earlier answer shown, "Yes, use this" / "Use a different one here", Change link; plain box when nothing to reuse
- [ ] Editor: "Use an earlier answer" type with the question to reuse
- [ ] Tests, svelte-check, browser check of the editor, commit

## Next

Apply the migration to dev, then the catalogue step.

## Outside actions

- Apply migration `20261011090000` to dev — check: `list_migrations` shows version 20261011090000 — pending

## Notes

- Earlier answers that can be reused: built-in ones, or any type except photo/file, pick or reuse; and only
  ones always asked (no "show only if" on an earlier answer). If the earlier question isn't asked for this
  client (stage not in package) or isn't answered, the reuse question is asked as a plain box.
