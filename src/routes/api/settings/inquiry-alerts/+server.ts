import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadInquiryAlertSettings } from '$lib/server/team/inquiry-alerts';
import { inquiryAlertRecipientsSchema } from '$lib/server/validation/team-notifications.schema';

// Who hears about new website inquiries. Managed by whoever manages Website Chat and other connections; the
// database re-checks that permission and that every chosen person can see every inquiry.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	try {
		return json(await loadInquiryAlertSettings(check.auth.organization.id), {
			headers: PRIVATE_READ_HEADERS
		});
	} catch (error) {
		console.error('Could not load inquiry alert settings.', error);
		return json({ error: 'Inquiry alerts could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const body = await event.request.json().catch(() => null);
	const parsed = inquiryAlertRecipientsSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Choose up to 50 team members.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { error } = await getOwnerSupabaseClient().rpc('set_inquiry_alert_recipients', {
		p_organization_id: check.auth.organization.id,
		p_actor_id: check.auth.user.id,
		p_user_ids: parsed.data.user_ids
	});
	if (error) {
		// 23514: someone chosen cannot see every inquiry (their access changed since the page loaded).
		if (error.code === '23514') {
			return json(
				{
					error: 'Someone you chose can no longer see every website inquiry. Refresh and try again.'
				},
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		}
		if (error.code === '42501') {
			return json(
				{ error: 'You do not have access to do that.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		console.error('Could not save inquiry alert recipients.', error);
		return json(
			{ error: 'Inquiry alerts could not be saved.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}

	try {
		return json(await loadInquiryAlertSettings(check.auth.organization.id), {
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not reload inquiry alert settings.', error);
		return json({ error: 'Saved, but the list could not be reloaded.' }, { status: 500 });
	}
};
