import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { prospectIdSchema } from '$lib/server/validation/prospect.schema';

const applicationSelect =
	'id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone, initial_administrator_name, initial_administrator_email, trade, city_country, time_zone, note, package_version_id, package_snapshot, possible_duplicate, submitted_at, updated_at, not_proceeding_at, personal_data_purge_after';

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const [applicationResult, submissionResult, correctionResult, setupLinkResult] =
			await Promise.all([
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
					.maybeSingle()
			]);

		if (applicationResult.error) throw applicationResult.error;
		if (!applicationResult.data) return json({ error: 'Prospect was not found.' }, { status: 404 });
		if (submissionResult.error) throw submissionResult.error;
		if (correctionResult.error) throw correctionResult.error;
		if (setupLinkResult.error) throw setupLinkResult.error;

		return json({
			prospect: applicationResult.data,
			original_submission: submissionResult.data,
			corrections: correctionResult.data ?? [],
			setup_link: setupLinkResult.data
		});
	} catch (error) {
		console.error('Could not load owner prospect.', error);
		return json({ error: 'Prospect could not be loaded.' }, { status: 500 });
	}
};
