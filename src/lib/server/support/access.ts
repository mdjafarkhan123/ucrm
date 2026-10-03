import type { RequestEvent } from '@sveltejs/kit';
import type { OrganizationContext } from '$lib/server/auth/organization';
import { isContractorRole } from '$lib/server/access/contractor';
import { databaseError, unauthorized } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

// Every active team member may contact Uplift, whatever their role or the organization's package: support
// is a core service (plan §7), so there is no permission key and no feature gate to ask about. It stays
// open while the business is paused (D5c), which the usual organization context cannot see, so the
// database answers through public.support_member_context instead.
export async function requireSupportMember(
	event: RequestEvent
): Promise<{ auth: OrganizationContext } | { response: Response }> {
	const user = await event.locals.getUser();
	if (!user) return { response: unauthorized() };

	const { data, error } = await event.locals.supabase.rpc('support_member_context');
	if (error) return { response: databaseError() };
	const organization = data as OrganizationContext['organization'] | null;
	if (!organization || !isContractorRole(organization.role)) return { response: unauthorized() };

	return { auth: { user, organization } };
}

// A person typing to support sends a handful of messages a minute at most. Counted per person, so one
// chatty teammate never blocks another.
const SUPPORT_SEND_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

/** Null when the message may go ahead. */
export async function supportSendLimited(
	event: RequestEvent,
	userId: string
): Promise<Response | null> {
	try {
		const limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `support-send:${userId}`,
			...SUPPORT_SEND_LIMIT
		});
		return limit.allowed ? null : rateLimitedResponse(limit.retryAfterSeconds);
	} catch {
		return databaseError();
	}
}

// Picking files asks for one upload link each: a few per message, far fewer than this in ordinary use.
const SUPPORT_UPLOAD_LIMIT = { windowSeconds: 300, maxAttempts: 40 };

/** Null when the upload may go ahead. */
export async function supportUploadLimited(
	event: RequestEvent,
	userId: string
): Promise<Response | null> {
	try {
		const limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `support-upload:${userId}`,
			...SUPPORT_UPLOAD_LIMIT
		});
		return limit.allowed ? null : rateLimitedResponse(limit.retryAfterSeconds);
	} catch {
		return databaseError();
	}
}
