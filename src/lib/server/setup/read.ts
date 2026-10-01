import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	SETUP_FACTS,
	SETUP_SECTIONS,
	sectionFacts,
	sectionStatus,
	type SetupAnswers,
	type SetupAvailability
} from '$lib/setup/catalogue';

export type SetupState = {
	welcomeSeen: boolean;
	answers: SetupAnswers;
	doneSections: Set<string>;
};

// Everything the wizard has saved for one organization: at most one row per fact and per section, so
// three small reads keyed by the organization.
export async function readSetupState(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<SetupState | null> {
	const [setupResult, answersResult, sectionsResult] = await Promise.all([
		supabase
			.from('organization_setup')
			.select('welcome_seen_at')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		supabase
			.from('organization_setup_answers')
			.select('fact_key, availability, value, note')
			.eq('organization_id', organizationId),
		supabase
			.from('organization_setup_sections')
			.select('section_key')
			.eq('organization_id', organizationId)
	]);
	if (setupResult.error || answersResult.error || sectionsResult.error) return null;

	const answers: SetupAnswers = {};
	for (const row of answersResult.data) {
		// A fact dropped from the catalogue keeps its row but is no longer part of setup.
		if (!SETUP_FACTS.has(row.fact_key)) continue;
		answers[row.fact_key] = {
			availability: row.availability as SetupAvailability,
			value: typeof row.value === 'string' ? row.value : null,
			note: row.note
		};
	}

	return {
		welcomeSeen: setupResult.data?.welcome_seen_at != null,
		answers,
		doneSections: new Set(sectionsResult.data.map((row) => row.section_key))
	};
}

export function setupSummary(state: SetupState) {
	const sections = SETUP_SECTIONS.map((section) => {
		const facts = sectionFacts(section);
		return {
			key: section.key,
			title: section.title,
			description: section.description,
			status: sectionStatus(section, state.answers, state.doneSections.has(section.key)),
			answered: facts.filter((fact) => state.answers[fact.key]).length,
			total: facts.length
		};
	});
	const done = sections.filter((section) => section.status === 'done').length;
	const next = sections.find((section) => section.status !== 'done') ?? null;

	return {
		welcome_seen: state.welcomeSeen,
		sections,
		progress: { done, total: sections.length },
		// The next useful thing to do. Null once every task is done.
		next: next ? { key: next.key, title: next.title, status: next.status } : null,
		// Sending to Uplift and the delivery stages arrive with later parts; until then this is the one
		// honest state setup can be in.
		delivery: { state: 'collecting' as const }
	};
}
