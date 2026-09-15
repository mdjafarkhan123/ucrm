import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { safeSmsBalance, type SmsCreditAccountRow } from '$lib/server/communications/sms-settings';

const noStore = { 'Cache-Control': 'no-store' };

async function authorize(event: Parameters<RequestHandler>[0]) {
	return requireOrganizationAdmin(event, 'conversations.manage_connections');
}

// This calendar month in UTC, matching the existing email-allowance period convention
// (date_trunc('month', now() at time zone 'UTC'), see 20260828005207_communications_email_provider_period_capacity.sql)
// so "this month" reads the same way across every Communications usage surface.
function currentMonthUtc(now = new Date()) {
	const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
	const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
	return { start: start.toISOString(), end: end.toISOString() };
}

// The Messaging health window (blueprint §4: "a short selected period"). Fixed at 30 days for this lean first
// version; a period picker is a later enhancement, not part of 3D.
const HEALTH_WINDOW_DAYS = 30;

// The Settings → Communications → SMS usage page (Stage 3D). Three read-only panes, deliberately lean:
//   - Balance: Stage 2C's settled/reserved/promotional/spendable truth, unchanged from the Jafar view.
//   - Usage summary: this month's retail charge, segments, messages and adjustments from the same ledger and
//     reservations tables -- no new aggregation table, the volume is bounded to one organization's month.
//   - Messaging health: Sent/Delivered/Failed counts from the shared message-event history, scoped to this
//     organization's SMS intents. No SMS has ever been sent yet (the send worker is a later stage), so these
//     are correctly zero today; "Received" has no source yet -- inbound SMS storage does not exist until
//     Conversations SMS ships -- and stays a static, explained zero rather than a guess.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;

	const client = getOwnerSupabaseClient();
	const organizationId = check.auth.organization.id;
	const month = currentMonthUtc();
	const healthSince = new Date(Date.now() - HEALTH_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();

	const [
		accountResult,
		promoBalanceResult,
		spendableBalanceResult,
		holdResult,
		chargesResult,
		adjustmentsResult,
		reservationsResult,
		optOutResult,
		messageEventsResult
	] = await Promise.all([
		client
			.from('communication_sms_credit_accounts')
			.select('currency_code, settled_balance_minor, reserved_balance_minor')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		client.rpc('communication_sms_promotional_balance', { p_organization_id: organizationId }),
		client.rpc('communication_sms_spendable_balance', { p_organization_id: organizationId }),
		client.rpc('communication_sms_active_outbound_hold', { p_organization_id: organizationId }),
		client
			.from('communication_sms_credit_ledger_entries')
			.select('amount_minor')
			.eq('organization_id', organizationId)
			.eq('entry_kind', 'charge')
			.gte('occurred_at', month.start)
			.lt('occurred_at', month.end),
		client
			.from('communication_sms_credit_ledger_entries')
			.select('amount_minor')
			.eq('organization_id', organizationId)
			.eq('entry_kind', 'adjustment')
			.gte('occurred_at', month.start)
			.lt('occurred_at', month.end),
		client
			.from('communication_sms_credit_reservations')
			.select('segment_count')
			.eq('organization_id', organizationId)
			.eq('state', 'settled')
			.gte('settled_at', month.start)
			.lt('settled_at', month.end),
		client
			.from('communication_sms_consent_state')
			.select('organization_id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.eq('state', 'opted_out')
			.gte('effective_at', healthSince),
		client
			.from('communication_message_events')
			.select(
				'event_kind, communication_delivery_intents!communication_message_events_delivery_intent_id_fkey!inner(channel)'
			)
			.eq('organization_id', organizationId)
			.eq('communication_delivery_intents.channel', 'sms')
			.gte('occurred_at', healthSince)
	]);

	for (const result of [
		accountResult,
		promoBalanceResult,
		spendableBalanceResult,
		holdResult,
		chargesResult,
		adjustmentsResult,
		reservationsResult,
		optOutResult,
		messageEventsResult
	]) {
		if (result.error) {
			console.error('Could not load the SMS usage page.', result.error);
			return json(
				{ error: 'The SMS usage could not be loaded.' },
				{ status: 500, headers: noStore }
			);
		}
	}

	const charges = (chargesResult.data ?? []) as { amount_minor: number }[];
	const adjustments = (adjustmentsResult.data ?? []) as { amount_minor: number }[];
	const reservations = (reservationsResult.data ?? []) as { segment_count: number }[];
	const events = (messageEventsResult.data ?? []) as { event_kind: string }[];
	const holdRows = (holdResult.data ?? []) as { scope: string; reason: string }[];

	const sentCount = events.filter((row) => row.event_kind === 'sent').length;
	const spendableBalanceMinor = spendableBalanceResult.data ?? 0;

	// One plain availability fact for the balance strip -- zero balance outranks a hold, since it is the
	// more actionable truth ("add credit" vs. "wait for a pause to lift"), matching Readiness in blueprint §3.
	const availability =
		spendableBalanceMinor <= 0
			? { state: 'zero_balance' as const, reason: null }
			: holdRows[0]
				? { state: 'paused' as const, reason: holdRows[0].reason }
				: { state: 'available' as const, reason: null };

	return json(
		{
			balance: safeSmsBalance(
				(accountResult.data as SmsCreditAccountRow) ?? null,
				promoBalanceResult.data ?? 0,
				spendableBalanceMinor
			),
			availability,
			usage_summary: {
				period_start: month.start,
				period_end: month.end,
				// Charge entries are negative movements against the balance; the summary reads as a plain charge.
				retail_charge_minor: charges.reduce((sum, row) => sum - row.amount_minor, 0),
				messages: reservations.length,
				segments: reservations.reduce((sum, row) => sum + row.segment_count, 0),
				adjustments_count: adjustments.length,
				adjustments_amount_minor: adjustments.reduce((sum, row) => sum + row.amount_minor, 0)
			},
			messaging_health: {
				period_days: HEALTH_WINDOW_DAYS,
				sent: sentCount,
				delivered: events.filter((row) => row.event_kind === 'delivered').length,
				failed: events.filter((row) => row.event_kind === 'send_failed').length,
				// Inbound SMS has no storage yet (Conversations SMS is a later stage) -- an honest zero, not a guess.
				received: 0,
				opt_out_rate: sentCount > 0 ? (optOutResult.count ?? 0) / sentCount : null
			}
		},
		{ headers: noStore }
	);
};
