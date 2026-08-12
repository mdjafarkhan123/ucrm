import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { issueSetupLink } from '$lib/server/jafar/setup-link';
import { prospectIdSchema } from '$lib/server/validation/prospect.schema';

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	const applicationId = parsedId.data;
	const client = getOwnerSupabaseClient();

	try {
		const { data: application, error: applicationError } = await client
			.from('platform_onboarding_applications')
			.select('stage, business_name, main_contact_email, initial_administrator_email')
			.eq('id', applicationId)
			.maybeSingle();
		if (applicationError) throw applicationError;
		if (!application) return json({ error: 'Prospect was not found.' }, { status: 404 });
		if (application.stage !== 'account_created')
			return json(
				{ error: 'A setup email can only be sent for a provisioned organization.' },
				{ status: 409 }
			);

		const { data: provision, error: provisionError } = await client
			.from('platform_onboarding_application_provisions')
			.select('status, administrator_user_id')
			.eq('application_id', applicationId)
			.maybeSingle();
		if (provisionError) throw provisionError;
		if (provision?.status !== 'succeeded' || !provision.administrator_user_id)
			return json(
				{ error: 'No administrator account was found for this application.' },
				{ status: 409 }
			);

		const { data: existingLink, error: existingLinkError } = await client
			.from('platform_onboarding_application_setup_links')
			.select('consumed_at')
			.eq('application_id', applicationId)
			.maybeSingle();
		if (existingLinkError) throw existingLinkError;
		if (existingLink?.consumed_at)
			return json({ error: 'The administrator has already completed setup.' }, { status: 409 });

		const administratorEmail = (
			application.initial_administrator_email ?? application.main_contact_email
		)
			.trim()
			.toLowerCase();

		const result = await issueSetupLink(client, {
			applicationId,
			administratorUserId: provision.administrator_user_id,
			intendedEmail: administratorEmail,
			businessName: application.business_name,
			origin: event.url.origin,
			actorEmail: session.email
		});

		if (!result.sent)
			return json(
				{ error: 'The setup email could not be sent. You can try resending it.' },
				{ status: 502 }
			);

		return json({ ok: true });
	} catch (error) {
		console.error('Could not send the administrator setup email.', error);
		return json({ error: 'The setup email could not be sent.' }, { status: 500 });
	}
};
