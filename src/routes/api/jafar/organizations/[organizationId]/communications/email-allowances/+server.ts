import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

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

	try {
		const { data: allowances, error } = await getOwnerSupabaseClient().rpc(
			'get_organization_communication_email_allowances',
			{ target_organization_id: parsedOrganizationId.data }
		);
		if (error) throw error;
		return json({ allowances }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load organization email allowances.', error);
		return json({ error: 'Email allowances could not be loaded.' }, { status: 500 });
	}
};
