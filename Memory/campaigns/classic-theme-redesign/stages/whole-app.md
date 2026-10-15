# Classic redesign — whole-application stages

**Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Later stages · **Order approved:** Jafar,
2026-10-15. Start after the shared-parts stage and first six record pages. Each named screen follows the
plan's design → approval → build → live check → synchronize shared parts → remove superseded look loop.
An approved Pencil frame is a head start, not proof that its application screen is built.

| Stage | Screens and result | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| L — Lists | Jobs, Clients, Requests, Quotes, Invoices, one by one; approved 1440px designs and their separately approved additions | B12 | Each list's main journey, permissions, filters, empty/loading/error states, light/dark and desktop-width checks pass; its old local styling and rejected variants are removed | Planned |
| S — Schedule | Approved Week, Day, Month, Unscheduled drawer, and empty-slot Job/Request/Event dialogs first; remaining previews, forms, moving, filters, route/map and Task card receive design approval before their build | L | Scheduling, moving and preview journeys retain behavior; all approved Schedule screens are live-checked and the old look is removed | Planned |
| T — Settings | Approved Settings home and Business profile first, including approved search, setup, balance and preview additions; then each remaining Settings page | S | Each setting is reachable and saves exactly as before; desktop layout and text scaling are checked; all Settings routes are accounted for | Planned |
| H — Home and Reports | Owner and worker Home, Insights and reports, coordinated with `crm-launch-readiness` Part 13 | T and that campaign's final designs | Approved designs are built; amounts reconcile with the books and permissions; live desktop journeys pass | Planned |
| W — Remaining Business Workspace | Pipeline, Communications, Marketing, Files, Reviews, Timesheets, creation/edit/import flows, team and setup screens not covered above | H | Every signed-in Business Workspace route is assigned a screen part and passes the same design/build/clean check | Planning gate |
| C — Uplift Control Room | `/jafar` workspace and its sign-in/setup routes, without changing owner powers | W | Every Control Room route is assigned and checked with the roles that use it | Planning gate |
| P — Customer and entry journeys | Business login/password and application-owned request, quote, invoice/payment, booking, forms, portal and other public journeys | C | Every application-owned entry/customer route is assigned and checked on desktop web | Planning gate |

Before W, C and P, make a route-and-component inventory and split each into focused screen parts. This is a
sequencing gate, not a new vote on whether those areas belong to the campaign: Jafar approved whole-app scope
on 2026-10-15. The separate theme-foundation first release still covers only the signed-in Business Workspace.
Coordinate H with its owning campaign; do not duplicate its product rules here. Do not let further Pencil
concepts run far ahead of implementation.
