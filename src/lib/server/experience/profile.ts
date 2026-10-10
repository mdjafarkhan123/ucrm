import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { isKnownExperience, type ExperienceKey } from '$lib/experience/definitions';

/**
 * An Organization's experience profile (multi-industry foundation B1). Uplift records each decision in an
 * append-only chain; the head of the chain -- the decision no later one replaces -- is the current
 * profile. Anything else fails closed: no decision, a broken chain, or an experience this build does not
 * know all resolve to no experience, so nothing downstream can silently enable a different one.
 */

type Client = SupabaseClient<Database>;

export type ExperienceDecision = {
	id: string;
	experience_key: string;
	definition_version: number;
	business_type_key: string | null;
	service_shape: string;
	package_agreement_id: string | null;
	source: string;
	reason: string;
	actor_email: string;
	previous_decision_id: string | null;
	decided_at: string;
};

export type ExperienceProfile =
	| { state: 'missing'; experience: null; decision: null }
	| { state: 'unresolved'; experience: null; decision: null }
	| { state: 'unrecognized'; experience: null; decision: ExperienceDecision }
	| { state: 'confirmed'; experience: ExperienceKey; decision: ExperienceDecision };

/** Newest first, following the chain from its head. */
export function orderDecisionChain(decisions: ExperienceDecision[]) {
	const replaced = new Set(decisions.map((decision) => decision.previous_decision_id));
	const heads = decisions.filter((decision) => !replaced.has(decision.id));
	if (heads.length !== 1) return null;
	const byId = new Map(decisions.map((decision) => [decision.id, decision]));
	const chain: ExperienceDecision[] = [];
	for (let current: ExperienceDecision | undefined = heads[0]; current;) {
		chain.push(current);
		current = current.previous_decision_id ? byId.get(current.previous_decision_id) : undefined;
	}
	return chain.length === decisions.length ? chain : null;
}

export function resolveExperienceProfile(decisions: ExperienceDecision[]): ExperienceProfile {
	if (decisions.length === 0) return { state: 'missing', experience: null, decision: null };
	const chain = orderDecisionChain(decisions);
	if (!chain) return { state: 'unresolved', experience: null, decision: null };
	const head = chain[0];
	if (!isKnownExperience(head.experience_key, head.definition_version)) {
		return { state: 'unrecognized', experience: null, decision: head };
	}
	return { state: 'confirmed', experience: head.experience_key, decision: head };
}

export async function loadExperienceDecisions(client: Client, organizationId: string) {
	const { data, error } = await client
		.from('organization_experience_decisions')
		.select(
			'id, experience_key, definition_version, business_type_key, service_shape, package_agreement_id, source, reason, actor_email, previous_decision_id, decided_at'
		)
		.eq('organization_id', organizationId)
		.order('decided_at', { ascending: false });
	if (error) throw error;
	return data satisfies ExperienceDecision[];
}

export async function loadOrganizationExperienceProfile(client: Client, organizationId: string) {
	return resolveExperienceProfile(await loadExperienceDecisions(client, organizationId));
}
