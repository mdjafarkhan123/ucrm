import type {
	ReadinessNumber,
	ReadinessOrder,
	ReadinessPaperwork
} from '$lib/communications/number-readiness';

// Joins the rows behind number readiness (Stage 10 Part 4) into one fact list per number: the number itself,
// the order that bought it, and the paperwork for its country and kind. A number still being connected has an
// order but no sender yet, so it gets its own entry too. Pure, so the join is tested without a database.

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
	paperworkRows: ReadinessPaperworkRow[]
): ReadinessNumber[] {
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
			paperwork: paperworkFor(country, numberType)
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
			paperwork: paperworkFor(row.country_code, row.number_type)
		}));

	// The default first, then the oldest, so the cards keep their places as numbers are added.
	return [...owned, ...connecting].sort(
		(a, b) =>
			Number(b.is_default_sender) - Number(a.is_default_sender) ||
			a.created_at.localeCompare(b.created_at)
	);
}
