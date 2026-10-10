import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { readinessDecisionSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';
import { decisionFactsByArea, entriesFromChecks } from '$lib/server/experience/readiness';
import { loadOrganizationExperienceProfile } from '$lib/server/experience/profile';
import {
	describeReadiness,
	isReadinessAreaKey,
	readinessAreasFor,
	readinessRefusal
} from '$lib/experience/readiness';
import type { ReadinessHistoryEntry, ReadinessTabResponse } from '$lib/experience/types';

// Multi-industry foundation B8: Uplift's sign-off on each real-world area of one business, and every earlier
// decision. Anyone who may open Organizations can read it; recording a decision is the Platform Owner's
// (`OWNER_ONLY_CHANGES`). The business never reads the private reason or the reviewer from here.

async function loadReadinessTab(organizationId: string): Promise<ReadinessTabResponse> {
	const client = getOwnerSupabaseClient();
	const [decisions, profile] = await Promise.all([
		client
			.from('organization_readiness_decisions')
			.select(
				'id, area_key, status, source, checks, reason, business_message, actor_email, previous_decision_id, decided_at'
			)
			.eq('organization_id', organizationId)
			.order('decided_at', { ascending: false }),
		loadOrganizationExperienceProfile(client, organizationId)
	]);
	if (decisions.error) throw decisions.error;

	const entryOf = (row: (typeof decisions.data)[number]): ReadinessHistoryEntry => ({
		id: row.id,
		status: row.status as ReadinessHistoryEntry['status'],
		source: row.source === 'carried_over' ? 'carried_over' : 'review',
		checks: entriesFromChecks(row.checks),
		reason: row.reason,
		business_message: row.business_message,
		actor_email: row.actor_email,
		decided_at: row.decided_at
	});

	// The head of an area's chain is the decision no later decision replaces.
	const replaced = new Set(decisions.data.map((row) => row.previous_decision_id));
	const heads = decisions.data.filter((row) => !replaced.has(row.id));
	const experience = profile.experience;
	const views = describeReadiness(experience, decisionFactsByArea(heads));

	return {
		areas: readinessAreasFor(experience).map((area) => {
			const history = decisions.data.filter((row) => row.area_key === area.key).map(entryOf);
			const head = heads.find((row) => row.area_key === area.key);
			const view = views.find((candidate) => candidate.key === area.key)!;
			return {
				key: area.key,
				label: area.label,
				opens: area.opens,
				requires: area.requires,
				checks: area.checks,
				current: head ? entryOf(head) : null,
				business_view: {
					state: view.state,
					open: view.open,
					sentence: view.open ? 'Open for real customers.' : readinessRefusal(view)
				},
				history
			};
		})
	};
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		return json(await loadReadinessTab(parsedId.data), {
			headers: { 'cache-control': 'no-store' }
		});
	} catch (error) {
		console.error('Could not load operational readiness.', error);
		return json({ error: 'Readiness could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = readinessDecisionSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{ error: 'Please review the decision.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	const command = parsed.data;

	try {
		const client = getOwnerSupabaseClient();
		const profile = await loadOrganizationExperienceProfile(client, parsedId.data);
		const area = readinessAreasFor(profile.experience).find(
			(candidate) => candidate.key === command.area_key
		);
		if (!area || !isReadinessAreaKey(command.area_key))
			return json(
				{ error: 'That area is not part of this business’s experience.' },
				{ status: 422 }
			);

		// Every check of the area is answered exactly once, and no other check is accepted.
		const answered = new Map(command.checks.map((check) => [check.key, check]));
		const unknown = command.checks.find(
			(check) => !area.checks.some((known) => known.key === check.key)
		);
		if (unknown || answered.size !== command.checks.length || answered.size !== area.checks.length)
			return json(
				{
					error: 'Please review the decision.',
					field_errors: { checks: 'Answer every check in this area once.' }
				},
				{ status: 422 }
			);

		if (command.status === 'ready') {
			const current = await loadReadinessTab(parsedId.data);
			const blocked = area.requires
				.map((key) => current.areas.find((candidate) => candidate.key === key))
				.filter((required) => required && required.current?.status !== 'ready');
			if (blocked.length > 0)
				return json(
					{
						error: 'Please review the decision.',
						field_errors: {
							status: `Sign off ${blocked.map((required) => required!.label).join(' and ')} first.`
						}
					},
					{ status: 422 }
				);
		}

		const { data, error } = await client.rpc('record_organization_readiness_decision', {
			target_organization_id: parsedId.data,
			target_area_key: command.area_key,
			target_status: command.status,
			target_checks: command.checks,
			decision_reason: command.reason,
			// The command keeps a missing message as null; the generated type omits null.
			business_message: command.business_message as string,
			expected_previous_decision_id: command.expected_previous_decision_id as string,
			idempotency_key: command.idempotency_key,
			actor_email: session.email
		});
		if (error) {
			if (error.code === '23503' && error.message.startsWith('Organization was not found'))
				return json({ error: 'Organization was not found.' }, { status: 404 });
			if (['23503', '23505', '23514', 'P0409'].includes(error.code ?? ''))
				return json({ error: error.message }, { status: 409 });
			throw error;
		}

		return json(
			{ command: data, ...(await loadReadinessTab(parsedId.data)) },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not record the readiness decision.', error);
		return json({ error: 'The readiness decision could not be recorded.' }, { status: 500 });
	}
};
