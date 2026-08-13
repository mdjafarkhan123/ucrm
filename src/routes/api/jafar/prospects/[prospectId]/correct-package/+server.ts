import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	prospectIdSchema,
	prospectPackageCorrectionSchema
} from '$lib/server/validation/prospect.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = prospectPackageCorrectionSchema.safeParse(body);
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
		const { error: rpcError } = await client.rpc('correct_onboarding_application_package', {
			target_application_id: parsedId.data,
			actor_email: session.email,
			new_package_version_id: parsed.data.package_version_id,
			correction_reason: parsed.data.reason
		});

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (
				rpcError.message.includes('can no longer be corrected') ||
				rpcError.message.includes('after payment is confirmed')
			)
				return json({ error: rpcError.message }, { status: 409 });
			if (
				rpcError.message.includes('not available') ||
				rpcError.message.includes('no longer exists') ||
				rpcError.message.includes('Choose a different package')
			)
				return json(
					{
						error: rpcError.message,
						field_errors: { package_version_id: rpcError.message }
					},
					{ status: 422 }
				);
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not change the prospect package.', error);
		return json({ error: 'The package could not be changed.' }, { status: 500 });
	}
};
