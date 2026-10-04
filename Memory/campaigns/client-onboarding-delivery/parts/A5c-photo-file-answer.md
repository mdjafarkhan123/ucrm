# A5c — Photo or file answer

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** A client uploads a photo answer and Jafar can open it

## Steps

- [x] Migration `20261009100000_setup_file_answers` applied to dev (`supabase db push --linked`); link sync proven in SQL (rolled back)
- [x] Allowlist: MP3, M4A, WAV with byte signatures, accepted only by the setup upload route
- [x] `catalogue.ts` file kind (`$lib/setup/files.ts`); editor schema/model/UI (tick kinds, pick max files)
- [x] Routes: `POST`/`GET /api/setup/files`, `GET /api/setup/files/[id]`, owner
      `GET /api/jafar/organizations/[organizationId]/setup/files/[fileId]`; answers save refuses unusable files
- [x] Wizard field `SetupFilesField.svelte`; svelte-check 0 errors; setup/file unit tests pass; committed
- [ ] Unit tests for new code: `parseSetupFileIds`, `setupFileType`, audio `detectSignature`, editor schema file rules
- [ ] Browser check (see Next), then close the part

## Next

Write the missing unit tests (step 6). Then browser-check: on `/jafar/setup` start a draft, Edit questions, add
a "Photo or file" question (tick Photos, up to 5), save — then DISCARD the draft (never publish test questions).
The client side cannot be seen without publishing, so its live look joins A5's hands-on publish: Jafar adds a real
photo question, a client uploads a photo, "Checking for viruses…" turns ready within about a minute (worker cron),
and Jafar opens it at the owner route. Then mark A5c done, add the deferred note "microphone recording across the
whole app" (Jafar 2026-10-04), and continue with A5e.

## Notes

- Jafar 2026-10-04: max files and accepted kinds are chosen per question (Google Forms pattern). Recordings are
  uploads only, accepted only in setup answers; microphone recording is a separate future project.
- SVG refused: several CRM routes show any `image/*` straight on the page. Clients send PDF or PNG logos.
- Run svelte-check with `NODE_OPTIONS=--max-old-space-size=8192`, or it runs out of memory.
