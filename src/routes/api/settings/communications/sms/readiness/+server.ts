import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import {
	SMS_REGISTRATION_COUNTRY_CODE,
	SMS_REGISTRATION_SENDER_TYPE,
	SMS_REGISTRATION_USE_CASE
} from '$lib/server/communications/sms-registration';
import {
	priceRenewals,
	readinessNumbers,
	type ReadinessTollFreeCheckRow
} from '$lib/server/communications/sms-number-readiness';

// A released number keeps its card this long, so the business sees what happened to it (Part 7).
const RELEASED_CARD_DAYS = 30;

// Whether each texting number can text yet (Stage 10 Part 4): every number the business owns or is still
// connecting, each with its own order, paperwork, toll-free check and the US registration it may share. The page turns these
// facts into cards with $lib/communications/number-readiness.ts; nothing here is a write.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const client = getOwnerSupabaseClient();
	const organizationId = check.auth.organization.id;
	const releasedSince = new Date(Date.now() - RELEASED_CARD_DAYS * 86_400_000).toISOString();
	const [senders, orders, paperwork, tollFree, registration, account] = await Promise.all([
		client
			.from('communication_sms_sender_identities')
			.select(
				'id, phone_number, display_name, country_code, sender_type, number_type, lifecycle_state, capable_sms, capable_mms, capable_voice, is_default_sender, created_at, renewal_state, renews_at, unpaid_since, grace_ends_at, released_at'
			)
			.eq('organization_id', organizationId)
			.or(`lifecycle_state.neq.released,released_at.gte.${releasedSince}`),
		client
			.from('communication_sms_number_orders')
			.select(
				'id, phone_number, country_code, number_type, capable_sms, capable_mms, capable_voice, bundle_sid, address_sid, state, sender_identity_id, purchased_at, created_at'
			)
			.eq('organization_id', organizationId)
			.neq('state', 'failed'),
		client
			.from('communication_sms_number_paperwork')
			.select(
				'id, country_code, number_type, status, failure_reason, valid_until, submitted_at, decided_at'
			)
			.eq('organization_id', organizationId),
		client
			.from('communication_sms_tollfree_verifications')
			.select(
				'id, sender_identity_id, status, failure_reason, submitted_at, decided_at, edit_expires_at'
			)
			.eq('organization_id', organizationId),
		client
			.from('communication_sms_registrations')
			.select('status, required_fixes, submitted_at, updated_at')
			.eq('organization_id', organizationId)
			.eq('country_code', SMS_REGISTRATION_COUNTRY_CODE)
			.eq('sender_type', SMS_REGISTRATION_SENDER_TYPE)
			.eq('use_case', SMS_REGISTRATION_USE_CASE)
			.maybeSingle(),
		client
			.from('communication_sms_credit_accounts')
			.select('currency_code, settled_balance_minor, reserved_balance_minor')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);
	const failed = [senders, orders, paperwork, tollFree, registration, account].find(
		(result) => result.error
	);
	if (failed) {
		console.error('Could not load number readiness.', failed.error);
		return databaseError();
	}

	const currency = account.data?.currency_code ?? 'USD';
	let renewals;
	try {
		renewals = await priceRenewals(client, senders.data ?? [], currency);
	} catch (error) {
		console.error('Could not price number renewals.', error);
		return databaseError();
	}

	return json(
		{
			numbers: readinessNumbers(
				(senders.data ?? []).map((sender) => ({
					...sender,
					renewal: renewals.get(sender.id) ?? null
				})),
				orders.data ?? [],
				paperwork.data ?? [],
				(tollFree.data ?? []) as ReadinessTollFreeCheckRow[]
			),
			us_registration: registration.data ?? null,
			balance: {
				available_minor: account.data
					? account.data.settled_balance_minor - account.data.reserved_balance_minor
					: 0,
				currency
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
