import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runSmsPriceReconciliationCron } from './sms-price-reconciliation-cron';
import { TwilioProvisioningError } from './twilio';
import type { SmsPriceReconciliationStore } from './sms-price-reconciliation-store';

function fakeCandidate(overrides: Partial<Record<string, unknown>> = {}) {
	return {
		deliveryIntentId: 'intent-1',
		organizationId: 'org-1',
		providerMessageId: 'SM' + '0'.repeat(32),
		twilioAccountId: 'account-1',
		subaccountSid: 'AC' + '0'.repeat(32),
		priceCheckAttempts: 0,
		...overrides
	};
}

function fakeStore(candidates: ReturnType<typeof fakeCandidate>[]): SmsPriceReconciliationStore {
	return {
		listCandidates: vi.fn().mockResolvedValue(candidates),
		settle: vi.fn().mockResolvedValue(undefined),
		defer: vi.fn().mockResolvedValue(undefined)
	};
}

const resolveCredentials = vi.fn().mockResolvedValue({ apiKeySid: 'SK1', apiKeySecret: 'secret' });

describe('runSmsPriceReconciliationCron', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		resolveCredentials.mockResolvedValue({ apiKeySid: 'SK1', apiKeySecret: 'secret' });
	});

	it('returns zeroed counts when nothing is due', async () => {
		const store = fakeStore([]);
		const fetchPrice = vi.fn();
		const result = await runSmsPriceReconciliationCron(store, { resolveCredentials, fetchPrice });
		expect(result).toEqual({ checked: 0, settled: 0, stillPending: 0, escalated: 0, failed: 0 });
		expect(fetchPrice).not.toHaveBeenCalled();
	});

	it('settles a reservation once Twilio reports a price', async () => {
		const store = fakeStore([fakeCandidate()]);
		const fetchPrice = vi.fn().mockResolvedValue({
			available: true,
			priceMinor: 75,
			priceCurrency: 'USD',
			segmentCount: 1
		});

		const result = await runSmsPriceReconciliationCron(store, { resolveCredentials, fetchPrice });

		expect(result).toEqual({ checked: 1, settled: 1, stillPending: 0, escalated: 0, failed: 0 });
		expect(store.settle).toHaveBeenCalledWith({
			deliveryIntentId: 'intent-1',
			reportedSegmentCount: 1,
			reportedProviderPriceMinor: 75,
			reportedProviderPriceCurrency: 'USD'
		});
		expect(store.defer).not.toHaveBeenCalled();
	});

	it('defers a reservation whose price is not yet available, without escalating early', async () => {
		const store = fakeStore([fakeCandidate({ priceCheckAttempts: 2 })]);
		const fetchPrice = vi.fn().mockResolvedValue({ available: false });

		const result = await runSmsPriceReconciliationCron(store, { resolveCredentials, fetchPrice });

		expect(result).toEqual({ checked: 1, settled: 0, stillPending: 1, escalated: 0, failed: 0 });
		expect(store.settle).not.toHaveBeenCalled();
		expect(store.defer).toHaveBeenCalledWith({
			deliveryIntentId: 'intent-1',
			lastError: 'Twilio has not reported a price for this message yet.'
		});
	});

	it('tallies the final bounded attempt as escalated rather than still pending', async () => {
		const store = fakeStore([fakeCandidate({ priceCheckAttempts: 7 })]);
		const fetchPrice = vi.fn().mockResolvedValue({ available: false });

		const result = await runSmsPriceReconciliationCron(store, { resolveCredentials, fetchPrice });

		expect(result).toEqual({ checked: 1, settled: 0, stillPending: 0, escalated: 1, failed: 0 });
	});

	it('isolates one failing reservation instead of aborting the sweep, and still defers it', async () => {
		const store = fakeStore([
			fakeCandidate({ deliveryIntentId: 'bad' }),
			fakeCandidate({ deliveryIntentId: 'good' })
		]);
		const fetchPrice = vi
			.fn()
			.mockRejectedValueOnce(new TwilioProvisioningError('boom', 500, 'twilio_http_500', true))
			.mockResolvedValueOnce({
				available: true,
				priceMinor: 75,
				priceCurrency: 'USD',
				segmentCount: 1
			});

		const result = await runSmsPriceReconciliationCron(store, { resolveCredentials, fetchPrice });

		expect(result).toEqual({ checked: 2, settled: 1, stillPending: 0, escalated: 0, failed: 1 });
		expect(store.defer).toHaveBeenCalledWith({ deliveryIntentId: 'bad', lastError: 'boom' });
		expect(store.settle).toHaveBeenCalledTimes(1);
	});

	it('resolves credentials per reservation, scoped to its own organization and subaccount', async () => {
		const store = fakeStore([
			fakeCandidate({ organizationId: 'org-9', subaccountSid: 'AC' + '9'.repeat(32) })
		]);
		const fetchPrice = vi.fn().mockResolvedValue({
			available: true,
			priceMinor: 75,
			priceCurrency: 'USD',
			segmentCount: 1
		});

		await runSmsPriceReconciliationCron(store, { resolveCredentials, fetchPrice });

		expect(resolveCredentials).toHaveBeenCalledWith({
			organizationId: 'org-9',
			twilioAccountId: 'account-1',
			subaccountSid: 'AC' + '9'.repeat(32)
		});
	});
});
