import type { RequestHandler } from './$types';
import { databaseError, notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { photoResponse } from '$lib/server/profile/photo-routes';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { userIdParamSchema } from '$lib/server/validation/profile.schema';

// A contractor staff member's photo inside the Jafar Panel, on that client's Team tab. The panel's gate
// already requires Organizations to be open; this adds that the person really belongs to that client, so
// the address cannot be used to fetch any contractor's photo by guessing ids.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const userId = userIdParamSchema.safeParse(event.params.userId);
	if (!organizationId.success || !userId.success) return notFound('No photo.');

	const client = getOwnerSupabaseClient();
	const [membership, profile] = await Promise.all([
		client
			.from('organization_members')
			.select('user_id')
			.eq('organization_id', organizationId.data)
			.eq('user_id', userId.data)
			.maybeSingle(),
		client.from('profiles').select('avatar_object_key').eq('id', userId.data).maybeSingle()
	]);
	if (membership.error || profile.error) return databaseError();
	if (!membership.data || !profile.data?.avatar_object_key) return notFound('No photo.');

	return photoResponse(event.request, profile.data.avatar_object_key);
};
