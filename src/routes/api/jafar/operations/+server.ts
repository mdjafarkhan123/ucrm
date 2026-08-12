import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { operationListQuerySchema } from '$lib/server/validation/operation.schema';

const summarySelect =
	'id, correlation_id, operation_type, target_kind, target_id, status, attempt_count, last_error, acknowledged_at, acknowledged_by_owner_email, resolved_at, resolved_by_owner_email, resolution_note, created_at, updated_at';

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();

	const parsed = operationListQuerySchema.safeParse({
		status: event.url.searchParams.get('status') ?? undefined,
		target_id: event.url.searchParams.get('target_id') ?? undefined
	});
	if (!parsed.success)
		return json({ error: 'The operations filter is invalid.' }, { status: 422 });

	try {
		let query = getOwnerSupabaseClient()
			.from('platform_operation_attempts')
			.select(summarySelect)
			.order('updated_at', { ascending: false })
			.limit(100);

		query = parsed.data.status
			? query.eq('status', parsed.data.status)
			: query.neq('status', 'succeeded');
		if (parsed.data.target_id) query = query.eq('target_id', parsed.data.target_id);

		const { data, error } = await query;
		if (error) throw error;
		return json({ operations: data ?? [] });
	} catch (error) {
		console.error('Could not load operations.', error);
		return json({ error: 'Operations could not be loaded.' }, { status: 500 });
	}
};
