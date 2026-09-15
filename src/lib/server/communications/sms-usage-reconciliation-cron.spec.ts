import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runSmsUsageReconciliationCron } from './sms-usage-reconciliation-cron';
import { TwilioProvisioningError } from './twilio';
import type { SmsUsageReconciliationStore } from './sms-usage-reconciliation-store';

function fakeCandidate(overrides: Partial<Record<string, unknown>> = {}) {
	return {
		organizationId: 'org-1',
		twilioAccountId: 'account-1',
		subaccountSid: 'AC' + '0'.repeat(32),
		windowStart: '2026-09-10',
		windowEnd: '2026-09-11',
		...overrides
	};
}

function fakeStore(candidates: ReturnType<typeof fakeCandidate>[]): SmsUsageReconciliationStore {
	return {
		listCandidates: vi.fn().mockResolvedValue(candidates),
		getOurTotals: vi.fn().mockResolvedValue([]),
		recordFinding: vi.fn().mockResolvedValue(undefined),
		advanceCursor: vi.fn().mockResolvedValue(undefined)
	};
}

const resolveCredentials = vi.fn().mockResolvedValue({ apiKeySid: 'SK1', apiKeySecret: 'secret' });

describe('runSmsUsageReconciliationCron', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		resolveCredentials.mockResolvedValue({ apiKeySid: 'SK1', apiKeySecret: 'secret' });
	});

	it('returns zeroed counts when no organization is due', async () => {
		const store = fakeStore([]);
		const fetchUsageRecords = vi.fn();
		const result = await runSmsUsageReconciliationCron(store, {
			resolveCredentials,
			fetchUsageRecords
		});
		expect(result).toEqual({
			organizationsChecked: 0,
			daysChecked: 0,
			matched: 0,
			drifted: 0,
			failed: 0
		});
		expect(fetchUsageRecords).not.toHaveBeenCalled();
	});

	it('records a matched finding for each day when our totals equal Twilio’s', async () => {
		const store = fakeStore([fakeCandidate()]);
		vi.mocked(store.getOurTotals).mockResolvedValue([
			{ usageDate: '2026-09-10', messageCount: 3, priceMinor: 210, priceCurrency: 'USD' },
			{ usageDate: '2026-09-11', messageCount: 1, priceMinor: 70, priceCurrency: 'USD' }
		]);
		const fetchUsageRecords = vi.fn().mockResolvedValue([
			{ usageDate: '2026-09-10', messageCount: 3, priceMinor: 210, priceCurrency: 'USD' },
			{ usageDate: '2026-09-11', messageCount: 1, priceMinor: 70, priceCurrency: 'USD' }
		]);

		const result = await runSmsUsageReconciliationCron(store, {
			resolveCredentials,
			fetchUsageRecords
		});

		expect(result).toEqual({
			organizationsChecked: 1,
			daysChecked: 2,
			matched: 2,
			drifted: 0,
			failed: 0
		});
		expect(store.recordFinding).toHaveBeenCalledWith({
			organizationId: 'org-1',
			usageDate: '2026-09-10',
			ourMessageCount: 3,
			ourPriceMinor: 210,
			providerMessageCount: 3,
			providerPriceMinor: 210,
			priceCurrency: 'USD'
		});
		expect(store.advanceCursor).toHaveBeenCalledWith({
			organizationId: 'org-1',
			reconciledThrough: '2026-09-11'
		});
	});

	it('flags a day as drift when Twilio reports more messages than we settled', async () => {
		const store = fakeStore([
			fakeCandidate({ windowStart: '2026-09-10', windowEnd: '2026-09-10' })
		]);
		vi.mocked(store.getOurTotals).mockResolvedValue([
			{ usageDate: '2026-09-10', messageCount: 2, priceMinor: 140, priceCurrency: 'USD' }
		]);
		const fetchUsageRecords = vi
			.fn()
			.mockResolvedValue([
				{ usageDate: '2026-09-10', messageCount: 3, priceMinor: 210, priceCurrency: 'USD' }
			]);

		const result = await runSmsUsageReconciliationCron(store, {
			resolveCredentials,
			fetchUsageRecords
		});

		expect(result).toEqual({
			organizationsChecked: 1,
			daysChecked: 1,
			matched: 0,
			drifted: 1,
			failed: 0
		});
		expect(store.recordFinding).toHaveBeenCalledWith({
			organizationId: 'org-1',
			usageDate: '2026-09-10',
			ourMessageCount: 2,
			ourPriceMinor: 140,
			providerMessageCount: 3,
			providerPriceMinor: 210,
			priceCurrency: 'USD'
		});
	});

	it('treats a day Twilio never reported as zero, still flagging our own untracked spend as drift', async () => {
		const store = fakeStore([
			fakeCandidate({ windowStart: '2026-09-10', windowEnd: '2026-09-10' })
		]);
		vi.mocked(store.getOurTotals).mockResolvedValue([
			{ usageDate: '2026-09-10', messageCount: 1, priceMinor: 70, priceCurrency: 'USD' }
		]);
		const fetchUsageRecords = vi.fn().mockResolvedValue([]);

		const result = await runSmsUsageReconciliationCron(store, {
			resolveCredentials,
			fetchUsageRecords
		});

		expect(result.drifted).toBe(1);
		expect(store.recordFinding).toHaveBeenCalledWith(
			expect.objectContaining({
				providerMessageCount: 0,
				providerPriceMinor: 0,
				priceCurrency: 'USD'
			})
		);
	});

	it('isolates one failing organization instead of aborting the sweep, and never advances its cursor', async () => {
		const store = fakeStore([
			fakeCandidate({ organizationId: 'bad-org' }),
			fakeCandidate({ organizationId: 'good-org' })
		]);
		vi.mocked(store.getOurTotals).mockResolvedValue([]);
		const fetchUsageRecords = vi
			.fn()
			.mockRejectedValueOnce(new TwilioProvisioningError('boom', 500, 'twilio_http_500', true))
			.mockResolvedValueOnce([]);

		const result = await runSmsUsageReconciliationCron(store, {
			resolveCredentials,
			fetchUsageRecords
		});

		expect(result).toEqual({
			organizationsChecked: 2,
			daysChecked: 2,
			matched: 2,
			drifted: 0,
			failed: 1
		});
		expect(store.advanceCursor).toHaveBeenCalledTimes(1);
		expect(store.advanceCursor).toHaveBeenCalledWith(
			expect.objectContaining({ organizationId: 'good-org' })
		);
	});

	it('resolves credentials per organization, scoped to its own subaccount', async () => {
		const store = fakeStore([
			fakeCandidate({ organizationId: 'org-9', subaccountSid: 'AC' + '9'.repeat(32) })
		]);
		vi.mocked(store.getOurTotals).mockResolvedValue([]);
		const fetchUsageRecords = vi.fn().mockResolvedValue([]);

		await runSmsUsageReconciliationCron(store, { resolveCredentials, fetchUsageRecords });

		expect(resolveCredentials).toHaveBeenCalledWith({
			organizationId: 'org-9',
			twilioAccountId: 'account-1',
			subaccountSid: 'AC' + '9'.repeat(32)
		});
	});
});
