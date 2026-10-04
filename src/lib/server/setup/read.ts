import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	sectionFacts,
	sectionStatus,
	setupAnswerGiven,
	shownCatalogueFacts,
	type SetupAnswer,
	type SetupAnswers,
	type SetupAvailability,
	type SetupCatalogue
} from '$lib/setup/catalogue';
import { SETUP_CHECK_KEY, SETUP_CHECK_TITLE } from '$lib/setup/check';

/** B13: the newest Send to Uplift, without its answers. */
export type SetupSent = { number: number; submitted_at: string; submitted_by_name: string };

export type SetupState = {
	welcomeSeen: boolean;
	answers: SetupAnswers;
	doneSections: Set<string>;
	sent: SetupSent | null;
};

/** A stored answer as the page works with it: hours, lists and the like are JSON, read as text. */
export function setupAnswerFromRow(row: {
	availability: string;
	value: unknown;
	note: string | null;
}): SetupAnswer {
	return {
		availability: row.availability as SetupAvailability,
		value:
			typeof row.value === 'string'
				? row.value
				: row.value == null
					? null
					: JSON.stringify(row.value),
		note: row.note
	};
}

// Everything the wizard has saved for one organization: at most one row per fact and per section, and the
// newest send, so four small reads keyed by the organization.
export async function readSetupState(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<SetupState | null> {
	const [setupResult, answersResult, sectionsResult, sentResult] = await Promise.all([
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
			.eq('organization_id', organizationId),
		supabase
			.from('organization_setup_submissions')
			.select('submission_number, submitted_at, submitted_by_name')
			.eq('organization_id', organizationId)
			.order('submission_number', { ascending: false })
			.limit(1)
			.maybeSingle()
	]);
	if (setupResult.error || answersResult.error || sectionsResult.error || sentResult.error)
		return null;

	const answers: SetupAnswers = {};
	// An answer to a question since removed stays stored, but nothing reads it: every reader looks answers up by
	// the published version's own facts.
	for (const row of answersResult.data) answers[row.fact_key] = setupAnswerFromRow(row);

	return {
		welcomeSeen: setupResult.data?.welcome_seen_at != null,
		answers,
		doneSections: new Set(sectionsResult.data.map((row) => row.section_key)),
		sent: sentResult.data
			? {
					number: sentResult.data.submission_number,
					submitted_at: sentResult.data.submitted_at,
					submitted_by_name: sentResult.data.submitted_by_name
				}
			: null
	};
}

export function setupSummary(state: SetupState, catalogue: SetupCatalogue) {
	// Only the questions this client is asked now count; one an earlier answer hides is neither total nor answered.
	const shown = shownCatalogueFacts(catalogue, state.answers);
	const sections = catalogue.sections.map((section) => {
		const facts = sectionFacts(section).filter((fact) => shown.has(fact.key));
		return {
			key: section.key,
			title: section.title,
			description: section.description,
			status: sectionStatus(section, state.answers, state.doneSections.has(section.key), shown),
			answered: facts.filter((fact) => setupAnswerGiven(fact, state.answers)).length,
			total: facts.length
		};
	});
	const done = sections.filter((section) => section.status === 'done').length;
	const unfinished = sections.find((section) => section.status !== 'done');
	// B13: with every task done, Check and send is next until setup has been sent.
	const next = unfinished
		? { key: unfinished.key, title: unfinished.title, status: unfinished.status }
		: state.sent
			? null
			: { key: SETUP_CHECK_KEY, title: SETUP_CHECK_TITLE, status: 'not_started' as const };

	return {
		welcome_seen: state.welcomeSeen,
		sections,
		progress: { done, total: sections.length },
		// The next useful thing to do. Null once setup has been sent and every task is still done.
		next,
		// Uplift's review and the delivery stages arrive with later parts.
		delivery: state.sent
			? { state: 'sent' as const, ...state.sent }
			: { state: 'collecting' as const }
	};
}
