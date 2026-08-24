# Quote composer has no financial rail or proposal sections

- **Priority:** P2


- **Campaign:** `quotes` Part 4D, decided by Jafar 2026-08-21.
- **Reason:** Discount, Tax, Introduction, Client message, Client view, and customer-facing files all need a
  saved draft with a revision, and `/quotes/new` does not create the quote until Save. Staging them locally
  and firing the commands after create risks a half-saved quote. Jobber's own composer does carry them.
- **Reactivation trigger:** Jafar asks for these on the composer, or Part 5 changes how a quote is created.
- **Prerequisites:** decide whether create takes the whole document in one write, or the composer keeps
  redirecting to the detail page to finish.
- **Checkpoint:** `src/lib/components/quotes/QuoteForm.svelte`, `src/routes/api/quotes/+server.ts`.

