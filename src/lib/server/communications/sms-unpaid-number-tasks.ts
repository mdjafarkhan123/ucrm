import type { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { formatMinor } from '$lib/communications/sms-number-shop';
import type { TextingSetupQueue, UnpaidNumberTask } from '$lib/jafar/texting-setup';

// Stage 10 Part 7: the Texting setup page's "Unpaid number" tasks (board `QiDBX`). One per number in its 14-day
// renewal grace, with what it owes, the business's balance and what has happened so far. Uplift has nothing to
// press: a confirmed top-up pays the renewal and the task leaves the queue; otherwise the number is released.

type Client = ReturnType<typeof getOwnerSupabaseClient>;

const NUMBER_KIND: Record<string, string> = {
	local: 'Local',
	mobile: 'Mobile',
	national: 'National',
	toll_free: 'Toll-free'
};

export function numberKindWords(numberType: string | null, senderType: string | null) {
	return NUMBER_KIND[numberType ?? (senderType === 'toll_free' ? 'toll_free' : 'local')] ?? 'Local';
}

export async function unpaidNumberTasks(client: Client): Promise<UnpaidNumberTask[]> {
	const { data: senders, error } = await client
		.from('communication_sms_sender_identities')
		.select(
			'id, organization_id, phone_number, display_name, country_code, number_type, sender_type, unpaid_since, grace_ends_at, renewal_period'
		)
		.eq('renewal_state', 'unpaid')
		.neq('lifecycle_state', 'released')
		.order('unpaid_since', { ascending: true });
	if (error) throw error;
	if (!senders?.length) return [];

	const organizationIds = [...new Set(senders.map((row) => row.organization_id))];
	const senderIds = senders.map((row) => row.id);
	const [organizations, accounts, renewals, owners, warnings] = await Promise.all([
		client.from('organizations').select('id, name').in('id', organizationIds),
		client
			.from('communication_sms_credit_accounts')
			.select('organization_id, currency_code, settled_balance_minor, reserved_balance_minor')
			.in('organization_id', organizationIds),
		client
			.from('communication_sms_number_renewals')
			.select(
				'sender_identity_id, period_number, renews_at, amount_minor, currency_code, state, created_at, paid_at'
			)
			.in('sender_identity_id', senderIds)
			.order('renews_at', { ascending: false })
			.limit(senderIds.length * 6),
		client
			.from('organization_members')
			.select('organization_id, user_id, created_at')
			.in('organization_id', organizationIds)
			.eq('role', 'owner')
			.eq('status', 'active'),
		client
			.from('team_notifications')
			.select('subject_id, source_key, created_at')
			.eq('kind', 'communications.number_renewal')
			.in('subject_id', senderIds)
	]);
	const failed = [organizations, accounts, renewals, owners, warnings].find(
		(result) => result.error
	);
	if (failed?.error) throw failed.error;
	const ownerIds = [...new Set((owners.data ?? []).map((row) => row.user_id))];
	const profiles = ownerIds.length
		? await client.from('profiles').select('id, full_name').in('id', ownerIds)
		: { data: [], error: null };
	if (profiles.error) throw profiles.error;
	const nameOf = new Map(
		(profiles.data ?? []).map((row) => [row.id, row.full_name?.trim() || null])
	);

	return senders.map((sender): UnpaidNumberTask => {
		const account = accounts.data?.find((row) => row.organization_id === sender.organization_id);
		const currency = account?.currency_code ?? 'USD';
		const balance = account ? account.settled_balance_minor - account.reserved_balance_minor : 0;
		const own = (renewals.data ?? []).filter((row) => row.sender_identity_id === sender.id);
		const unpaid = own.find((row) => row.period_number === sender.renewal_period);
		// The longest-standing owner when a business has several.
		const owner = (owners.data ?? [])
			.filter((row) => row.organization_id === sender.organization_id)
			.sort((a, b) => a.created_at.localeCompare(b.created_at))[0];
		const ownerName = owner ? (nameOf.get(owner.user_id) ?? null) : null;
		const who = ownerName?.split(' ')[0] ?? 'The owner';

		const history: UnpaidNumberTask['history'] = [];
		for (const row of own) {
			if (row.state === 'paid' && row.paid_at)
				history.push({
					kind: 'renewed',
					at: row.paid_at,
					text: `Renewed for ${formatMinor(row.amount_minor, row.currency_code)} from the texting balance.`
				});
			else
				history.push({
					kind: 'failed',
					at: row.created_at,
					text: `Renewal failed; sending paused. ${who} was emailed and told in the bell.`
				});
		}
		// One warning per period, however many owners got it.
		const warned = new Map<string, string>();
		for (const row of warnings.data ?? []) {
			if (row.subject_id !== sender.id || !row.source_key.startsWith('number_renewal_short:'))
				continue;
			if (!warned.has(row.source_key)) warned.set(row.source_key, row.created_at);
		}
		for (const at of warned.values())
			history.push({
				kind: 'warned',
				at,
				text: `Warned ${who}: the balance can’t cover the next renewal.`
			});
		history.sort((a, b) => b.at.localeCompare(a.at));

		return {
			id: `unpaid:${sender.id}`,
			sender_id: sender.id,
			organization_id: sender.organization_id,
			organization_name:
				organizations.data?.find((row) => row.id === sender.organization_id)?.name ?? 'A business',
			owner_name: ownerName,
			name: sender.display_name?.trim() || sender.phone_number,
			phone_number: sender.phone_number,
			country: sender.country_code ?? 'US',
			number_type: numberKindWords(sender.number_type, sender.sender_type),
			requested_at: sender.unpaid_since as string,
			grace_ends_at: sender.grace_ends_at as string,
			amount_minor: unpaid?.amount_minor ?? 0,
			balance_minor: balance,
			currency,
			history
		};
	});
}

/** The queue with its unpaid numbers, counted in To do. */
export function withUnpaidNumberTasks(
	queue: Omit<TextingSetupQueue, 'unpaid_number_tasks'>,
	unpaid: UnpaidNumberTask[]
): TextingSetupQueue {
	const oldest = [queue.summary.oldest_at, unpaid[0]?.requested_at]
		.filter((value): value is string => !!value)
		.sort()[0];
	return {
		...queue,
		summary: {
			...queue.summary,
			to_do: queue.summary.to_do + unpaid.length,
			oldest_at: oldest ?? null
		},
		unpaid_number_tasks: unpaid
	};
}
