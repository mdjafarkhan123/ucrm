import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

// The durable-state boundary for Stage 8's price-reconciliation cron. A thin wrapper over the three
// Postgres commands the migration added -- the money logic itself lives in the database, not here.

export type PriceReconciliationCandidate = {
	deliveryIntentId: string;
	organizationId: string;
	providerMessageId: string;
	twilioAccountId: string;
	subaccountSid: string;
	priceCheckAttempts: number;
};

export type SmsPriceReconciliationStore = {
	listCandidates(limit: number): Promise<PriceReconciliationCandidate[]>;
	settle(input: {
		deliveryIntentId: string;
		reportedSegmentCount: number;
		reportedProviderPriceMinor: number;
		reportedProviderPriceCurrency: string;
	}): Promise<void>;
	defer(input: { deliveryIntentId: string; lastError?: string }): Promise<void>;
};

class SmsPriceReconciliationStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'SmsPriceReconciliationStoreError';
	}
}

export function createSupabaseSmsPriceReconciliationStore(
	client: SupabaseClient<Database>
): SmsPriceReconciliationStore {
	return {
		async listCandidates(limit) {
			const { data, error } = await client.rpc(
				'communication_sms_list_price_reconciliation_candidates',
				{ p_limit: limit }
			);
			if (error)
				throw new SmsPriceReconciliationStoreError(
					'Could not list price-reconciliation candidates.'
				);
			return (data ?? []).map((row) => ({
				deliveryIntentId: row.delivery_intent_id,
				organizationId: row.organization_id,
				providerMessageId: row.provider_message_id,
				twilioAccountId: row.twilio_account_id,
				subaccountSid: row.subaccount_sid,
				priceCheckAttempts: row.price_check_attempts
			}));
		},

		async settle(input) {
			const { error } = await client.rpc('communication_sms_settle_reservation_price', {
				p_delivery_intent_id: input.deliveryIntentId,
				p_reported_segment_count: input.reportedSegmentCount,
				p_reported_provider_price_minor: input.reportedProviderPriceMinor,
				p_reported_provider_price_currency: input.reportedProviderPriceCurrency
			});
			if (error)
				throw new SmsPriceReconciliationStoreError('Could not settle an SMS credit reservation.');
		},

		async defer(input) {
			const { error } = await client.rpc('communication_sms_defer_price_reconciliation', {
				p_delivery_intent_id: input.deliveryIntentId,
				p_last_error: input.lastError
			});
			if (error)
				throw new SmsPriceReconciliationStoreError(
					'Could not defer an SMS price-reconciliation check.'
				);
		}
	};
}
