import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	legacyPackageAssignmentSchema,
	organizationIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

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

	const parsed = legacyPackageAssignmentSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the legacy package assignment.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { error } = await client.rpc('record_legacy_organization_package', {
			target_organization_id: parsedOrganizationId.data,
			target_package_version_id: parsed.data.package_version_id,
			target_paid_through_date: parsed.data.paid_through_date,
			target_reason: parsed.data.reason
		});
		if (error) {
			const status =
				error.code === '23505' || error.code === '23514' || error.code === '23503' ? 409 : 500;
			return json({ error: error.message }, { status });
		}

		await recordOwnerAccessAudit(client, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type: 'package.legacy_assigned',
			target_type: 'organization.package_version',
			target_key: parsed.data.package_version_id,
			after_state: {
				package_version_id: parsed.data.package_version_id,
				paid_through_date: parsed.data.paid_through_date,
				reason: parsed.data.reason
			}
		});

		return json({ organization_id: parsedOrganizationId.data, assigned: true });
	} catch (error) {
		console.error('Could not assign a legacy organization package.', error);
		return json({ error: 'The legacy package could not be assigned.' }, { status: 500 });
	}
};
