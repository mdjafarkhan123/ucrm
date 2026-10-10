# Jafar Business Management — roadmap

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| P1 Review the journey | Complete lead-to-client journey, two-area navigation, pipeline, and first useful release direction | — | Jafar's corrections or approval are in the plan | Done 2026-10-06 |
| P2 Sending and reuse limits | Verified email readiness, reply path, country/channel limits, and suitable reusable capabilities | P1 | The plan promises only behavior that can actually work | Done 2026-10-07 |
| P3 Team, booking, Settings, and conversion details | Roles, booking, Settings, pricing, payment handoff, and edge cases | P1 | Open behavior questions are settled and Jafar approves the plan | Done 2026-10-07 |
| P4 First release scope | Agreed complete workflows for release one and what follows later | P2, P3 | Jafar approves the user-facing release scope and priorities | Done 2026-10-07 |
| P5 Design and build roadmap | Reuse and risk audit, premium UI/UX direction, and thin complete build parts covering release one through final browser approval | P4 | Jafar approves the build parts, their order, and observable checks | Done 2026-10-07 |

Build stages (approved 2026-10-07, built in this order):

| Stage | Delivers | State | Parts |
| --- | --- | --- | --- |
| A Foundations | One shared access check, two entrances, Settings home | Done 2026-10-07 | — |
| B Leads to client | Leads, history, contact approval, Deals, Won and handover | Done 2026-10-07 | — |
| C Your day | Home next actions, calendar and reminders, activity report | Done 2026-10-09 — speed (lab): C2 calendar week ~10 ms at 50k Leads; C3 report (Leads → Report) at 50k Leads / 500k history lines: month 29 ms, 90 days 153 ms, year 475 ms, all time 1.3 s. Playwright needs `executablePath: '/usr/bin/brave'` | — |
| D Team | Teammate invitations and sign-in, permissions, assignments | Done 2026-10-09 — invitations, area and action switches, Lead owners, teammates' own home and calendar, Jafar's Mine/Everyone switch | — |
| E Public booking | Booking page, reschedule and approval, hosts, Zoom, Google Meet | In progress — E1 done 2026-10-09 (phone lab, 4× CPU + slow 4G, production build: `/book` LCP ~0.6 s, CLS 0); E2 done 2026-10-09 (change/cancel links, approval mode, request card on the Lead page); E3 done 2026-10-10 (meeting types, hosts, change host); E2b next | `stages/E-booking.md` |
| F Final tour | Jafar's desktop and phone approval of release one | Not started | `stages/F-finish.md` |

The campaign finishes only when every stage is built, tested, and approved in the browser.
