import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	EmailSetupRequestError,
	closeEmailSetupRequest
} from '$lib/server/communications/email-setup-requests';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationFieldErrors,
	emailSetupCloseSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Jafar closes a contractor's ask with a note the contractor sees on their Email settings page.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const requestId = organizationIdSchema.safeParse(event.params.requestId);
	if (!requestId.success) {
		return json({ error: 'The request identifier is invalid.' }, { status: 422, headers: noStore });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = emailSetupCloseSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please write a note for the contractor.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	try {
		await closeEmailSetupRequest(getOwnerSupabaseClient(), requestId.data, parsed.data.note);
		return json({ ok: true }, { headers: noStore });
	} catch (error) {
		if (error instanceof EmailSetupRequestError) {
			return json({ error: error.message }, { status: error.status, headers: noStore });
		}
		console.error('Could not close the email setup request.', error);
		return json({ error: 'The request could not be closed.' }, { status: 500, headers: noStore });
	}
};
