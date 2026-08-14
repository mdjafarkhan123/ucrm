import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import {
	OrganizationAccessNotFoundError,
	resolveOrganizationAccess
} from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationLifecycleSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

function stepUpRequired() {
	return json(
		{
			error: 'Confirm your password before changing organization status.',
			step_up_required: true
		},
		{ status: 403 }
	);
}

export const PATCH: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
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

	const parsed = organizationLifecycleSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the requested status.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) return stepUpRequired();

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const { data: command, error } = await client.rpc('apply_organization_lifecycle_change', {
			target_organization_id: organizationId,
			target_status: parsed.data.status,
			target_suspension_category: (parsed.data.status === 'suspended'
				? parsed.data.suspension_category
				: null) as string,
			idempotency_key: parsed.data.idempotency_key,
			private_reason: parsed.data.reason,
			actor_owner_email: session.email
		});
		if (error) {
			if (['23503', '23505', '23514', '40001'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		return json({
			command,
			access: await resolveOrganizationAccess(client, organizationId)
		});
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError) {
			return json({ error: error.message }, { status: 404 });
		}
		console.error('Could not change organization lifecycle status.', error);
		return json({ error: 'Organization status could not be changed.' }, { status: 500 });
	}
};
