import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	OrganizationAccessNotFoundError,
	resolveOrganizationAccess
} from '$lib/server/access/effective';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	featureOverrideSchema,
	organizationIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

const featureKeyPattern = /^[a-z][a-z0-9_.-]{1,79}$/;

export const PUT: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const featureKey = event.params.featureKey;
	if (!parsedOrganizationId.success || !featureKeyPattern.test(featureKey)) {
		return json({ error: 'The organization or feature identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = featureOverrideSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the feature override.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const { data: command, error } = await client.rpc('apply_organization_feature_exception', {
			target_organization_id: organizationId,
			target_feature_key: featureKey,
			target_override_state: parsed.data.override_state,
			target_starts_at: parsed.data.starts_at,
			target_expires_at: (parsed.data.expires_at ?? null) as string,
			idempotency_key: parsed.data.idempotency_key,
			private_reason: parsed.data.reason,
			actor_owner_email: session.email
		});
		if (error) {
			if (['23503', '23505', '23514', 'P0409'].includes(error.code ?? '')) {
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
		console.error('Could not change organization feature override.', error);
		return json({ error: 'Feature override could not be changed.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();
	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success || !featureKeyPattern.test(event.params.featureKey)) {
		return json({ error: 'The organization or feature identifier is invalid.' }, { status: 422 });
	}
	return json(
		{ error: 'Use an explicit inherit action so the reason is retained in history.' },
		{ status: 405 }
	);
};
