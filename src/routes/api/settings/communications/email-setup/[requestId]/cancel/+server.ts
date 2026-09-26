import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import {
	EmailSetupRequestError,
	cancelEmailSetupRequest,
	loadEmailSetup
} from '$lib/server/communications/email-setup-requests';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Withdraw an ask, only while it still waits on Jafar. Once Jafar has started, the database refuses (409).
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const requestId = organizationIdSchema.safeParse(event.params.requestId);
	if (!requestId.success) {
		return json({ error: 'The request identifier is invalid.' }, { status: 422, headers: noStore });
	}

	const client = getOwnerSupabaseClient();
	try {
		await cancelEmailSetupRequest(client, check.auth.organization.id, requestId.data);
		return json(await loadEmailSetup(client, check.auth.organization.id), { headers: noStore });
	} catch (error) {
		if (error instanceof EmailSetupRequestError) {
			return json({ error: error.message }, { status: error.status, headers: noStore });
		}
		console.error('Could not cancel the email setup request.', error);
		return json(
			{ error: 'The request could not be cancelled.' },
			{ status: 500, headers: noStore }
		);
	}
};
