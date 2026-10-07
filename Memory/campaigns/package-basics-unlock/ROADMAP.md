# Package basics unlock — roadmap

| Part                         | Delivers                                                                                                                                       | Waits for | Done when                                                                               | State       |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------- | --------------------------------------------------------------------------------------- | ----------- |
| 1 Plan: unlocking the basics | Settles which basics stay in every package, the full "needs" list, what a business sees when a feature is off, and moving to a smaller package | —         | Still unclear is empty or holds only what Jafar left for later; Jafar approves the plan | Done 2026-10-07 |
| 2 Split into build parts     | Build parts written into this roadmap, riskiest first                                                                                          | 1         | Jafar approves the part list                                                            | Done 2026-10-07 |
| 3 The package decides what shows | One shared package answer; loose permissions (Settings pages, time, expenses, field records) tied to their features; menu built from it with no flash | 2 | A test business without Quotes sees no Quotes in the menu, Settings, client summary, or search; a direct request is refused | In progress — `parts/3.md` |
| 4 Quotes, Invoices, Customer access leave no trace | Dashboard, client page, automation triggers, notifications, setup steps, customer portal hide them; these three become untickable | 3 | A test business without them finds nothing broken or empty on any page | Not started |
| 5 Requests, Jobs, Scheduling leave no trace | The same for these three, including the review-request job choice; they become untickable | 3 | The reviews-only test business checked on desktop and phone | Not started |
| 6 Needs in the package builder | Auto-ticks with notes, remove-both and pick-one questions, publish refusal, exceptions follow needs, not-ready basics locked with a reason | 4, 5, package-builder P16 tour | Ticking Quotes adds Jobs and Scheduling with notes | Not started |
| 7 Moving to a smaller package | Preview of open items; records hidden, restored on upgrade; automations paused; customer links keep working | 6 | A business with an unpaid invoice moves to reviews-only, the customer still pays by link, moving back shows the invoice | Not started |
| 8 Final tour | Jafar runs the campaign done-check in the browser | 7 | Jafar approves on desktop and phone | Not started |

**Campaign done-check (Jafar, 2026-10-07):** Jafar builds a package with Review requests and only the basics that
must stay. A test business on it sees Customers and Reviews but no Requests, Quotes, Jobs, Schedule, or Invoices
anywhere, sends a review ask by hand, and finds no broken or empty part on any page.

Any build part that changes the package builder waits for the package-builder campaign's P16 tour, so the tour
does not test a moving target.
