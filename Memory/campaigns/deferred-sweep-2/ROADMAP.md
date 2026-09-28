# Deferred sweep 2 — roadmap

Jafar approved all nine, in this order, 2026-09-29. Spec = the named note in `Memory/deferred/`.

| Part | Delivers | Note | Done when | State |
| --- | --- | --- | --- | --- |
| 1 Quote API tests | checks trust the rate limit | `quote-api-tests-never-learned-the-rate-limit` | quote specs pass on `main` | In progress |
| 2 Client-name search | Jobs and Quotes find by client | `jobs-and-quotes-list-search-also-misses-client-name` | searching a client's name lists their jobs/quotes | Not started |
| 3 Requests KPI cards | real New requests + Conversion rate | `requests-new-and-conversion-rate-cards-have-no-real-data-source` | cards show real 30-day numbers | Not started |
| 4 Held-booking status | label, filter, counts | `request-needs-approval-status-has-no-label` | Jafar: "Follow Jobber" — research Jobber's label first | Not started |
| 5 Address names | street only, like Jobber (Jafar) | `every-unnamed-address-is-called-primary-property` | no fake "Primary property"; old ones cleaned | Not started |
| 6 Archive in history | timeline lines for archive/restore | `client-archive-and-restore-not-in-client-history` | both show in the client timeline | Not started |
| 7 Client work + schedule | real Work overview / Client schedule | `client-work-overview-and-schedule-sections-are-empty` | boxes show the client's real work | Not started |
| 8 Type check | `npm run check` clean of the union error | `resolve-route-union-type-too-complex-to-represent` | check passes that error | Not started |
| 9 Chat identity | resolved conflict stays resolved | `resolving-a-chat-identity-does-not-stop-the-next-conflict` | Jafar picks model; repeat conflict gone | Not started |
