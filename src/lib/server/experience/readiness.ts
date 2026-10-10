import { json } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	describeReadiness,
	isReadinessAreaKey,
	readinessRefusal,
	type ReadinessAreaKey,
	type ReadinessAreaView,
	type ReadinessCheckEntry,
	type ReadinessCheckState,
	type ReadinessDecisionFacts,
	type ReadinessStatus
} from '$lib/experience/readiness';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';

/**
 * Operational readiness for the app's server (multi-industry foundation B8). The Business Workspace reads the
 * current answer per area through `organization_readiness_for_member`, which hides Uplift's private reason
 * and reviewer. A real-world action asks `refuseIfAreaClosed` first; a refusal names the remaining tasks and
 * who owns them. Anything unreadable fails closed.
 */

type Client = SupabaseClient<Database>;

const STATES = new Set<string>(['open', 'done', 'not_applicable']);
const STATUSES = new Set<string>(['ready', 'not_ready', 'held']);

export function entriesFromChecks(value: unknown): ReadinessCheckEntry[] {
	if (!Array.isArray(value)) return [];
	return value.flatMap((item) => {
		if (!item || typeof item !== 'object') return [];
		const { key, state, note } = item as { key?: unknown; state?: unknown; note?: unknown };
		if (typeof key !== 'string' || typeof state !== 'string' || !STATES.has(state)) return [];
		return [
			{
				key,
				state: state as ReadinessCheckState,
				...(typeof note === 'string' && note ? { note } : {})
			}
		];
	});
}

type DecisionRow = {
	area_key: string;
	status: string;
	source: string;
	checks: unknown;
	business_message: string | null;
};

/** The current decision per area from rows already read; an unknown status or area is dropped. */
export function decisionFactsByArea(rows: DecisionRow[]) {
	const facts: Partial<Record<ReadinessAreaKey, ReadinessDecisionFacts>> = {};
	for (const row of rows) {
		if (!isReadinessAreaKey(row.area_key) || !STATUSES.has(row.status)) continue;
		facts[row.area_key] = {
			status: row.status as ReadinessStatus,
			source: row.source === 'carried_over' ? 'carried_over' : 'review',
			checks: entriesFromChecks(row.checks),
			business_message: row.business_message
		};
	}
	return facts;
}

/** What a Team member sees: each area's answer, read with their own session. */
export async function loadMemberReadiness(
	client: Client,
	organizationId: string,
	experience?: string | null
): Promise<ReadinessAreaView[]> {
	const { data, error } = await client.rpc('organization_readiness_for_member', {
		target_organization_id: organizationId
	});
	if (error) throw error;
	return describeReadiness(experience, decisionFactsByArea(data ?? []));
}

/**
 * Null when the area is open for this business. Otherwise the 403 a route returns: the sentence to show, plus
 * the area and its tasks for a screen that wants more than the sentence. When readiness cannot be read the
 * action is refused, never allowed.
 */
export async function refuseIfAreaClosed(
	client: Client,
	organizationId: string,
	area: ReadinessAreaKey
): Promise<Response | null> {
	let views: ReadinessAreaView[];
	try {
		views = await loadMemberReadiness(client, organizationId);
	} catch (error) {
		console.error('Could not read operational readiness.', error);
		return json(
			{ error: 'Uplift could not check whether this is switched on yet. Try again in a moment.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}
	const view = views.find((candidate) => candidate.key === area);
	if (view?.open) return null;
	return json(
		{
			error: view ? readinessRefusal(view) : 'This is not switched on for your business yet.',
			reason: 'not_ready',
			area,
			tasks: view?.tasks ?? []
		},
		{ status: 403, headers: NO_STORE_HEADERS }
	);
}
