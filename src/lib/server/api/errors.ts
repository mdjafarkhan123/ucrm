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
