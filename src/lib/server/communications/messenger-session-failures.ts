import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import type { MessengerSessionFailure } from './messenger-connections';

// The same three plain answers wherever a Facebook login session is used.
const FAILURES: Record<MessengerSessionFailure, { status: number; error: string }> = {
	session_expired: {
		status: 409,
		error: 'Your Facebook login has expired. Log in with Facebook again.'
	},
	facebook_unavailable: {
		status: 503,
		error: 'Facebook could not be reached. Try again in a minute.'
	},
	facebook_refused: {
		status: 409,
		error: 'Facebook stopped sharing your Pages with us. Log in with Facebook again.'
	}
};

export function messengerSessionFailureResponse(reason: MessengerSessionFailure) {
	const failure = FAILURES[reason];
	return json(
		{ error: failure.error, reason },
		{ status: failure.status, headers: NO_STORE_HEADERS }
	);
}
