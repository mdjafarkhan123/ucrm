# Offline field records on site

Jobs 15f, deferred by Jafar 2026-09-08 after scoping. Field screens are online-only: a worker in a basement
or dead zone cannot tick a checklist, write a note, add a photo, or complete a visit, and a reload shows
nothing because the app itself is fetched every time.

**Reactivation trigger:** a real contractor reports workers losing signal on site, or offline becomes a
sales blocker against Jobber.

**Already known, so future work does not re-derive it:**

- Three layers, in order: app shell cached on the device; the current visit's data cached; writes held on the
  device and replayed. A queue alone is useless without the first layer.
- Stack-native path, no custom system: SvelteKit's built-in `src/service-worker.ts` for the shell; the
  TanStack Query persistence plugin into IndexedDB for reads; TanStack's own paused-mutation queue with
  `setMutationDefaults` + `resumePausedMutations` for writes. Photos held as Blobs in IndexedDB, presigned and
  uploaded to R2 only after reconnect.
- Prerequisite: notes, checklist answers and attachments have no idempotency key (visit commands do), so a
  retry could double-write. Small endpoint change, not a rebuild.
- Auth tokens cannot refresh offline, so offline is hours, not days; iOS can evict a web app's stored data.
- Jobber's web app has no offline at all; their native app does a bounded version (schedule, notes, photos).
  A bounded scope — the one visit a worker is standing at — is the approved shape if this reactivates.
