# Part 5 — Complete customer documents

**Campaign:** deferred-launch-sweep · **Plan:** Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md (spec; deleted when this ships)
**Code:** `main`
**Done when:** invoices and quotes email both the client's primary address and a separate billing-contact
address (when one is set), browser-verified on Raad LTD, and the deferred note is deleted.

## Steps

- [x] Prior Part 5 items done — see ROADMAP.md Part 5 line.
- [x] Migration `20260928200000` (billing-contact column/constraints, `create_client`/`update_client`,
      `enqueue_invoice_communication_email`/`enqueue_quote_communication_email`) written and applied.
- [x] Zod (`foundation.schema.ts`), duplicates (`duplicates.ts`), API types (`clients/api.ts`), the client
      GET/duplicates routes, and all three UI spots (`ClientDetailsForm`, `ClientForm`,
      `[id=uuid]/+page.svelte`, `ClientDetailHeader`) all updated for `billing_email`. See the code and its
      comments for the shape; nothing here needs restating.
- [x] Invoice/quote single-send and batch-deliver routes now generate a second access link and pass it to
      the RPC (unconditionally — the RPC only spends it if a billing contact exists).
- [x] **Bug found while regenerating `database.types.ts`:** `CREATE OR REPLACE FUNCTION` doesn't replace when
      the argument count changes — it silently overloads. Migration `20260928200000` left the old 6-arg
      `enqueue_invoice_communication_email`/`enqueue_quote_communication_email` alive alongside new 8-arg
      ones (confirmed via `pg_proc`, query in Notes). Fix migration `20260928212000` drops the stale
      overloads — **written and committed, NOT yet applied**.
- [ ] **Blocked:** `db push --dry-run` refuses with `DbPushMissingLocalError` — remote has migration
      `20260928211000` from Part 7's worktree, not yet merged to `main`/not in this folder. `212000` sorts
      after it once that file lands.
- [x] `database.types.ts` regenerated and committed (shows the overload as a union type for now).
- [ ] `npm run check` not run successfully — machine was memory-starved by another session's concurrent
      `svelte-check`. Changed `.svelte` files were checked individually with the Svelte MCP autofixer instead
      (no new issues; its warnings are pre-existing SCSS-nesting noise).
- [ ] Browser-verify on Raad LTD: billing email on a real client, send invoice + quote, confirm two sends,
      confirm the billing link opens the document. **Not started.**
- [ ] Delete `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md` + its ROADMAP.md
      mention once shipped and verified; mark Part 5 done with the date.

## Next

1. Check if the Part 7 session/worktree has merged. If yes, its `20260928211000` file is on `main`: dry-run
   then apply `20260928212000`, then re-run the `pg_proc` query in Notes to confirm one `oid` per function.
   If not merged yet, wait — don't touch that worktree/branch.
2. Run `npm run check` (check `free -h` first) and fix anything it finds.
3. Browser-verify on Raad LTD, then close out the note's last two steps.

## Notes

- `client_contacts`/its own `client_contact_methods` rows exist but have no CRUD UI anywhere — out of scope.
  The billing contact is deliberately just a second flagged email on the client's own contact methods.
- `client_contact_methods_org_value_unique_idx` is organization-wide, not per-client — inherited, not new.
- Overload check: `select p.oid, p.pronargs, pg_get_function_identity_arguments(p.oid) from pg_proc p join
  pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
  ('enqueue_invoice_communication_email', 'enqueue_quote_communication_email') order by p.proname,
  p.pronargs;` — one row per name means fixed.
- Two sessions are applying migrations to the same shared remote DB concurrently this campaign (this session
  and Part 7's worktree). If `DbPushMissingLocalError` recurs: find who applied the missing version, get
  their file onto `main`, timestamp any new local migration after it.
