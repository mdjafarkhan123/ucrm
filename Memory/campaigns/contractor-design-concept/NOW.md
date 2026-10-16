# Contractor design concept — now

**Goal:** Phase A: build every designed screen, update shared parts, delete old code. Phase B: researched, premium new concept, applied app-wide.
**Core agreement — read on every resume:** `docs/contractor-design-concept-behavior-contract.md` — Summary, Experience target, Not doing.
**Stage:** Building, Phase A. A1 and the whole A2 batch (Home, Inbox, Quote/Request/Invoice/Client/Payment details, all list gaps) are on main as of 2026-10-16. Their part notes are in `parts/`.

**Not run yet (Jafar: once, after every screen is built):** `npm run check`, lint, the focused tests, and the speed check for the Quotes and Invoices list slices. The merge was checked by loading every screen in the running app: no errors. The merge fixed one broken brace in `SectionBlock.svelte`.

**Next:** (1) A2b below; (2) Settings: Pencil has only Home and Business profile, so Jafar decides how the other ~15 pages follow; (3) A3 Schedule (11 Pencil frames); (4) A4 undesigned screens; (5) A5 cleanup; then one whole-app check.

**Decisions by Jafar (2026-10-16):** money/feature cards stay light in dark mode. Jafar delegated the rest to a contractor's view; do these as A2b after merging: progress strip (Request→Quote→Job→Invoice→Paid) on every record page using existing links (verify invoice→job link); Call/Text/Directions icons on Request, Invoice, Client headers; Request list lines "Asked for", assessor, "Quote #". Skipped: Payment History button, labelled "More" button.

**Still open:** "Changes requested" colour on Quotes.
