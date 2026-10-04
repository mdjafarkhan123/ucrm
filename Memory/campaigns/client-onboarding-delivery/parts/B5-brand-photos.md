# B5 — Brand, photos and proof

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 3.3,
blueprint stage 3 · **Code:** `main`
**Done when:** Logo and photos upload; "no logo" never blocks

## Steps

- [x] Migration `20261014090000_setup_starter_brand_stage.sql` written; tests in `starter-content.spec.ts`
- [x] Saves too big for the database's 8,000-byte answer limit are refused in plain words (`setupStoredBytes`)
- [ ] Apply the migration to dev — outcome check: `list_migrations` shows `20261014090000`, and the draft
      version has a `brand` stage (`setup_stages`). Never apply twice blindly.
- [ ] Mark B5 done in the stage file, NOW.md, INDEX row; delete this note

## Next

Apply the migration to dev after the outcome check above.
