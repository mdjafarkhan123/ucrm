import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { sendPreviewReadyEmails } from '$lib/server/setup/preview';
import { setupPreviewVersionSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E3 (plan §6): Jafar releases his draft, and the client's owners and administrators are
// emailed. The release stands even if the email cannot be queued, and the reply says so; pressing Release again
// records nothing twice and queues only an email that is missing.
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
	const parsed = setupPreviewVersionSchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'Choose a preview to release.' });

	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('owner_release_setup_preview', {
		target_organization_id: organizationId.data,
		target_version: parsed.data.version,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not release the preview.', error);
		return databaseError();
	}

	let emailed = true;
	try {
		await sendPreviewReadyEmails(client, {
			organizationId: organizationId.data,
			version: parsed.data.version,
			origin: env.APP_URL?.trim() || event.url.origin
		});
	} catch (error) {
		console.error('Could not queue the preview email.', error);
		emailed = false;
	}
	return json({ ...(data as object), emailed }, { headers: NO_STORE_HEADERS });
};
