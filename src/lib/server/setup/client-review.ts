// Client onboarding C3b: Uplift's review as the client sees it (plan §4). Uplift decides on the newest send,
// read against the setup version it was taken with (ADR 0005), so this reads that send the way Jafar's page does
// and folds each section's state into the client's three. Only a send's own question list needs the service
// role; the send and the decisions are read with the caller's client, which the organization's administrators
// may read.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueForServices,
	sectionFacts,
	type SetupAnswers,
	type SetupCatalogue,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';
import { sameSectionAnswers, setupClientReview, type SetupClientReview } from '$lib/setup/review';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSectionReviews } from '$lib/server/setup/client-page';
import { setupAnswerFromRow, type SetupState } from '$lib/server/setup/read';

/**
 * Each section's review, keyed by section, for the sections of `catalogue` (the client's questions now) that
 * were in their newest send. Empty before the first send. Throws when the database cannot be read.
 */
export async function readClientSetupReviews(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	state: SetupState,
	catalogue: SetupCatalogue
): Promise<Record<string, SetupClientReview>> {
	if (!state.sent) return {};

	const { data: send, error } = await supabase
		.from('organization_setup_submissions')
		.select('setup_version_id, service_keys, answers')
		.eq('organization_id', organizationId)
		.eq('submission_number', state.sent.number)
		.single();
	if (error) throw error;

	// The version id comes from this organization's own send, so this reads only the questions they were asked.
	const versionResult = await getOwnerSupabaseClient().rpc('owner_setup_version_catalogue', {
		target_version_id: send.setup_version_id
	});
	if (versionResult.error || !versionResult.data)
		throw versionResult.error ?? new Error('The setup version of a send is missing.');
	const sentCatalogue = catalogueForServices(
		buildSetupCatalogue(versionResult.data as unknown as SetupCatalogueRow),
		new Set(send.service_keys)
	);

	const sentAnswers: SetupAnswers = {};
	for (const [key, row] of Object.entries((send.answers ?? {}) as Record<string, never>))
		sentAnswers[key] = setupAnswerFromRow(row);

	const reviews = await readSectionReviews(supabase, organizationId, {
		number: state.sent.number,
		answers: sentAnswers,
		catalogue: sentCatalogue
	});

	const result: Record<string, SetupClientReview> = {};
	for (const section of catalogue.sections) {
		const review = reviews[section.key];
		if (!review) continue;
		const factKeys = sectionFacts(section).map((fact) => fact.key);
		const changed = !sameSectionAnswers(factKeys, state.answers, sentAnswers);
		result[section.key] = setupClientReview(review, changed);
	}
	return result;
}
