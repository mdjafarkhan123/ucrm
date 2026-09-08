# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Through 15c complete. 15c-1 and 15c-2 are written and fully browser-verified (owner + Field),
  console clean, production build passing.
- Uncommitted on `schedule-5b-visits-card`: 15b plus 15c-1/15c-2. Jafar has not asked for a commit.

## Exact next action

Start Part 15d (collected Job signatures and immutable signed evidence). It is `Planned`, not yet scoped
for implementation.

1. Load `.claude/skills/jobber/SKILL.md` and re-read `docs/jobs-behavior-contract.md` for any signature
   language. Check `Design/Jobber Jobs/` for captured signature screens; visit Jobber if missing.
2. Load `supabase-postgres-best-practices` before drafting any table/RLS — 15d adds a signed-evidence store
   that later Job edits must not be able to rewrite.
3. Present the 15d plan (topology, tables, RLS, the immutability mechanism, the standard pattern and who
   builds it that way, risks, completion gate) to Jafar. Wait for approval before writing code.

- Checklists work fired no performance gate: reads bounded by one Job/Visit; no visits-list badge exists.
  If 15d introduces any list-level signature indicator, run the `performance-review` design branch first.

## Pointers

- Roadmap/contract: `Memory/campaigns/jobs/ROADMAP.md`, `docs/jobs-behavior-contract.md`.
- 15c shipped code (reference for the record seam): `src/lib/checklists/`, `src/lib/server/checklists/`,
  `src/lib/components/jobs/{JobChecklistsCard,VisitRecordsDialog}.svelte`,
  `supabase/migrations/20260911100000_job_checklists_foundation.sql`.

Resume command: `read memory and continue the Jobs campaign`.
