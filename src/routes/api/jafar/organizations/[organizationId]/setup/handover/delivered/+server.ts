import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { sendDeliveredEmails } from '$lib/server/setup/training';

// Client onboarding E6 (plan §6): Jafar marks the project delivered once it is Live, training is booked or the owner
// skipped it, and the handover has his access summary and a guide; open outside waits never block. The client's
// owners and administrators are emailed a link to the handover pack.

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('owner_mark_setup_delivered', {
		target_organization_id: organizationId.data,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not mark the project delivered.', error);
		return databaseError();
	}
	const result = data as unknown as { status: string; live_at?: string };

	let emailed = true;
	if (result.status !== 'unchanged') {
		try {
			await sendDeliveredEmails(client, {
				organizationId: organizationId.data,
				origin: env.APP_URL?.trim() || event.url.origin
			});
		} catch (error) {
			console.error('Could not queue the delivered emails.', error);
			emailed = false;
		}
	}
	return json({ ...result, emailed }, { headers: NO_STORE_HEADERS });
};
