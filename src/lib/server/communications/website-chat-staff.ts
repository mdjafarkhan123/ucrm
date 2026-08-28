import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';

export const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The three WC4.5 staff commands raise exactly four kinds of refusal, and every one of them is
// something the person on the screen can act on rather than a fault to hide behind a 500:
//
//   42501 insufficient_privilege            they lack the permission the command re-checked
//   23503 foreign_key_violation             the session or the chosen client is not available
//   55000 object_not_in_prerequisite_state  already ended, or no longer needs review
//   22023 invalid_parameter_value           an empty message body
//
// The command's own message is already written for a contractor, so it is forwarded verbatim -- the
// same contract the guarded-email review route already follows.
const ACTIONABLE_CODES = new Set(['42501', '23503', '55000', '22023']);

export function websiteChatCommandError(error: unknown) {
	const dbError = error as { code?: string; message?: string };
	if (!ACTIONABLE_CODES.has(dbError.code ?? '')) return null;
	return json({ error: dbError.message }, { status: 422, headers: NO_STORE_HEADERS });
}
