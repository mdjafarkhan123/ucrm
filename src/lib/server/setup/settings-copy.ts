// Client onboarding C5: copies a client's accepted setup answers into their CRM settings (plan §4, §10 journey 6).
// Run after Jafar accepts a section or records Uplift's answer to a help request. It always copies everything
// accepted so far, so running it again changes nothing; the database keeps any newer change the owner made in
// Settings (`public.owner_copy_setup_settings`).

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueFacts,
	catalogueForServices,
	sectionFacts,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';
import { applicableHelpAnswers } from '$lib/setup/help';
import {
	setupSettingProposals,
	type SetupSettingKey,
	type SetupSettingOutcome
} from '$lib/setup/settings-copy';
import { readSectionReviews, snapshotAnswers } from '$lib/server/setup/client-page';
import { readSetupHelpAnswers } from '$lib/server/setup/help';
import { forgetOrganizationTimezone } from '$lib/server/requests/timezone';

type Client = SupabaseClient<Database>;

/** What happened to each setting this time; empty when nothing is accepted yet. */
export type SetupSettingsCopyResult = Partial<Record<SetupSettingKey, SetupSettingOutcome>>;

export async function copyAcceptedSetupSettings(
	supabase: Client,
	organizationId: string,
	actorEmail: string
): Promise<SetupSettingsCopyResult> {
	const { data: rows, error } = await supabase
		.from('organization_setup_submissions')
		.select('submission_number, submitted_at, setup_version_id, service_keys, answers')
		.eq('organization_id', organizationId)
		.order('submission_number', { ascending: true });
	if (error) throw error;
	const newest = rows.at(-1);
	if (!newest) return {};

	const catalogueResult = await supabase.rpc('owner_setup_version_catalogue', {
		target_version_id: newest.setup_version_id
	});
	if (catalogueResult.error || !catalogueResult.data)
		throw catalogueResult.error ?? new Error('The setup version of a send is missing.');
	const catalogue = catalogueForServices(
		buildSetupCatalogue(catalogueResult.data as unknown as SetupCatalogueRow),
		new Set(newest.service_keys)
	);

	const sends = rows.map((row) => ({
		number: row.submission_number,
		submitted_at: row.submitted_at,
		answers: snapshotAnswers(row.answers)
	}));
	const newestAnswers = sends[sends.length - 1].answers;
	const [reviews, help] = await Promise.all([
		readSectionReviews(supabase, organizationId, {
			number: newest.submission_number,
			answers: newestAnswers,
			catalogue
		}),
		readSetupHelpAnswers(supabase, organizationId, catalogueFacts(catalogue))
	]);

	const acceptedKeys = new Set(
		catalogue.sections
			.filter((section) => reviews[section.key]?.state === 'accepted')
			.flatMap((section) => sectionFacts(section).filter((fact) => fact.builtIn))
			.map((fact) => fact.key)
	);
	const proposals = setupSettingProposals({
		sends,
		acceptedKeys,
		help: applicableHelpAnswers(help, newestAnswers)
	});
	if (Object.keys(proposals).length === 0) return {};

	const { data, error: copyError } = await supabase.rpc('owner_copy_setup_settings', {
		target_organization_id: organizationId,
		proposals: proposals as unknown as Json,
		actor_email: actorEmail
	});
	if (copyError) throw copyError;
	// Time zone and currency are held in process for every request that formats a date or an amount.
	forgetOrganizationTimezone(organizationId);
	return (data as { results: SetupSettingsCopyResult }).results;
}
