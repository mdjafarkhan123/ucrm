import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { prospectIdSchema } from '$lib/server/validation/prospect.schema';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const { error: rpcError } = await client.rpc('acknowledge_onboarding_application_duplicate', {
			target_application_id: parsedId.data,
			actor_email: session.email
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (
				rpcError.message.includes('not flagged as a possible duplicate') ||
				rpcError.message.includes('already acknowledged') ||
				rpcError.message.includes('unpaid application can have its duplicate flag')
			)
				return json({ error: rpcError.message }, { status: 409 });
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not acknowledge the prospect duplicate flag.', error);
		return json({ error: 'The application could not be updated.' }, { status: 500 });
	}
};
