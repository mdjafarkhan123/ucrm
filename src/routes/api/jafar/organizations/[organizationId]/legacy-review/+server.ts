import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationLegacyReconciliationSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

function stepUpRequired() {
	return json(
		{
			error: 'Confirm your password before activating this organization.',
			step_up_required: true
		},
		{ status: 403 }
	);
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name, lifecycle_status')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		const { data: readiness, error: readinessError } = await client.rpc(
			'organization_legacy_readiness',
			{ target_organization_id: parsedId.data }
		);
		if (readinessError) throw readinessError;

		return json({ organization, readiness });
	} catch (error) {
		console.error('Could not load legacy organization readiness.', error);
		return json({ error: 'Legacy organization readiness could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = organizationLegacyReconciliationSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the reconciliation details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (parsed.data.status === 'active' && !consumeOwnerStepUp(event, session)) {
		return stepUpRequired();
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedId.data;
		const { data: command, error } = await client.rpc(
			'apply_organization_pending_setup_reconciliation',
			{
				target_organization_id: organizationId,
				target_status: parsed.data.status,
				target_suspension_category: (parsed.data.status === 'suspended'
					? parsed.data.suspension_category
					: null) as string,
				idempotency_key: parsed.data.idempotency_key,
				private_reason: parsed.data.reason,
				actor_owner_email: session.email
			}
		);
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
		console.error('Could not reconcile the legacy organization.', error);
		return json({ error: 'The legacy organization could not be reconciled.' }, { status: 500 });
	}
};
