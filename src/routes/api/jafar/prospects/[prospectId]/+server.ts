import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { prospectIdSchema } from '$lib/server/validation/prospect.schema';
import { loadOfferedExperiences } from '$lib/server/experience/offered';

const applicationSelect =
	'id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone, initial_administrator_name, initial_administrator_email, trade, described_work, proposed_experience_key, proposed_definition_version, proposed_business_type_key, proposed_other, city_country, time_zone, note, package_edition_id, billing_interval, package_snapshot, possible_duplicate, duplicate_acknowledged_at, duplicate_acknowledged_by_owner_email, submitted_at, updated_at, not_proceeding_at, personal_data_purge_after, payment_reversed_at, business_relationship_id, linked_lead:platform_business_relationships(id, business_name)';

const duplicateMatchSelect =
	'id, business_name, main_contact_email, initial_administrator_email, stage, submitted_at';

type DuplicateMatchRow = {
	id: string;
	business_name: string;
	main_contact_email: string;
	initial_administrator_email: string | null;
	stage: string;
	submitted_at: string;
};

function duplicateMatchReasons(
	candidate: DuplicateMatchRow,
	application: {
		business_name: string;
		main_contact_email: string;
		initial_administrator_email: string | null;
	}
) {
	const reasons: string[] = [];
	if (candidate.main_contact_email.toLowerCase() === application.main_contact_email.toLowerCase())
		reasons.push('Same contact email');
	if (candidate.business_name.toLowerCase() === application.business_name.toLowerCase())
		reasons.push('Same business name');
	if (
		application.initial_administrator_email &&
		candidate.initial_administrator_email?.toLowerCase() ===
			application.initial_administrator_email.toLowerCase()
	)
		reasons.push('Same administrator email');
	return reasons;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const [
			applicationResult,
			submissionResult,
			correctionResult,
			setupLinkResult,
			paymentConfirmationResult,
			paymentReversalResult,
			provisionResult,
			qualificationResult,
			offeredExperiences,
			businessTypeResult
		] = await Promise.all([
			client
				.from('platform_onboarding_applications')
				.select(applicationSelect)
				.eq('id', parsedId.data)
				.maybeSingle(),
			client
				.from('platform_onboarding_application_submissions')
				.select(
					'id, application_id, submitted_data, package_snapshot, privacy_policy_version, agreement_accepted_at, submitted_at'
				)
				.eq('application_id', parsedId.data)
				.maybeSingle(),
			client
				.from('platform_onboarding_application_corrections')
				.select(
					'id, application_id, actor_owner_email, reason, before_state, after_state, created_at'
				)
				.eq('application_id', parsedId.data)
				.order('created_at', { ascending: false }),
			client
				.from('platform_onboarding_application_setup_links')
				.select('intended_email, expires_at, consumed_at, last_sent_at, last_error')
				.eq('application_id', parsedId.data)
				.maybeSingle(),
			client
				.from('platform_onboarding_application_payment_confirmations')
				.select(
					'id, actor_owner_email, amount_usd_cents, currency, private_reference, mismatch_reason, received_on, method, note, confirmed_at'
				)
				.eq('application_id', parsedId.data)
				.order('confirmed_at', { ascending: false }),
			client
				.from('platform_onboarding_application_payment_reversals')
				.select('id, actor_owner_email, reason, reversed_amount_usd_cents, reversed_at')
				.eq('application_id', parsedId.data)
				.order('reversed_at', { ascending: false }),
			client
				.from('platform_onboarding_application_provisions')
				.select('status, last_error, attempt_count, updated_at')
				.eq('application_id', parsedId.data)
				.maybeSingle(),
			// Multi-industry foundation B3: Uplift's decisions about the kind of business, newest first, and
			// what can be chosen when confirming one.
			client
				.from('platform_onboarding_application_qualifications')
				.select(
					'id, outcome, experience_key, definition_version, business_type_key, reviewed_work, buyer_message, reason, actor_owner_email, created_at'
				)
				.eq('application_id', parsedId.data)
				.order('created_at', { ascending: false }),
			loadOfferedExperiences(client),
			client
				.from('industry_experience_business_types')
				.select('experience_key, definition_version, business_type_key, label')
		]);

		if (applicationResult.error) throw applicationResult.error;
		if (!applicationResult.data) return json({ error: 'Prospect was not found.' }, { status: 404 });
		if (submissionResult.error) throw submissionResult.error;
		if (correctionResult.error) throw correctionResult.error;
		if (setupLinkResult.error) throw setupLinkResult.error;
		if (paymentConfirmationResult.error) throw paymentConfirmationResult.error;
		if (paymentReversalResult.error) throw paymentReversalResult.error;
		if (provisionResult.error) throw provisionResult.error;
		if (qualificationResult.error) throw qualificationResult.error;
		if (businessTypeResult.error) throw businessTypeResult.error;

		const typeLabel = (experience: string | null, version: number | null, type: string | null) =>
			(businessTypeResult.data ?? []).find(
				(row) =>
					row.experience_key === experience &&
					row.definition_version === version &&
					row.business_type_key === type
			)?.label ?? null;

		const application = applicationResult.data;
		let duplicateMatches: (DuplicateMatchRow & { matched_on: string[] })[] = [];
		if (application.possible_duplicate) {
			// Three separate equality queries (merged below) instead of a single `.or()` filter
			// string -- business_name is free text and could contain PostgREST filter syntax
			// (commas, parentheses) that would change the query's meaning if interpolated directly.
			const matchQueries = [
				client
					.from('platform_onboarding_applications')
					.select(duplicateMatchSelect)
					.neq('id', parsedId.data)
					.eq('main_contact_email', application.main_contact_email)
					.limit(5),
				client
					.from('platform_onboarding_applications')
					.select(duplicateMatchSelect)
					.neq('id', parsedId.data)
					.eq('business_name', application.business_name)
					.limit(5)
			];
			if (application.initial_administrator_email)
				matchQueries.push(
					client
						.from('platform_onboarding_applications')
						.select(duplicateMatchSelect)
						.neq('id', parsedId.data)
						.eq('initial_administrator_email', application.initial_administrator_email)
						.limit(5)
				);

			const matchResults = await Promise.all(matchQueries);
			for (const result of matchResults) if (result.error) throw result.error;

			const byId = new Map<string, DuplicateMatchRow>();
			for (const result of matchResults)
				for (const candidate of result.data ?? []) byId.set(candidate.id, candidate);

			duplicateMatches = Array.from(byId.values())
				.sort((a, b) => b.submitted_at.localeCompare(a.submitted_at))
				.slice(0, 5)
				.map((candidate) => ({
					...candidate,
					matched_on: duplicateMatchReasons(candidate, application)
				}));
		}

		return json({
			prospect: application,
			original_submission: submissionResult.data,
			corrections: correctionResult.data ?? [],
			setup_link: setupLinkResult.data,
			duplicate_matches: duplicateMatches,
			payment_confirmations: paymentConfirmationResult.data ?? [],
			payment_reversals: paymentReversalResult.data ?? [],
			provision: provisionResult.data,
			proposed_business_type_label: typeLabel(
				application.proposed_experience_key,
				application.proposed_definition_version,
				application.proposed_business_type_key
			),
			qualifications: (qualificationResult.data ?? []).map((decision) => ({
				...decision,
				business_type_label: typeLabel(
					decision.experience_key,
					decision.definition_version,
					decision.business_type_key
				),
				experience_name:
					offeredExperiences.find((d) => d.experience_key === decision.experience_key)?.name ??
					decision.experience_key
			})),
			offered_experiences: offeredExperiences
		});
	} catch (error) {
		console.error('Could not load owner prospect.', error);
		return json({ error: 'Prospect could not be loaded.' }, { status: 500 });
	}
};
