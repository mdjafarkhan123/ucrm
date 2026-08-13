import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { prospectIdSchema, prospectNotProceedingSchema } from '$lib/server/validation/prospect.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	let body: unknown = {};
	const rawBody = await event.request.text();
	if (rawBody.trim()) {
		try {
			body = JSON.parse(rawBody);
		} catch {
			return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
		}
	}

	const parsed = prospectNotProceedingSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	try {
		const client = getOwnerSupabaseClient();
		const { error: rpcError } = await client.rpc('mark_onboarding_application_not_proceeding', {
			target_application_id: parsedId.data,
			actor_email: session.email,
			reason: parsed.data.reason ?? undefined
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (rpcError.message.includes('private reason is required'))
				return json(
					{
						error: rpcError.message,
						field_errors: { reason: 'Enter a private reason to close this possible duplicate.' }
					},
					{ status: 422 }
				);
			if (rpcError.message.includes('unpaid application'))
				return json({ error: rpcError.message }, { status: 409 });
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not mark the prospect not proceeding.', error);
		return json({ error: 'The application could not be updated.' }, { status: 500 });
	}
};
