# Client detail's financial summary widget is empty for everyone, not just some roles

- **Priority:** P2
- **Why postponed:** Found incidentally during the paid-launch-trust Part 16 audit, across three different
  roles (office, sales, finance) on three different real clients (one of them — Greenfield Property Group —
  has real quotes on file). The client detail page's Lifetime/Open quotes/Active jobs summary shows "Once you
  start invoicing/quoting..." placeholder copy regardless of role and regardless of whether the client
  actually has billing history. The raw `/api/clients/{id}` payload contains no lifetime/balance/revenue
  fields at all — this looks like the summary was never wired to a real data source, not a permission leak
  (`customers.view_financials` gating itself works: sales, which lacks that permission, gets the same empty
  widget as finance, which has it — no difference was observed either way).
- **Reactivate when:** Client detail's financial summary is scoped, or a contractor asks why their client
  page shows no billing history for a client that clearly has some.
- **Constraint:** Not a security issue — do not route through the paid-launch-trust campaign. Whatever
  populates this widget needs an actual query against quotes/invoices totals per client; check whether one
  was ever built for it.
- **Pointers:** Client detail page's financial summary widget; `/api/clients/[id=uuid]` payload shape.
