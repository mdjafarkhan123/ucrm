import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireLinkedEntityAccess, parseLinkedEntityQuery } from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

export const GET: RequestHandler = async (event) => {
	const params = parseLinkedEntityQuery(event.url);
	if (!params) return validationError({ entity_type: 'Provide entity_type and entity_id.' });

	const access = await requireLinkedEntityAccess(event, params.entity_type, 'view');
	if ('response' in access) return access.response;

	const requestedLimit = Number(event.url.searchParams.get('limit') ?? DEFAULT_LIMIT);
	const limit = Number.isFinite(requestedLimit)
		? Math.min(Math.max(Math.trunc(requestedLimit), 1), MAX_LIMIT)
		: DEFAULT_LIMIT;

	const { data, error } = await event.locals.supabase
		.from('activity_events')
		.select('*')
		.eq('entity_type', params.entity_type)
		.eq('entity_id', params.entity_id)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error) return databaseError();

	return json({ activity_events: data ?? [] });
};
