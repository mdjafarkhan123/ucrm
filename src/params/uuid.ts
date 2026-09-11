import type { ParamMatcher } from '@sveltejs/kit';

// Every id-shaped route segment below is a Postgres uuid primary key. A non-uuid value (a guessed,
// mistyped, or stale link) would otherwise reach a `.eq('id', ...)` filter and fail as a raw database
// error instead of a normal 404 -- this stops it at the router, before any query runs.
export const match: ParamMatcher = (param) =>
	/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(param);
