import { json } from '@sveltejs/kit';

export function validationError(fieldErrors: Record<string, string>, status = 422) {
	return json(
		{ error: 'Please review the highlighted fields.', field_errors: fieldErrors },
		{ status }
	);
}

export function databaseError() {
	return json({ error: 'We could not save that record. Please try again.' }, { status: 500 });
}

export function unauthorized() {
	return json({ error: 'Authentication or organization membership required.' }, { status: 401 });
}

export function notFound(message: string) {
	return json({ error: message }, { status: 404 });
}

// Read responses are per-tenant, so they must never land in a shared cache. TanStack Query owns how long
// the browser keeps them; the header only says who may store them.
export const PRIVATE_READ_HEADERS = { 'cache-control': 'private, no-cache' };
export const NO_STORE_HEADERS = { 'cache-control': 'no-store' };
