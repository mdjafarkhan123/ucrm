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
	limitKeySchema,
	limitOverrideSchema,
	organizationIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const PUT: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedLimitKey = limitKeySchema.safeParse(event.params.limitKey);
	if (!parsedOrganizationId.success || !parsedLimitKey.success) {
		return json({ error: 'The organization or limit identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = limitOverrideSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the limit override.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const limitKey = parsedLimitKey.data;
		const { data: command, error } = await client.rpc('apply_organization_limit_exception', {
			target_organization_id: organizationId,
			target_limit_key: limitKey,
			target_limit_state: parsed.data.override_state,
			target_limit_value: (parsed.data.limit_value ?? null) as number,
			target_starts_at: parsed.data.starts_at,
			target_expires_at: (parsed.data.expires_at ?? null) as string,
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
		console.error('Could not change organization limit override.', error);
		return json({ error: 'Limit override could not be changed.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedLimitKey = limitKeySchema.safeParse(event.params.limitKey);
	if (!parsedOrganizationId.success || !parsedLimitKey.success) {
		return json({ error: 'The organization or limit identifier is invalid.' }, { status: 422 });
	}
	return json(
		{ error: 'Use an explicit inherit action so the reason is retained in history.' },
		{ status: 405 }
	);
};
