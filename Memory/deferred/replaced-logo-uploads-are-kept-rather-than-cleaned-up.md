# Replaced logo uploads are kept rather than cleaned up

- **Priority:** P3


- **Campaign:** `contractor-settings` Part 1, decided by Jafar 2026-08-22.
- **Reason:** deleting a replaced object is only safe once documents reference frozen logos. Until then every
  existing and replaced object is retained. This is a holding position, not a permanent promise.
- **Reactivation trigger:** frozen document branding references exist.
- **Prerequisites:** retain every referenced object and delete only unreferenced uploads after a safe grace
  period.
- **Checkpoint:** `src/routes/api/settings/branding/logo/+server.ts`.

