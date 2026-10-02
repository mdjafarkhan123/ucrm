# Sales Pipeline: Performance Verification

Verified 2026-10-02 in the practice database on this computer (Docker `supabase_db_ucrm`, PostgreSQL 17.6,
8 cores, default settings: 128 MB shared buffers, 4 MB work memory). Method:
`.claude/skills/performance-review/references/verify.md`. Three fixes were made and are on the live database
(migration `20261006100000_pipeline_speed_at_volume.sql`).

To repeat: reset the practice database, run `scripts/perf/pipeline-volume-seed.sql` (about 10 minutes), then
`python3 scripts/perf/pipeline-volume-bench.py <vol|mid> <owner|restricted>`.

```text
Performance Verification – Sales Pipeline (stages A–F)
Workload contract : Assumed, not measured. One person at a time reading the board, the Table, search, and
                    Sales Outcomes. Two fake companies beside eight filler companies (157,700 cards, 426,921
                    stage events, 101,851 Tasks, 57,000 clients in the database):
                      "big"     20,179 open cards, 83,000 cards in all, 30,000 clients, 12 members
                      "midsize"  2,248 open cards,  8,300 cards in all,  3,000 clients,  6 members
                    Each read timed as the owner and as a member with "see every client" taken away (406
                    assigned clients in the big company). Target: nothing a person waits on takes longer
                    than about half a second, and no read does work that grows with other companies' data.
Layers reviewed   : database reads and bulk changes (the functions behind /api/pipeline/* and the Sales
                    Outcomes report). Not reviewed: browser rendering, the network, many people at once.

Layer                      | Evidence (median of 4 warm runs; first run adds about 10 ms)                    | Result
---------------------------|---------------------------------------------------------------------------------|-------
Correctness first          | Fake data: 6,035 sample cards updated with every trigger on, no stage, value,    | ✅
                           | date, or Task field moved. Fixes: 282 calls (3 members x 2 companies x 47 reads) |
                           | return the same rows before and after. Live smoke as the Raad LTD owner passes.  |
Board, one column          | 6–8 ms in the Task order for every column, custom stages and the grouped         | ✅
(26 cards, 32 KB)          | Assessment column (6,000 cards) included. Other sorts 7–12 ms. Owner, unassigned |
                           | and date filters 7–8 ms. Midsize 5–9 ms. Restricted member 17–24 ms.             |
Table (51 rows, 64 KB)     | 9–11 ms in every sort. A page 15,000 rows deep: 10 ms (keyset, no offset).       | ✅
Column headings (counts)   | 5 ms plain or filtered; 1.4 ms midsize.                                          | ✅
Search, big company        | One column 40–95 ms by name or title, 140 ms grouped Assessment with no match,   | ⚠️
                           | 185–235 ms by phone digits. Table 260 ms no match, 490 ms phone digits. Headings |
                           | 120–250 ms. Restricted member 25–250 ms; Table by Quote number 520 ms.           |
Search, midsize company    | 20–30 ms per column, 15–50 ms Table, 15–22 ms headings.                          | ✅
Lead source filter         | Column 9–15 ms, Table 42 ms, headings 29 ms, the list of sources 44 ms (6 ms     | ✅
                           | midsize). Restricted member 20–120 ms.                                           |
Sales Outcomes lists       | Won, Lost, Direct jobs: 2 ms by date, created, or total. By title or client name | ✅
                           | 80 ms at 14,000 Won records (6 ms midsize): sorted after reading, no index.      |
Sales Outcomes numbers     | Tiles 1–6 ms. Report (loss reasons, days to win): 4 ms a month, 31 ms a year,    | ✅
                           | 96 ms All time (7 ms midsize).                                                   |
Conversion tab             | Big: 0.2 s one month, 0.6 s a year, 0.9 s All time. Midsize: 20 ms, 62 ms,       | ⚠️
                           | 81 ms. Grows in a straight line with the company's cards and stage history.      |
Financial report           | Page 8–23 ms, summary 3–21 ms, one month to three years.                         | ✅
Bulk changes (50 cards)    | Owner 50 ms, Task 110–130 ms, move to a custom stage 40 ms. Hard cap of 50.      | ✅
Other companies' data      | Every read re-run on the midsize company with plans logged: after the fixes none | ✅
                           | scans a table past its own organization's rows.                                  |

Changes made (migration 20261006100000, no behavior change):
1. Restricted members. The board, headings, lead source list, and Sales Outcomes asked "may this person see
   this client?" for every card, several times per card (about 0.5 ms each). They now check each card against
   the member's assigned clients read once per request, the same helper the clients list already uses.
   Before, big company (measured before the member had any assignments): column 115 ms, Table 220 ms,
   search 2.3–10.8 s, headings while searching 10.5 s, lead source list 10.4 s, Sales Outcomes page 58 ms.
   After: 17–24 ms, 21 ms, 25–520 ms, 80–200 ms, 20 ms, 5 ms.
2. Search read every company's contacts on each request (57,000 rows for a 2,248-card company). It now reads
   only the searching company's. Midsize column search 78 ms -> 27 ms; big 177 ms -> 94 ms.
3. The Conversion tab read every company's Quotes (62,700 rows). Same fix. Midsize one month 33 ms -> 20 ms.

Unverified/deferred:
- Search at 20,000 open cards is 0.1–0.5 s per request, and the board asks once per column plus the
  headings, about ten requests per search. It reads every open card in the column; there is no search index
  across card, client, address, contact, and phone. Impact: fine for one person; the cost is one company's
  own. Next decision: only if a real company nears 20,000 open cards, move search to an indexed read.
- Conversion tab All time is 0.9 s at 83,000 cards and 227,000 stage events. It is opened on demand and
  cached in the browser. A maintained summary would be the fix; not justified by this evidence.
- Many people at once: no concurrency test was run, and this computer is not production hardware. Owner:
  the production-like load rehearsal in the launch gate.
- Browser: card rendering, bytes over the network, and the phone view were not profiled. Pages are capped at
  50 rows. Owner: G2 walk-through.
- Quote emails are not in the fake data, so the board's "quote email failed" lookup found nothing. It is one
  lookup per Awaiting response card drawn (26 a page).
- Notes and call logs are not in the fake data; they load only when one card is opened.
- Stale pgTAP: `pipeline_quote_board_read_model.sql` and `pipeline_unified_board_and_presentation_setting.sql`
  fail before their first test ("Sorting by Task needs today's date"), from the stage C Task order, not from
  this work. Owner: G2.
Capacity statement : One person at a time, on this computer, with the data above. A company with about 2,000
                     open cards gets every Pipeline read in under 0.1 s. A company with about 20,000 open
                     cards gets the board, Table, and lists in under 0.1 s, search in 0.1–0.5 s, and the
                     All time Conversion tab in about 0.9 s. Nothing is claimed about how many people or
                     companies can do this at the same time.
Overall            : ⚠️ Partially verified (nothing blocks; concurrency and the browser are unmeasured)
```
