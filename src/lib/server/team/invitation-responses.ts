import { json } from '@sveltejs/kit';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { TeamInvitationError } from './invitations';

const statusByCode = {
	seat_limit: 409,
	email_in_use: 409,
	invalid_adjustments: 422,
	invalid_or_expired: 404,
	acceptance_in_progress: 409,
	invitation_conflict: 409,
	service_unavailable: 503
} as const;

export function invitationErrorResponse(error: unknown) {
	if (error instanceof TeamInvitationError) {
		return json(
			{ error: error.message, code: error.code },
			{ status: statusByCode[error.code], headers: NO_STORE_HEADERS }
		);
	}

	return json(
		{ error: 'The invitation could not be processed right now. Try again.' },
		{ status: 500, headers: NO_STORE_HEADERS }
	);
}
