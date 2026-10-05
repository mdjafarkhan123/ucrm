import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { sendLaunchApprovedEmails } from '$lib/server/setup/launch-approval';
import { setupLaunchRecordSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E4 (plan §6): the approver said yes by phone or email, and Jafar records it on the open
// request with how it was given. The receipt goes to the approver and the client's owners and administrators.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupLaunchRecordSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ reason: parsed.error.issues[0]?.message ?? 'Check the reason.' });

	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('owner_record_setup_launch_approval', {
		target_organization_id: organizationId.data,
		target_version: parsed.data.version,
		reason: parsed.data.reason,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not record the launch approval.', error);
		return databaseError();
	}
	const result = data as unknown as { status: string; request_id: string };

	let emailed = true;
	if (result.status === 'approved') {
		try {
			await sendLaunchApprovedEmails(client, {
				organizationId: organizationId.data,
				requestId: result.request_id,
				origin: env.APP_URL?.trim() || event.url.origin
			});
		} catch (error) {
			console.error('Could not queue the launch approval receipt.', error);
			emailed = false;
		}
	}
	return json({ ...result, emailed }, { headers: NO_STORE_HEADERS });
};
