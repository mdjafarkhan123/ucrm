import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { SMS_REGISTRATION_USE_CASE } from './sms-registration';
import type {
	ReadinessNumber,
	ReadinessOrder,
	ReadinessPaperwork,
	ReadinessTollFreeCheck
} from '$lib/communications/number-readiness';

// Joins the rows behind number readiness (Stage 10 Part 4) into one fact list per number: the number itself,
// the order that bought it, and the paperwork for its country and kind. A number still being connected has an
// order but no sender yet, so it gets its own entry too. A toll-free number also carries its carrier check. The join is pure; the switch-on helpers below call the
// database command that turns passed approvals into live numbers.

export type ReadinessSenderRow = {
	id: string;
	phone_number: string;
	display_name: string | null;
	country_code: string | null;
	sender_type: string | null;
	number_type: string | null;
	lifecycle_state: string;
	capable_sms: boolean;
	capable_mms: boolean;
	capable_voice: boolean;
	is_default_sender: boolean;
	created_at: string;
};

export type ReadinessOrderRow = {
	id: string;
	phone_number: string;
	country_code: string;
	number_type: string;
	capable_sms: boolean;
	capable_mms: boolean;
	capable_voice: boolean;
	bundle_sid: string | null;
	address_sid: string | null;
	state: string;
	sender_identity_id: string | null;
	purchased_at: string | null;
	created_at: string;
};

export type ReadinessPaperworkRow = {
	id: string;
	country_code: string;
	number_type: string;
	status: string;
	failure_reason: string | null;
	valid_until: string | null;
	submitted_at: string | null;
	decided_at: string | null;
};

export type ReadinessTollFreeCheckRow = ReadinessTollFreeCheck & { sender_identity_id: string };

function order(row: ReadinessOrderRow): ReadinessOrder {
	return {
		state: row.state as ReadinessOrder['state'],
		purchased_at: row.purchased_at,
		created_at: row.created_at,
		needs_paperwork: row.bundle_sid !== null || row.address_sid !== null
	};
}

function paperwork(row: ReadinessPaperworkRow | undefined): ReadinessPaperwork | null {
	if (!row) return null;
	return {
		id: row.id,
		status: row.status as ReadinessPaperwork['status'],
		failure_reason: row.failure_reason,
		valid_until: row.valid_until,
		submitted_at: row.submitted_at,
		decided_at: row.decided_at
	};
}

export function readinessNumbers(
	senders: ReadinessSenderRow[],
	orders: ReadinessOrderRow[],
	paperworkRows: ReadinessPaperworkRow[],
	tollFreeRows: ReadinessTollFreeCheckRow[] = []
): ReadinessNumber[] {
	const tollFreeCheckFor = (senderId: string): ReadinessTollFreeCheck | null => {
		const row = tollFreeRows.find((check) => check.sender_identity_id === senderId);
		if (!row) return null;
		const { sender_identity_id: _sender, ...check } = row;
		void _sender;
		return check;
	};
	const paperworkFor = (country: string, numberType: string | null) =>
		paperwork(
			paperworkRows.find((row) => row.country_code === country && row.number_type === numberType)
		);
	const used = new Set<string>();

	const owned = senders.map((sender): ReadinessNumber => {
		const bought =
			orders.find((row) => row.sender_identity_id === sender.id) ??
			orders.find((row) => !row.sender_identity_id && row.phone_number === sender.phone_number);
		if (bought) used.add(bought.id);
		const country = sender.country_code ?? bought?.country_code ?? 'US';
		const numberType = sender.number_type ?? bought?.number_type ?? null;
		return {
			sender_id: sender.id,
			order_id: bought?.id ?? null,
			phone_number: sender.phone_number,
			display_name: sender.display_name,
			country_code: country,
			sender_type: (sender.sender_type ?? 'long_code') as ReadinessNumber['sender_type'],
			number_type: numberType as ReadinessNumber['number_type'],
			lifecycle_state: sender.lifecycle_state as ReadinessNumber['lifecycle_state'],
			capabilities: {
				sms: sender.capable_sms,
				mms: sender.capable_mms,
				voice: sender.capable_voice
			},
			is_default_sender: sender.is_default_sender,
			created_at: sender.created_at,
			order: bought ? order(bought) : null,
			paperwork: paperworkFor(country, numberType),
			toll_free_check: tollFreeCheckFor(sender.id)
		};
	});

	// Orders still being connected: bought or being bought, with no sender yet.
	const connecting = orders
		.filter((row) => !used.has(row.id) && row.state !== 'completed')
		.map((row): ReadinessNumber => ({
			sender_id: null,
			order_id: row.id,
			phone_number: row.phone_number,
			display_name: null,
			country_code: row.country_code,
			sender_type: row.number_type === 'toll_free' ? 'toll_free' : 'long_code',
			number_type: row.number_type as ReadinessNumber['number_type'],
			lifecycle_state: null,
			capabilities: { sms: row.capable_sms, mms: row.capable_mms, voice: row.capable_voice },
			is_default_sender: false,
			created_at: row.created_at,
			order: order(row),
			paperwork: paperworkFor(row.country_code, row.number_type),
			toll_free_check: null
		}));

	// The default first, then the oldest, so the cards keep their places as numbers are added.
	return [...owned, ...connecting].sort(
		(a, b) =>
			Number(b.is_default_sender) - Number(a.is_default_sender) ||
			a.created_at.localeCompare(b.created_at)
	);
}

/**
 * Switch on every number of this business whose route's approval has now passed (US: the approved US
 * registration; elsewhere: approved, in-date paperwork). Called after a purchase finishes, after an approval
 * arrives and by the daily check; never throws, because the next of those runs finishes whatever this misses.
 */
export async function reconcileSenderReadiness(
	client: SupabaseClient<Database>,
	organizationId: string
): Promise<number> {
	const { data, error } = await client.rpc('communication_sms_reconcile_sender_readiness', {
		p_organization_id: organizationId,
		p_us_use_case: SMS_REGISTRATION_USE_CASE
	});
	if (error) {
		console.error('Could not switch on numbers whose approval passed.', { organizationId, error });
		return 0;
	}
	return data ?? 0;
}

/** The daily sweep: every business that still has a number waiting to be switched on. */
export async function reconcileAllSenderReadiness(client: SupabaseClient<Database>) {
	const { data, error } = await client
		.from('communication_sms_sender_identities')
		.select('organization_id')
		.eq('lifecycle_state', 'pending_setup');
	if (error) {
		console.error('Could not list numbers waiting to be switched on.', error);
		return { organizations: 0, switched_on: 0 };
	}
	const organizations = [...new Set((data ?? []).map((row) => row.organization_id))];
	let switchedOn = 0;
	for (const organizationId of organizations) {
		switchedOn += await reconcileSenderReadiness(client, organizationId);
	}
	return { organizations: organizations.length, switched_on: switchedOn };
}
