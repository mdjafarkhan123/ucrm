# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **6b-1b CLOSED and committed 2026-09-06.** The enqueue bug fix is applied to remote DB and confirmed live
  (real send to Raad LTD invoice #1 returned a clean 201/queued with the correct org-default sender — no
  crash). No browser tool was available this session, so verification was done at the API/DB level instead of
  clicking through the UI; the page wiring itself was already browser-verified in an earlier session.

## Residual (not blocking)

The "no sender ready" 422 refusal path (`src/lib/server/communications/email-send-errors.ts`) is only
type-checked, not exercised live — every org with an issued invoice in the current DB now has a working
sender. Same shape as the already-shipped quote 55000 mapping, so risk is low. Revisit only if a real
no-sender send is reported broken.

## Next thread: 6c (Jafar flagged 2026-09-06) — awaiting his go-ahead

Invoice **contract/disclaimer** gap — it is in the behavior contract but not implemented. Mirror the shipped
quote disclaimer: enter / save / edit on the draft, display on the customer invoice document, keep it
SEPARATE from payment terms, and FREEZE its content when the invoice is issued. Reference quote pattern:
`src/routes/(app)/quotes/[id]/+page.svelte` "Contract disclaimer" SectionBlock + `contract_disclaimer` on
quote versions + `CustomerQuoteDocument`. See ROADMAP row 6c.

## Notes

- 6a committed 2026-09-05 (`3959681`). Deferred follow-up logged:
  `Memory/deferred/email-sender-setup-flow.md` (guide contractors to set up a sending email when missing).
- Mirrors: quote detail send/copy wiring, `QuoteEmailDialog`, `enqueue_quote_communication_email`.

Resume command: `read memory and continue the Invoices campaign` (will pick up 6c once Jafar approves it).
