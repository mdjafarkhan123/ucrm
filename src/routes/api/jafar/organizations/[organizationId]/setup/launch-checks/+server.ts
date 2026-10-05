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
import { setupLaunchCheckSchema } from '$lib/server/validation/setup.schema';
import type { OwnerLaunchChecklist } from '$lib/setup/launch-checks';

// Client onboarding E5 (plan §6): Jafar's launch checklist for one client — the newest released preview's lines and
// where each stands, or null before any release (GET) — and ticking, marking Doesn't apply or clearing one line
// (POST). The database refuses a tick while a wait the line depends on is open, and any change once launch approval
// was asked for on that version.

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_setup_launch_checklist', {
		target_organization_id: organizationId.data
	});
	if (error) {
		console.error('Could not read the launch checks.', error);
		return databaseError();
	}
	return json(
		{ checklist: (data ?? null) as OwnerLaunchChecklist | null },
		{ headers: PRIVATE_READ_HEADERS }
	);
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
	const parsed = setupLaunchCheckSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[String(issue.path[0] ?? 'form')] ??= issue.message;
		return validationError(fieldErrors);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_set_setup_launch_check', {
		target_organization_id: organizationId.data,
		target_version: parsed.data.version,
		target_check_key: parsed.data.check_key,
		// The database reads null as "clear the line".
		new_outcome: parsed.data.outcome as string,
		new_reason: parsed.data.reason as string,
		actor_email: session.email
	});
	if (error) {
		// Waiting on a provider, already asked, not the newest version: the database's own sentence.
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not change a launch check.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
