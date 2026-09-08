# A full page load can crash hydration and leave the previous page on screen

- **Priority:** P2
- **Found:** Jobs 15g Round 1 browser pass, 2026-09-08 — incidental, not part of the checklist.
- **Symptom:** on a full load or reload (never on in-app navigation), the URL shows one route while the DOM
  still holds a different route's content — observed as the `/jafar` Control Room rendering at `/login` and
  Settings rendering at `/schedule`. Console: `Failed to hydrate: HierarchyRequestError: Failed to execute
  'appendChild' on 'Node'`, reported as originating in `PageHeader.svelte`. It self-corrects on the next
  navigation, but the tab was briefly unresponsive (screenshot capture timed out twice).
- **Already ruled out, so nobody repeats it:** `PageHeader.svelte` is a plain header with no DOM
  manipulation, no `{@html}` and no portal — it is where hydration *fails*, not the cause. No cross-user leak
  was shown: the session that saw Control Room at `/login` was the platform Admin, who may legitimately open
  that page. Whether a user without that access can be shown it is **unverified and is the thing to test
  first.**
- **Reactivation trigger:** any further report of the wrong page appearing, or before launch — an internal
  page rendering under a public URL is not acceptable in production even when it is only the viewer's own
  stale DOM.
- **Next step when picked up:** reproduce deliberately (repeated hard reloads across `/login`, `/schedule`,
  `/jafar`), then find the SSR/CSR mismatch in the `(app)` shell. The shell is SSR while page content is CSR,
  so the seam is the likely home.
