# ADR 0007: Every Jafar Panel request passes one front-door gate

## Status

Accepted 2026-10-07, with Jafar business management part A1. Follows § Team access across `/jafar` of the
[Jafar business management plan](../jafar-business-management-behavior-contract.md).

## Context

The Jafar Panel is about to gain teammates with limited access (stage D). Until now each of its ~190 API
handlers checked the owner session itself, and its pages relied on the `(protected)` layout's server load.
A handler that forgot its check would be open. A page's own server load is not protected by its layout:
SvelteKit runs them in parallel and, on client navigation, may run the page's load without re-running the
layout's (the package preview page was exposed this way).

## Decision

1. **One gate in `src/hooks.server.ts`.** `guardJafarRequest` (`src/lib/server/auth/platform-access.ts`)
   runs for every `/jafar` page and `/api/jafar` request before route code. Without a valid session it
   answers 401 for the API and redirects pages to `/jafar/login`. Deny by default: a new route is closed
   until someone deliberately lists it as open.
2. **Only sign-in and secret-checked jobs are open.** `/jafar/login`, `/api/jafar/session`, and
   `/api/jafar/internal/*` (database-triggered jobs that check their own bearer secret).
3. **One registry lookup per request.** `getOwnerSession` keeps its result in `locals.ownerSession`, so the
   gate and the route's own check share one answer. Route-level checks stay as a second line of defence.
4. **Stage D extends the gate, not the routes.** Teammate identity and area permissions are added behind
   this gate and `getOwnerSession`'s successor, never as a second, parallel check.

`src/hooks.server.spec.ts` reads the route folders from disk and proves every guarded page and API refuses
logged-out, forged, unknown, and signed-out sessions, and that the open list is exactly the one above.

## Rejected

- **Layout server loads alone** — they do not protect `+server.ts` endpoints or a page's own load.
- **Renaming every route's check now** — churn across about 230 files with no behavior change; the actor's shape
  changes in stage D anyway.
