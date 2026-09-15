import { fetchTwilioMessagePrice, TwilioProvisioningError } from './twilio';
import type { SmsPriceReconciliationStore } from './sms-price-reconciliation-store';
import { defaultResolveSmsCredentials, type ResolveSmsCredentials } from './sms-worker';

export type SmsPriceReconciliationResult = {
	checked: number;
	settled: number;
	stillPending: number;
	escalated: number;
	failed: number;
};

/**
 * Stage 8 part 1: the poll that finally settles an SMS credit reservation. Twilio's status callback never
 * carries a final price, so this fetches each candidate's Message resource directly, settles it when a price
 * is available, or defers (with backoff, then escalation) when it is not yet -- mirroring
 * runTrustHubStatusPollCron's per-item isolation so one bad row never aborts the sweep.
 */
export async function runSmsPriceReconciliationCron(
	store: SmsPriceReconciliationStore,
	dependencies: {
		resolveCredentials?: ResolveSmsCredentials;
		fetchPrice?: typeof fetchTwilioMessagePrice;
	} = {}
): Promise<SmsPriceReconciliationResult> {
	const resolveCredentials = dependencies.resolveCredentials ?? defaultResolveSmsCredentials;
	const fetchPrice = dependencies.fetchPrice ?? fetchTwilioMessagePrice;

	const candidates = await store.listCandidates(100);
	const result: SmsPriceReconciliationResult = {
		checked: 0,
		settled: 0,
		stillPending: 0,
		escalated: 0,
		failed: 0
	};

	for (const candidate of candidates) {
		result.checked += 1;
		try {
			const credentials = await resolveCredentials({
				organizationId: candidate.organizationId,
				twilioAccountId: candidate.twilioAccountId,
				subaccountSid: candidate.subaccountSid
			});

			const price = await fetchPrice({
				subaccountSid: candidate.subaccountSid,
				messageSid: candidate.providerMessageId,
				apiKeySid: credentials.apiKeySid,
				apiKeySecret: credentials.apiKeySecret
			});

			if (price.available) {
				await store.settle({
					deliveryIntentId: candidate.deliveryIntentId,
					reportedSegmentCount: price.segmentCount,
					reportedProviderPriceMinor: price.priceMinor,
					reportedProviderPriceCurrency: price.priceCurrency
				});
				result.settled += 1;
			} else {
				// Tally only -- the SQL side (communication_sms_defer_price_reconciliation's own max_attempts)
				// is the authority on when a reservation actually escalates to a reconciliation item.
				const escalating = candidate.priceCheckAttempts + 1 >= 8;
				await store.defer({
					deliveryIntentId: candidate.deliveryIntentId,
					lastError: 'Twilio has not reported a price for this message yet.'
				});
				if (escalating) result.escalated += 1;
				else result.stillPending += 1;
			}
		} catch (error) {
			result.failed += 1;
			const message = error instanceof TwilioProvisioningError ? error.message : 'Unknown error.';
			console.error('SMS price reconciliation failed for one reservation.', {
				deliveryIntentId: candidate.deliveryIntentId,
				error: error instanceof Error ? error.message : error
			});
			try {
				await store.defer({ deliveryIntentId: candidate.deliveryIntentId, lastError: message });
			} catch (deferError) {
				console.error('Could not even defer a failed SMS price-reconciliation check.', {
					deliveryIntentId: candidate.deliveryIntentId,
					error: deferError instanceof Error ? deferError.message : deferError
				});
			}
		}
	}

	return result;
}
