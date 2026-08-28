import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { retryReceiptCleanup } from '$lib/server/jafar/organization-closure-cron';
import {
	organizationCleanupRetrySchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

/**
 * Pushes the external (Auth + Brevo) cleanup for one stuck deletion receipt again, without waiting for
 * the nightly sweep. The organization was already purged under a step-up-confirmed action; this only
 * finishes that already-authorized deletion and is idempotent, so an owner session gates it -- no
 * fresh step-up. Failures stay durably tracked by the finish helpers (operation attempts + owner
 * alerts); this route just reports whether the receipt reached completed.
 */
export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = organizationCleanupRetrySchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Choose a valid deletion to retry.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const outcome = await retryReceiptCleanup(client, parsed.data.operation_id);
		if (!outcome.found) return json({ error: 'That deletion was not found.' }, { status: 404 });

		return json({ resolved: outcome.authOk && outcome.providerOk });
	} catch (error) {
		console.error('Could not retry the deletion cleanup.', error);
		return json({ error: 'The cleanup could not be retried.' }, { status: 500 });
	}
};
