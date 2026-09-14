import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

type RegistrationEventRow = {
	id: string;
	registration_id: string;
	event_type: string;
	from_status: string | null;
	to_status: string | null;
	detail: string | null;
	provider_outcome: string | null;
	created_at: string;
};

type RegistrationKeyRow = {
	id: string;
	country_code: string;
	sender_type: string;
	use_case: string;
};

// Stage 2C-6c: list one organization's SMS registration/provider history for the Jafar History & recovery tab.
// communication_sms_registration_events is append-only (started/info_updated/submitted/resubmitted/approved/
// action_needed/readiness_checked) and has been write-only since 2C-3 -- the registration/check/outcome routes
// insert it, but nothing has read it back until now. Read-only; each event is joined with its registration's
// country/sender type/use case since a bare registration id isn't meaningful in a list.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();

		const [
			{ data: events, error: eventsError },
			{ data: registrations, error: registrationsError }
		] = await Promise.all([
			client
				.from('communication_sms_registration_events')
				.select(
					'id, registration_id, event_type, from_status, to_status, detail, provider_outcome, created_at'
				)
				.eq('organization_id', parsedOrganizationId.data)
				.order('created_at', { ascending: false })
				.limit(200),
			client
				.from('communication_sms_registrations')
				.select('id, country_code, sender_type, use_case')
				.eq('organization_id', parsedOrganizationId.data)
		]);
		if (eventsError) throw eventsError;
		if (registrationsError) throw registrationsError;

		const registrationById = new Map(
			((registrations ?? []) as RegistrationKeyRow[]).map((registration) => [
				registration.id,
				registration
			])
		);

		const withRegistration = ((events ?? []) as RegistrationEventRow[]).map((registrationEvent) => {
			const registration = registrationById.get(registrationEvent.registration_id);
			return {
				...registrationEvent,
				country_code: registration?.country_code ?? null,
				sender_type: registration?.sender_type ?? null,
				use_case: registration?.use_case ?? null
			};
		});

		return json({ events: withRegistration }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the SMS registration history.', error);
		return json({ error: 'The SMS registration history could not be loaded.' }, { status: 500 });
	}
};
