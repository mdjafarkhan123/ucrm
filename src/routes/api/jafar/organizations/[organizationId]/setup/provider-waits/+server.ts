import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { readOwnerProviderWaits, sendProviderWaitEmails } from '$lib/server/setup/provider-waits';
import { setupProviderWaitSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E2 (plan §5): Jafar's outside waits for one client — the ones the package offers and where
// each stands (GET), and moving one to a stage or clearing it (POST). "You need to do something" emails the
// client's owners and administrators; the change stands even if that email cannot be queued, and the reply says
// so, so Jafar can press Save again, which queues only what is missing.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	try {
		const result = await readOwnerProviderWaits(getOwnerSupabaseClient(), organizationId.data);
		return json(result, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read the outside waits.', error);
		return databaseError();
	}
};

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
	const parsed = setupProviderWaitSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[String(issue.path[0] ?? 'form')] ??= issue.message;
		return validationError(fieldErrors);
	}

	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('owner_set_setup_provider_wait', {
		target_organization_id: organizationId.data,
		target_wait_key: parsed.data.wait_key,
		// The database reads null as "clear it back to not started".
		new_status: parsed.data.status as string,
		new_note: parsed.data.note as string,
		actor_email: session.email
	});
	if (error) {
		// The package does not include the service, or a note is missing: the database's own sentence.
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not change an outside wait.', error);
		return databaseError();
	}

	// Asked again for the same "You need to do something", this re-queues only an email that is missing.
	let emailed = true;
	if (parsed.data.status === 'action_needed')
		try {
			await sendProviderWaitEmails(client, {
				organizationId: organizationId.data,
				waitKey: parsed.data.wait_key,
				origin: env.APP_URL?.trim() || event.url.origin
			});
		} catch (error) {
			console.error('Could not queue the email about an outside wait.', error);
			emailed = false;
		}

	return json({ ...(data as object), emailed }, { headers: NO_STORE_HEADERS });
};
