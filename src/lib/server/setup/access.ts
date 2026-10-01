import { json, type RequestEvent } from '@sveltejs/kit';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

// Setup is the administrator's job: its answers include contact details the rest of the team has no reason
// to read, and what is entered here becomes the brief Uplift builds from.
export function requireSetupReader(event: RequestEvent) {
	return requireOrganizationAdmin(event, 'settings.business.view');
}

export function requireSetupEditor(event: RequestEvent) {
	return requireOrganizationAdmin(event, 'settings.business.edit');
}

// Autosave sends a request for every field somebody finishes, so the ceiling is well above the 20 a minute
// that an ordinary settings Save gets. It is still one shared counter per organization.
const SETUP_WRITE_LIMIT = { windowSeconds: 60, maxAttempts: 120 };

/** Null when the write may go ahead. */
export async function setupWriteLimited(
	event: RequestEvent,
	organizationId: string
): Promise<Response | null> {
	try {
		const limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `setup-write:${organizationId}`,
			...SETUP_WRITE_LIMIT
		});
		return limit.allowed ? null : rateLimitedResponse(limit.retryAfterSeconds);
	} catch {
		return databaseError();
	}
}

type DatabaseError = { code?: string; message?: string };

// The setup commands refuse in two ways, each already carrying the sentence a person should read.
export function setupWriteError(error: DatabaseError) {
	if (error.code === '42501')
		return json(
			{ error: 'Only an owner or administrator can change setup.', reason: 'permission_denied' },
			{ status: 403 }
		);
	if (error.code === '23514')
		return validationError({ form: error.message ?? 'That change is not allowed.' });
	return databaseError();
}
