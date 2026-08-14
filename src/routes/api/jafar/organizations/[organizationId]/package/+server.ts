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
	organizationIdSchema,
	packageChangeSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const PATCH: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
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

	const parsed = packageChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the package change.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const { data: command, error } = await client.rpc('apply_organization_package_change', {
			target_organization_id: organizationId,
			target_package_version_id: parsed.data.package_version_id,
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
		console.error('Could not change organization package.', error);
		return json({ error: 'Organization package could not be changed.' }, { status: 500 });
	}
};
