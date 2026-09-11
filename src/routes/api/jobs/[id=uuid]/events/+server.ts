import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';

type CombinedHistoryRow = {
	id: string;
	source: string;
	event_type: string;
	summary: string | null;
	actor_id: string | null;
	created_at: string;
	metadata: unknown;
	visit_id: string | null;
	visit_label: string | null;
};

// A job's own history, newest first, straight off the `job_events` spine the commands write. The rows are
// already fenced by their own RLS — a member without jobs.view sees none — and the actor's name is resolved
// separately through `profiles`, which teammate visibility lets one member read for another. A row whose
// actor is gone, or whose name is not visible to this reader, simply shows no name rather than an id.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const supabase = event.locals.supabase;
	const jobId = event.params.id;

	const eventRows = await supabase.rpc('job_combined_history', {
		target_job_id: jobId,
		result_limit: 100
	});

	if (eventRows.error) return databaseError();

	const rows = (eventRows.data ?? []) as CombinedHistoryRow[];
	const actorIds = [...new Set(rows.map((row) => row.actor_id).filter((id): id is string => !!id))];

	const names = new Map<string, string>();
	if (actorIds.length > 0) {
		const profiles = await supabase.from('profiles').select('id, full_name').in('id', actorIds);
		if (profiles.error) return databaseError();
		for (const profile of profiles.data ?? []) {
			if (profile.full_name) names.set(profile.id, profile.full_name);
		}
	}

	const events = rows.map((row) => ({
		id: row.id,
		source: row.source,
		event_type: row.event_type,
		summary: row.summary,
		actor_name: row.actor_id ? (names.get(row.actor_id) ?? null) : null,
		created_at: row.created_at,
		metadata: (row.metadata ?? {}) as Record<string, unknown>,
		visit_id: row.visit_id,
		visit_label: row.visit_label
	}));

	return json({ events }, { headers: PRIVATE_READ_HEADERS });
};
