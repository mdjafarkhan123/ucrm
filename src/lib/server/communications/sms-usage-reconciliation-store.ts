import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

// The durable-state boundary for Stage 8-2's usage-window reconciliation cron. A thin wrapper over the
// Postgres commands the migration added -- the comparison itself runs in sms-usage-reconciliation-cron.ts,
// which is the only place that calls Twilio.

export type UsageReconciliationCandidate = {
	organizationId: string;
	twilioAccountId: string;
	subaccountSid: string;
	windowStart: string;
	windowEnd: string;
};

export type OurUsageTotal = {
	usageDate: string;
	messageCount: number;
	priceMinor: number;
	priceCurrency: string | null;
};

export type SmsUsageReconciliationStore = {
	listCandidates(limit: number): Promise<UsageReconciliationCandidate[]>;
	getOurTotals(input: {
		organizationId: string;
		windowStart: string;
		windowEnd: string;
	}): Promise<OurUsageTotal[]>;
	recordFinding(input: {
		organizationId: string;
		usageDate: string;
		ourMessageCount: number;
		ourPriceMinor: number;
		providerMessageCount: number;
		providerPriceMinor: number;
		priceCurrency: string;
	}): Promise<void>;
	advanceCursor(input: { organizationId: string; reconciledThrough: string }): Promise<void>;
};

class SmsUsageReconciliationStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'SmsUsageReconciliationStoreError';
	}
}

export function createSupabaseSmsUsageReconciliationStore(
	client: SupabaseClient<Database>
): SmsUsageReconciliationStore {
	return {
		async listCandidates(limit) {
			const { data, error } = await client.rpc(
				'communication_sms_list_usage_reconciliation_candidates',
				{ p_limit: limit }
			);
			if (error)
				throw new SmsUsageReconciliationStoreError(
					'Could not list usage-reconciliation candidates.'
				);
			return (data ?? []).map((row) => ({
				organizationId: row.organization_id,
				twilioAccountId: row.twilio_account_id,
				subaccountSid: row.subaccount_sid,
				windowStart: row.window_start,
				windowEnd: row.window_end
			}));
		},

		async getOurTotals(input) {
			const { data, error } = await client.rpc(
				'communication_sms_usage_reconciliation_our_totals',
				{
					p_organization_id: input.organizationId,
					p_window_start: input.windowStart,
					p_window_end: input.windowEnd
				}
			);
			if (error)
				throw new SmsUsageReconciliationStoreError('Could not read our own SMS usage totals.');
			return (data ?? []).map((row) => ({
				usageDate: row.usage_date,
				messageCount: row.message_count,
				priceMinor: row.price_minor,
				priceCurrency: row.price_currency
			}));
		},

		async recordFinding(input) {
			const { error } = await client.rpc('communication_sms_record_usage_reconciliation_finding', {
				p_organization_id: input.organizationId,
				p_usage_date: input.usageDate,
				p_our_message_count: input.ourMessageCount,
				p_our_price_minor: input.ourPriceMinor,
				p_provider_message_count: input.providerMessageCount,
				p_provider_price_minor: input.providerPriceMinor,
				p_price_currency: input.priceCurrency
			});
			if (error)
				throw new SmsUsageReconciliationStoreError(
					'Could not record a usage-reconciliation finding.'
				);
		},

		async advanceCursor(input) {
			const { error } = await client.rpc('communication_sms_advance_usage_reconciliation_cursor', {
				p_organization_id: input.organizationId,
				p_reconciled_through: input.reconciledThrough
			});
			if (error)
				throw new SmsUsageReconciliationStoreError(
					'Could not advance the usage-reconciliation cursor.'
				);
		}
	};
}
