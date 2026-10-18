# C3 — Jobs list in the concept

**State:** Approved by Jafar and built on 2026-10-18. The Pencil frame is "Concept · Jobs list · Owner · 1440" (`t8ULdJ`) in `concept.pen`. Code and the saved drawing are on `main`.

**Agreement:** Keep the live Jobs list's data and behaviour, and keep its table look. The concept changes its presentation: status-coloured icon tiles, a green money card, a tiled header, and a "More" button with a trailing chevron. There is no action behind the Jobs menu yet. Its unavailable reason is "Bulk actions and exporting arrive later." Jafar approved applying shared component changes to every page that uses them. He also approved the concept header and More button throughout the app, with old presentation code removed.

**Built:** `AttentionCard` uses the status icon tiles on Jobs, Requests, Quotes, Invoices and Clients. `MoneyFeatureCard` uses the green feature look on those lists and the client and invoice record pages. `PageHeader` uses the concept's icon tile and record colour across its callers. `DropdownMenu` supplies the shared "More" style, including the white disabled Jobs, Requests and Quotes triggers. Clients uses the same menu style with working actions. The older page-specific More buttons and styles were removed. New token: `--color-feature--alert`.

**Evidence:** Earlier Jobs and related-list checks are recorded in commits `90270308` and `2824659d`. On this integration, the local browser produced 1440px captures of Jobs, Requests, Clients, Quotes and Invoices, plus a 390px Jobs capture. Jafar asked to defer any further checks until the whole campaign is complete. The campaign-end pass must cover the remaining screen, dark-mode, interaction, lint and type checks; no result should be inferred from the interrupted broad check.

**Next:** C4 Job details: research its content, draw it at 1440px in Pencil, and show Jafar for review before building.
