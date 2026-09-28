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
- [x] Unblocked: `20260928211000` landed on `main` (Part 7d, `b7be59e4`). Dry-run confirmed only `212000`
      pending, then applied it to the linked remote. `pg_proc` re-check: one 8-arg row per function — fixed.
- [x] `database.types.ts` regenerated and committed — overload union is gone (one entry per function now).
- [x] `npm run check` ran clean of any issue from this part's code (`--max-old-space-size=6144` needed; default
      heap OOMs on this machine's current load — note that for future runs). Found 3 pre-existing
      `resolve()` "union type too complex" errors and 2 pre-existing warnings in unrelated files (not touched
      by this part, not caused by it) — recorded as new deferred note
      `resolve-route-union-type-too-complex-to-represent.md`, not fixed here.
- [ ] Browser-verify on Raad LTD: billing email on a real client, send invoice + quote, confirm two sends,
      confirm the billing link opens the document. **Blocked:** the Claude-in-Chrome browser extension isn't
      connected this session (tabs_context_mcp reports "Browser extension is not connected"). Needs Jafar to
      either verify manually or reconnect the extension.
- [ ] Delete `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md` + its ROADMAP.md
      mention once shipped and verified; mark Part 5 done with the date.

## Next

1. Once the browser extension is connected: log in as Raad LTD owner (`info.socialmediauser1@gmail.com` /
   `11223344`) at `https://app.upliftcontractor.com`, set a billing-contact email on a real client, send an
   invoice and a quote, confirm both the primary and billing addresses receive a send, and confirm the billing
   link opens the document.
2. Delete `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md` + its ROADMAP.md
   mention once verified; mark Part 5 done with the date.

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
