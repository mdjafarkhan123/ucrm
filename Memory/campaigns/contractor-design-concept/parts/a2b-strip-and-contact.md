# A2b — progress strip, quick contact, Request list lines

Branch `claude/a2b-contact-strip` (worktree `.worktrees/a2b-contact-strip`). Claim `511a7383cecd`. **State:** Waiting to merge.

**Built**
- Progress strip (Request > Quote > Job > Invoice > Paid) on Request, Quote, Job and Invoice pages. One database call
  `record_chain(org, kind, id)` (migration `20261217090000_a2b_record_chain`, applied and recorded) follows the links
  and checks each step with the page's own can_view rule; a step the member cannot open comes back "restricted"
  (shown without link or detail). `GET /api/records/chain`, `$lib/work/record-chain.ts` (builder + query key),
  `work/RecordTrack.svelte`. The Quote page's own inline strip logic was replaced by it. Pages invalidate
  `RECORD_CHAIN_KEY_PREFIX` beside their detail query.
- Verified: invoice -> job link exists through `invoice_sources` (23 of 35 invoices have a job; the other 12 are
  standalone, so their strip says "Started as a ..."). Request/quote/job links are unique one-to-one.
- Round Call / Text / Directions buttons: new shared `work/QuickContactButtons.svelte` (used by `ClientSummaryCard`,
  now also on Request and Invoice, and by the Client header, where it replaced the disabled "Call" button).
  Invoice phone comes from the invoice API (primary contact, read under the member's own access); Directions go to
  the invoice's first property, else the billing address.
- Request list: "Asked for <day>" + window (website bookings waiting for approval), assessor name under the time,
  "Quote #n" / "Job #n" link under Converted. `/api/requests` now also returns `assignee_ids` and `converted_to`
  (two extra batched reads per page).

**Not done:** Payment details and Client pages carry no strip (a payment sits on invoices, a client is not on the
line). Job header has no Call/Text/Directions (not asked).
Type check, lint and tests NOT run (Jafar: once, after every screen is built).
