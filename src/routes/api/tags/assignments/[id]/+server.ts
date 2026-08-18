import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	requireLinkedEntityAccess,
	type LinkedEntityType
} from '$lib/server/access/collaboration';
import { databaseError } from '$lib/server/api/errors';

export const DELETE: RequestHandler = async (event) => {
	const { data: assignment, error: lookupError } = await event.locals.supabase
		.from('tag_assignments')
		.select('id, entity_type, entity_id')
		.eq('id', event.params.id)
		.maybeSingle();
	if (lookupError) return databaseError();
	if (!assignment) return json({ error: 'That tag assignment was not found.' }, { status: 404 });

	const entityType = assignment.entity_type as LinkedEntityType;
	const access = await requireLinkedEntityAccess(event, entityType, 'manage');
	if ('response' in access) return access.response;

	const { error } = await event.locals.supabase
		.from('tag_assignments')
		.delete()
		.eq('id', assignment.id);
	if (error) return databaseError();

	return json({ deleted: true });
};
