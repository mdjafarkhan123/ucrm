# Pre-baseline migrations (reference only)

These ~500 files were the repo's migration history until 2026-09-21. They do **not** rebuild the live database
(the repo and the managed database had drifted: duplicate versions, files edited after being applied, changes
applied only through the Supabase console). `supabase/migrations/20260101000000_baseline_*.sql` replaced them.

- The live database is the truth. To see how something is built today, read the baseline or query the database, not these files.
- Use these only to find the _reason_ a thing exists (the comments explain many decisions). Older docs point at file
  paths in `supabase/migrations/`; find the same file name here.
- Never copy a function body from here: 146 of them differ from live (144 only in comments or formatting, 2 in real logic).
- Do not move any file back into `supabase/migrations/`.
