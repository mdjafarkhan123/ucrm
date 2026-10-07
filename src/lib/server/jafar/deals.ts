import { json } from '@sveltejs/kit';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';

// Jafar business management B4: what every Deal command route does with the database's answer.

export const DEAL_NOT_FOUND = 'This Deal no longer exists.';

/**
 * The database's refusals (errcode 22023, e.g. "This business already has an open Deal.") are already in words
 * for Jafar; `false` or `null` means the Deal or business was removed meanwhile.
 */
export function dealCommandResponse(
	result: { data: unknown; error: { code?: string; message?: string } | null },
	what: string,
	missing: string = DEAL_NOT_FOUND
) {
	if (result.error) {
		if (result.error.code === '22023')
			return validationError({ form: result.error.message ?? 'That change is not allowed.' }, 409);
		if (result.error.code === '23505')
			return validationError({ form: 'This business already has an open Deal.' }, 409);
		console.error(`Could not ${what}.`, result.error);
		return databaseError();
	}
	if (result.data === false || result.data === null) return notFound(missing);
	return json({ result: result.data });
}
