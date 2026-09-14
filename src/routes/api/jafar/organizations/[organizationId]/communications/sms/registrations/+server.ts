import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsRegistrationStartSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

type RegistrationRow = {
	id: string;
	country_code: string;
	sender_type: string;
	use_case: string;
	status: string;
	provider_registration_sid: string | null;
	provider_outcome: string | null;
	required_fixes: string | null;
	submitted_at: string | null;
	last_checked_at: string | null;
	created_at: string;
	updated_at: string;
};

// Stage 2C-6: list one organization's SMS registrations for the Jafar Integrations tab, each carrying the
// same plain readiness state the contractor's own page would compute (communication_sms_readiness). A
// registration is one row per (country, sender type, use case), so the list stays small and bounded.
// Read-only; registrations are started, checked, and decided by the POST routes below and alongside.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: registrations, error } = await client
			.from('communication_sms_registrations')
			.select(
				'id, country_code, sender_type, use_case, status, provider_registration_sid, provider_outcome, required_fixes, submitted_at, last_checked_at, created_at, updated_at'
			)
			.eq('organization_id', parsedOrganizationId.data)
			.order('created_at');
		if (error) throw error;

		const withReadiness = await Promise.all(
			((registrations ?? []) as RegistrationRow[]).map(async (registration) => {
				const readinessResult = await client.rpc('communication_sms_readiness', {
					p_organization_id: parsedOrganizationId.data,
					p_country_code: registration.country_code,
					p_sender_type: registration.sender_type,
					p_use_case: registration.use_case
				});
				if (readinessResult.error) throw readinessResult.error;
				const row = Array.isArray(readinessResult.data)
					? readinessResult.data[0]
					: readinessResult.data;
				return {
					...registration,
					readiness_state: (row?.readiness_state as string) ?? null,
					live_sender_count: (row?.live_sender_count as number) ?? 0
				};
			})
		);

		return json({ registrations: withReadiness }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the SMS registrations.', error);
		return json({ error: 'The SMS registrations could not be loaded.' }, { status: 500 });
	}
};

// Stage 2C-5c: the platform owner starts (or reopens) a registration for one organization's country,
// sender type and use case. Carrier submission is a routine action (docs/jafar-organization-management-
// mission.md "High-impact action security"), so no step-up is required -- a reason/confirmation only.
// The command itself is idempotent: calling it again for the same key updates the existing row and logs
// 'info_updated' instead of losing history, so this route always records the audit event it produced.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsRegistrationStartSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the registration.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const result = await client.rpc('communication_sms_start_registration', {
			p_organization_id: parsedOrganizationId.data,
			p_country_code: parsed.data.country_code,
			p_sender_type: parsed.data.sender_type,
			p_use_case: parsed.data.use_case,
			p_actor: PLATFORM_OWNER_ACTOR_ID
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type: 'communication_sms_registration_started',
			target_type: 'communication_sms_registration',
			target_key: result.data.id,
			before_state: null,
			after_state: result.data
		});

		return json({ registration: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not start the SMS registration.', error);
		return json({ error: 'The registration could not be started.' }, { status: 500 });
	}
};
