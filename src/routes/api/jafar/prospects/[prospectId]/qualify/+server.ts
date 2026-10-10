import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Database } from '$lib/database.types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	prospectIdSchema,
	prospectQualificationSchema
} from '$lib/server/validation/prospect.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

type QualifyArgs =
	Database['public']['Functions']['record_onboarding_application_qualification']['Args'];

// Multi-industry foundation B3: Uplift confirms which Industry experience and Business type an Application
// is, or holds it while it checks something. Payment cannot be asked for or recorded, nor the account
// activated (B4), until it is confirmed.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
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

	const parsed = prospectQualificationSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	const decision = parsed.data;
	const supported = decision.outcome === 'supported';
	try {
		// The fields that do not belong to this outcome are sent as null; the generated types call them text.
		const { error: rpcError } = await getOwnerSupabaseClient().rpc(
			'record_onboarding_application_qualification',
			{
				target_application_id: parsedId.data,
				actor_email: session.email,
				target_outcome: decision.outcome,
				target_experience_key: supported ? decision.experience_key : null,
				target_business_type_key: supported ? decision.business_type_key : null,
				target_reviewed_work: supported ? decision.reviewed_work : null,
				target_buyer_message: supported ? null : decision.buyer_message,
				target_reason: decision.reason
			} as unknown as QualifyArgs
		);

		if (rpcError) {
			if (rpcError.message.includes('does not exist'))
				return json({ error: 'Prospect was not found.' }, { status: 404 });
			if (rpcError.message.includes('before the account is created'))
				return json({ error: rpcError.message }, { status: 409 });
			if (rpcError.message.includes('does not offer'))
				return json(
					{ error: rpcError.message, field_errors: { experience_key: rpcError.message } },
					{ status: 422 }
				);
			if (rpcError.message.includes('listed business types'))
				return json(
					{ error: rpcError.message, field_errors: { business_type_key: rpcError.message } },
					{ status: 422 }
				);
			throw rpcError;
		}

		return json({ ok: true });
	} catch (error) {
		console.error('Could not record the kind of business.', error);
		return json({ error: 'The decision could not be saved.' }, { status: 500 });
	}
};
