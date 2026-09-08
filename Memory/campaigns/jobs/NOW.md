# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: **15d (15d-1 + 15d-2) complete and committed.** Part 15 continues with 15e, `Planned`, not yet
  scoped for implementation.

## Exact next action

Start Part 15e (the customer-safe Work Report). It depends on 15b–15d, all now complete.

1. Load `.claude/skills/jobber/SKILL.md` and re-read `docs/jobs-behavior-contract.md` for report/share
   language. Check `Design/Jobber Jobs/` for captured report screens; visit Jobber if missing.
2. Present the 15e plan (what staff select as customer-safe, preview/print/PDF, secure link, share
   history, the standard pattern and who builds it that way, risks, completion gate) to Jafar. Wait for
   approval before writing code.

## Pointers

- Roadmap/contract: `Memory/campaigns/jobs/ROADMAP.md`, `docs/jobs-behavior-contract.md`.
- 15d shipped code (reference for the signed-evidence seam): `src/lib/signatures/`,
  `src/lib/server/signatures/`, `src/lib/components/jobs/{CollectJobSignatureDialog,JobSignaturesCard}.svelte`,
  `src/lib/components/ui/SignaturePad.svelte`, `supabase/migrations/20260912100000_job_signatures_foundation.sql`.
- `npm run db:types` does not work — no Supabase access token; the script overwrites
  `src/lib/database.types.ts` with a JSON error. Hand-patch, or export `SUPABASE_ACCESS_TOKEN` first.
- The Svelte MCP autofixer does not run the SCSS preprocessor, so it reports every `&__` nesting and
  `//` comment as an error. `npm run check` is the real gate.
- Test data left on the dev project: 3 signatures on job #20 (whose title is now
  "Solar setup quote (revised scope) v2") and 1 on job #1. They cannot be deleted — the record is
  append-only by design.
- ~520px layout pass for 15d-2 was skipped on Jafar's call; not re-opened unless he raises it.

Resume command: `read memory and continue the Jobs campaign`.
