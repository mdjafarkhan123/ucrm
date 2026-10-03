# A5c — Photo or file answer

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** A client uploads a photo answer and Jafar can open it

## Steps

- [ ] Migration: kind `file` with `file_kinds` (photo/document/audio) and `max_files` (1, 5, 10, 20) on setup
      items, carried by the three functions A5d touched; files/file_links role `setup_answer`; a link exists only
      while an answer holds the file (finalize + answer save), like catalog item photos; `file_usage` says "Business setup"
- [ ] Allowlist: MP3, M4A, WAV with byte signatures, accepted only by the setup upload route
- [ ] `catalogue.ts` file kind + value rules; editor schema/model/UI (tick kinds, pick max files)
- [ ] `POST /api/setup/files` (setup editor, fact must be a file question, kind allowed); answers save refuses a
      file not this organization's setup upload, or failed/trashed; section read returns the files' names/states/thumbs
- [ ] Wizard field (upload, progress, checking, remove, refresh while checking)
- [ ] Owner route to open a client's setup file (C2 will show it on the client page)
- [ ] Unit tests, svelte-check, browser check, commit

## Next

Start the migration (step 1).

## Notes

- Jafar 2026-10-04: max files and accepted kinds are chosen per question (Google Forms pattern). Recordings are
  uploads only, accepted only in setup answers; recording with the microphone across the whole app is a separate
  future project (deferred note to add when this part closes).
- SVG refused: several CRM routes show any `image/*` straight on the page. Clients send PDF or PNG logos.
