import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession, signOwnerStepUp, verifyOwnerCredentials } from '$lib/server/auth/owner';
import { ownerReconfirmSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

function unauthorized() {
	return json({ error: 'Platform owner authentication required.' }, { status: 401 });
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = ownerReconfirmSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		if (!verifyOwnerCredentials(session.email, parsed.data.password)) {
			return json({ error: 'The password is not correct.' }, { status: 401 });
		}

		signOwnerStepUp(event, session.email);
		return json({ ok: true });
	} catch (error) {
		console.error('Platform owner reconfirmation is unavailable.', error);
		return json({ error: 'Reconfirmation is not configured.' }, { status: 503 });
	}
};
