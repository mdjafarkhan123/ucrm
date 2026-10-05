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
import type { SetupClientReview } from '$lib/setup/review';

/** B13: the newest Send to Uplift, without its answers. */
export type SetupSent = { number: number; submitted_at: string; submitted_by_name: string };

/** C4: Ready for Uplift as the client sees it — the build's start and target range, `YYYY-MM-DD`. */
export type SetupReadyDates = { start_date: string; target_from: string; target_to: string };

export type SetupState = {
	welcomeSeen: boolean;
	answers: SetupAnswers;
	doneSections: Set<string>;
	sent: SetupSent | null;
	ready: SetupReadyDates | null;
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
// newest send and Ready for Uplift, so five small reads keyed by the organization.
export async function readSetupState(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<SetupState | null> {
	const [setupResult, answersResult, sectionsResult, sentResult, readyResult] = await Promise.all([
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
			.maybeSingle(),
		supabase
			.from('organization_setup_ready')
			.select('start_date, target_from, target_to')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);
	if (
		setupResult.error ||
		answersResult.error ||
		sectionsResult.error ||
		sentResult.error ||
		readyResult.error
	)
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
			: null,
		ready: readyResult.data ?? null
	};
}

/**
 * The task list's figures. `reviews` is Uplift's review of each sent section
 * (`$lib/server/setup/client-review`); empty before the first send.
 */
export function setupSummary(
	state: SetupState,
	catalogue: SetupCatalogue,
	reviews: Record<string, SetupClientReview> = {}
) {
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
			total: facts.length,
			review: reviews[section.key] ?? null
		};
	});
	const done = sections.filter((section) => section.status === 'done').length;
	const unfinished = sections.find((section) => section.status !== 'done');
	// C3b: a section Uplift sent back is the client's to change, then to send again.
	const returned = sections.filter((section) => section.review?.state === 'returned');
	const toChange = returned.find((section) => !section.review?.changed);
	const check = { key: SETUP_CHECK_KEY, title: SETUP_CHECK_TITLE, status: 'not_started' as const };
	// B13: with every task done, Check and send is next until setup has been sent.
	const next = unfinished
		? { key: unfinished.key, title: unfinished.title, status: unfinished.status, returned: false }
		: toChange
			? { key: toChange.key, title: toChange.title, status: toChange.status, returned: true }
			: returned.length > 0 || !state.sent
				? { ...check, returned: false }
				: null;

	return {
		welcome_seen: state.welcomeSeen,
		sections,
		progress: { done, total: sections.length },
		// The next useful thing to do. Null once setup has been sent, every task is still done and nothing is
		// waiting on the client's changes.
		next,
		// Sections Uplift sent back on the newest send.
		returned_count: returned.length,
		// C4: Ready for Uplift gives the build's dates; the later delivery stages arrive with stage E.
		delivery: state.ready
			? { state: 'ready' as const, ...state.ready }
			: state.sent
				? { state: 'sent' as const, ...state.sent }
				: { state: 'collecting' as const }
	};
}
