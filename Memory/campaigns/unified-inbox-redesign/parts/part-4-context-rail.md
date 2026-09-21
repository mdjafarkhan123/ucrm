# Part 4 — Contact/context rail

Approved by Jafar 2026-09-21:

- Desktop app, not mobile. No phone-specific work. The existing ≤1050px `SidePanel` drawer stays as-is for
  narrow desktop windows and only reuses the new rail content.
- Look: best-of-class, modern, professional (design skill tokens, SCSS + BEM, Tabler icons).
- Layout: GoHighLevel-style vertical icon-tab strip on the right edge (Jafar chose icon tabs over collapsible
  sections). Every tab needs real content — no fake modules.
- Tabs: Contact, Properties, Requests, Quotes, Jobs, Invoices, Pipeline (opportunities). Automation card stays
  under Contact when it applies.
- Work shown adds Jobs and Invoices, each with status, amount, and a link. Anything the viewer may not see
  stays hidden or empty (money follows `jobs.view_price` / `invoices.view_price`).
- Tab content loads lazily: query off until the tab icon is hovered, prefetch on hover, skeleton if the click
  wins; cached after (CLAUDE.md rule 10).

Built as one piece (no 4A/4B split): a rail component with a Bits UI vertical tab strip, one lazy list per tab,
and the context endpoint now returns only the client plus the visible tab list; `?section=` reads one tab (latest
6, `has_more`). Invoices reuse `invoice_list_page` + `invoice_money`; jobs use `job_list_rows` + `job_money`;
quotes use the version-money lookup. Money is `null` without the price permission.

Completion gate: ownership, follower, and related-work behavior preserved; light + dark desktop browser check.
