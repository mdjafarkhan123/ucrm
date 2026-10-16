# Contractor design concept — now

**Goal:** Phase A: build every designed screen, update shared parts, delete old code. Phase B: researched, premium new concept, applied app-wide.
**Core agreement — read on every resume:** `docs/contractor-design-concept-behavior-contract.md` — Summary, Experience target, Not doing.
**Stage:** Building, Phase A. A1 is on main. The A2 batch below is built on branches and **waiting to merge** (2026-10-16).

**Branches waiting to merge** (each has its note in `parts/<task>.md` on that branch; claims still held): `claude/a2-quote-details`, `a2-client-details`, `a2-request-details`, `a2-invoice-details`, `a2-payment-details`, `a2-home`, `a1b-clients-requests` (migration applied), `a1b-quotes-invoices` (two migrations applied). Inbox (`a2-inbox`) is being built in another terminal.

**Next:** (1) run `npm run check`, lint and focused tests once for the whole batch; (2) merge the branches into main one at a time, resolving shared-part conflicts (SectionBlock, RailCard, MoneyFeatureCard, AttentionCard, WorkRecordHeader, RecordFactsList); (3) then A2b below; (4) Settings; (5) A3 Schedule.

**Decisions by Jafar (2026-10-16):** money/feature cards stay light in dark mode. Jafar delegated the rest to a contractor's view; do these as A2b after merging: progress strip (Request→Quote→Job→Invoice→Paid) on every record page using existing links (verify invoice→job link); Call/Text/Directions icons on Request, Invoice, Client headers; Request list lines "Asked for", assessor, "Quote #". Skipped: Payment History button, labelled "More" button.

**Still open:** "Changes requested" colour on Quotes.
