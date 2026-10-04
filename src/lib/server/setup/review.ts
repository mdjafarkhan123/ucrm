// Client onboarding C3: Jafar's decision on one section of a client's newest send (plan §4). The section and
// any ticked questions are checked against the setup version that send was taken with, so Jafar can only
// return questions the client was actually asked. The database refuses a decision on anything but the newest
// send and records each one in Jafar's history.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueForServices,
	sectionFacts,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';
import type { SetupSectionReviewInput } from '$lib/server/validation/setup.schema';

export type SectionReviewResult =
	| { status: 'saved' | 'unchanged' }
	| { status: 'stale'; latest_number: number }
	| { status: 'not_found'; message: string }
	| { status: 'invalid'; field: 'section_key' | 'question_keys'; message: string };

export async function recordSectionReview(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	actorEmail: string,
	input: SetupSectionReviewInput
): Promise<SectionReviewResult> {
	const { data: send, error } = await supabase
		.from('organization_setup_submissions')
		.select('setup_version_id, service_keys')
		.eq('organization_id', organizationId)
		.eq('submission_number', input.send)
		.maybeSingle();
	if (error) throw error;
	if (!send) return { status: 'not_found', message: 'That setup send does not exist.' };

	const catalogueResult = await supabase.rpc('owner_setup_version_catalogue', {
		target_version_id: send.setup_version_id
	});
	if (catalogueResult.error || !catalogueResult.data)
		throw catalogueResult.error ?? new Error('The setup version of a send is missing.');
	const catalogue = catalogueForServices(
		buildSetupCatalogue(catalogueResult.data as unknown as SetupCatalogueRow),
		new Set(send.service_keys)
	);

	const section = catalogue.sections.find((item) => item.key === input.section_key);
	if (!section)
		return { status: 'invalid', field: 'section_key', message: 'That task is not in this send.' };

	const questionKeys = input.decision === 'returned' ? input.question_keys : [];
	const asked = new Set(sectionFacts(section).map((fact) => fact.key));
	if (questionKeys.some((key) => !asked.has(key)))
		return {
			status: 'invalid',
			field: 'question_keys',
			message: 'Tick only questions from this task.'
		};

	const { data, error: reviewError } = await supabase.rpc('owner_review_setup_section', {
		target_organization_id: organizationId,
		target_section_key: input.section_key,
		seen_number: input.send,
		new_decision: input.decision,
		// The database ignores the note of an acceptance.
		return_note: input.decision === 'returned' ? input.note : '',
		return_question_keys: questionKeys,
		actor_email: actorEmail
	});
	if (reviewError) throw reviewError;
	return data as unknown as SectionReviewResult;
}
