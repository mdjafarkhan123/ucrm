import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';
import {
	communicationEmailReputationResumeSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

// Only Jafar resumes an automatic reputation pause, and only knowingly: while the organization is
// still at or beyond a pause threshold the command refuses unless remediation review is confirmed.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{
				error: 'The organization identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedOrganizationId.error)
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationEmailReputationResumeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the resume details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client.rpc('resume_communication_email_reputation_pause', {
			p_organization_id: parsedOrganizationId.data,
			p_reason: parsed.data.reason,
			p_actor_email: session.email,
			p_confirm_remediation: parsed.data.confirm_remediation
		});
		if (error) {
			if (error.code === '23503') {
				return json({ error: 'That organization was not found.' }, { status: 404 });
			}
			if (['23505', '23514'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		const { data: reputation, error: reputationError } = await client.rpc(
			'get_communication_email_reputation',
			{ p_organization_id: parsedOrganizationId.data }
		);
		if (reputationError) throw reputationError;

		return json({ result: data, reputation }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not resume the automatic reputation pause.', error);
		return json({ error: 'The automatic pause could not be resumed.' }, { status: 500 });
	}
};
