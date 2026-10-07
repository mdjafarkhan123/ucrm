# 2 — Split into build parts

**Campaign:** package-basics-unlock · **Plan:** `docs/package-basics-unlock-behavior-contract.md` (approved 2026-10-07)
**Research:** `docs/research/package-basics-unlock-2026-10-07.md` (where a missing feature still shows)
**Done when:** Jafar approves the part list

## Steps

- [x] Draft the part list, riskiest first
- [ ] Jafar approves or corrects it
- [ ] Write the parts into `ROADMAP.md`, mark Part 2 done, point `NOW.md` at the first build part

## Proposed list (shown to Jafar 2026-10-07)

1. **The package decides what shows** — one shared answer to "what does this business's package include";
   tie the loose permissions (Settings pages, time, expenses, field records) to their features; menu built
   from it with no flash. Check: a test business without Quotes sees no Quotes in the menu, Settings, client
   summary, or search, and a direct request is refused. Waits for nothing.
2. **Quotes, Invoices, Customer access leave no trace** — dashboard, client page, automation triggers,
   notifications, setup steps, customer portal; these become untickable. Check: test business without them
   finds nothing broken or empty on any page. Waits for 1.
3. **Requests, Jobs, Scheduling leave no trace** — same for these, including the review-request job choice.
   Check: the campaign's reviews-only test business on desktop and phone. Waits for 1.
4. **Needs in the package builder** — auto-ticks with notes, the remove-both question, the pick-one question,
   publish refusal, exceptions follow the same needs; not-ready basics stay locked with a reason. Check: ticking
   Quotes adds Jobs and Scheduling with notes. Waits for 2, 3, and the package-builder P16 tour.
5. **Moving to a smaller package** — preview of open items, records hidden then restored on upgrade,
   automations paused, customer links keep working. Check: a test business with an unpaid invoice moves to
   reviews-only; the customer still pays by the link; moving back shows the invoice again. Waits for 4.
6. **Final tour** — Jafar runs the campaign done-check in the browser. Waits for 5.

## Next

Waiting for Jafar's answer on the list above; then write it into `ROADMAP.md`.
