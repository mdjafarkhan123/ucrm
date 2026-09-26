import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { publicRequest } from '$lib/server/communications/email-setup-requests';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const noStore = { 'Cache-Control': 'no-store' };

// The contractor's open ask for this organization, or null. It is "open" for as long as Jafar has not closed it;
// once he sets the domain up, the Email card's own rows take over.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success) {
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_email_setup_requests_waiting')
		.select('*')
		.eq('organization_id', organizationId.data)
		.maybeSingle();
	if (error) {
		console.error('Could not load the email setup request for the owner.', error);
		return json(
			{ error: 'The setup request could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}

	return json({ request: data ? publicRequest(data as never) : null }, { headers: noStore });
};
