import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationClosureRestoreSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

function stepUpRequired() {
	return json(
		{
			error: 'Confirm your password before restoring this organization.',
			step_up_required: true
		},
		{ status: 403 }
	);
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = organizationClosureRestoreSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the restoration details.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) return stepUpRequired();

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;

		const { data: command, error } = await client.rpc('apply_organization_closure_restore', {
			target_organization_id: organizationId,
			idempotency_key: parsed.data.idempotency_key,
			restoration_evidence_note: parsed.data.restoration_evidence_note,
			actor_owner_email: session.email
		});
		if (error) {
			if (['23503', '23505', '23514', '40001'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name, lifecycle_status')
			.eq('id', organizationId)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		return json({ command, organization });
	} catch (error) {
		console.error('Could not restore the organization.', error);
		return json({ error: 'Organization could not be restored.' }, { status: 500 });
	}
};
