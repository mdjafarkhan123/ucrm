import { env as publicEnv } from '$env/dynamic/public';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { resolvePublicForm } from '$lib/server/forms/public-resolver';
import { isBookingOutcome } from '$lib/forms/types';
import type { PageServerLoad } from './$types';

// Anonymous and unauthenticated by design -- this is the address a customer meets in the wild, so it never
// asks for a session and always answers the same generic "not available" shape rather than anything more
// precise (a wrong slug, a disabled form, and a suspended organization must all look identical from here).
export const load: PageServerLoad = async ({ params }) => {
	const client = getOwnerSupabaseClient();
	const resolved = await resolvePublicForm(client, params.orgSlug, params.formSlug);

	if (!resolved) return { available: false as const };

	return {
		available: true as const,
		organizationSlug: resolved.organizationSlug,
		outcome: resolved.outcome,
		isBooking: isBookingOutcome(resolved.outcome),
		title: resolved.title,
		description: resolved.description,
		content: resolved.content,
		services: resolved.services,
		turnstileSiteKey: publicEnv.PUBLIC_TURNSTILE_SITE_KEY ?? ''
	};
};
