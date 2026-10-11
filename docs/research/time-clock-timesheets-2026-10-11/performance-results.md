# Timesheets — performance verification (2026-10-12)

```text
Performance Verification – Timesheets page (time clock Part 4)
Workload contract : one business, 15 people who time their work; 26 weeks of history (≈17,600 entries);
                    a very busy week of 1,260 entries (12 a person a day), 4 people with overlaps, a
                    timer forgotten since Sunday. One manager reading at a time. Target: the page is no
                    slower than the existing daily list pages on the same phone.
Layers reviewed   : database reads, API, browser delivery and rendering, row-open interaction.

Layer        | Evidence                                                             | Result
-------------|----------------------------------------------------------------------|-------
Database     | Window scans use (organization_id, started_at, id) and the per-person | ✅
             | index: 903 rows in 0.7 ms, 30 rows in 0.06 ms, all buffer hits.        |
             | Overlap pass over the busy week: 1,261 rows in 8 ms.                   |
             | timesheet_summary week 24 ms warm (30–38 ms first call), day 16 ms;    |
             | timesheet_entries one person's week 6–17 ms.                           |
API          | One RPC per request after the sign-in check; no loops. Week summary    | ✅
             | 6.0 KB, day 4.3 KB, one person's busy week 35 KB (JSON before gzip).   |
             | Summary size grows with people × days, never entries; entries capped   |
             | at 400 with a truncated flag.                                          |
Browser      | Production build, phone 390×844, CPU 4× slower, ~4G (150 ms, 1.6 Mbps), | ✅
             | API mocked so only the page is measured, median of 5 cold loads:       |
             | 15 rows shown at 6.0 s, LCP 6.1 s, CLS 0.000, 1,915 DOM nodes.          |
             | Baseline, same profile, real API: Jobs data arrives at 6.6 s, Schedule  |
             | at 8.2 s; every page makes the same 251 requests (≈410 KB JS) for the    |
             | shared app shell. Timesheets' own code: 16.0 KB JS (5.8 KB gzip),      |
             | 13.7 KB CSS (2.2 KB gzip).                                             |
Interaction  | Opening a row with an 84-entry week: entries on screen 205 ms after    | ✅
             | the click (fetch starts on hover); slowest interaction 32 ms.           |

Changes made       : none needed.
Unverified/deferred: the shared shell's cold start on a slow phone (≈6 s, 251 requests) is the same
                     for every page and belongs to a whole-app release audit, not this part. vite
                     preview serves HTTP/1.1 without the production CDN, so production request timing
                     will differ. No concurrency test: a manager-only weekly read is not a high-traffic
                     path.
Capacity statement : one 15-person business with half a year of history, read by one manager at a
                     time. Nothing larger is established.
Overall            : ✅ Supported
```

Reproduce: `performance-proof.sql` (rolled back; run with `psql "$SUPABASE_DB_URL" -X -f …`) and
`performance-browser.mjs <mock-summary-week.json> 5` against `npm run preview -- --port 5181`, with the
mock made by `make-mocks.mjs`.
