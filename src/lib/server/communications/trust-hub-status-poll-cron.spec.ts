import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runTrustHubStatusPollCron } from './trust-hub-status-poll-cron';
import { syncTrustHubRegistrationStatus } from './trust-hub-submission';
import type { TrustHubStatusTriggerStore } from './trust-hub-status-trigger-store';
import type { TrustHubSubmissionDeps } from './trust-hub-submission';

vi.mock('./trust-hub-submission', async (importOriginal) => {
	const actual = await importOriginal<typeof import('./trust-hub-submission')>();
	return { ...actual, syncTrustHubRegistrationStatus: vi.fn() };
});

const mockedSync = vi.mocked(syncTrustHubRegistrationStatus);

function fakeTriggerStore(registrationIds: string[]): TrustHubStatusTriggerStore {
	return {
		findRegistrationIdByResourceSid: vi.fn(),
		listRegistrationIdsPendingSync: vi.fn().mockResolvedValue(registrationIds)
	};
}

const DEPS = {} as TrustHubSubmissionDeps;

describe('runTrustHubStatusPollCron', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('returns zeroed counts when nothing is pending', async () => {
		const result = await runTrustHubStatusPollCron(DEPS, fakeTriggerStore([]));
		expect(result).toEqual({
			checked: 0,
			approved: 0,
			actionNeeded: 0,
			stillPending: 0,
			failed: 0
		});
		expect(mockedSync).not.toHaveBeenCalled();
	});

	it('tallies each registration by the sync outcome it reports', async () => {
		mockedSync
			.mockResolvedValueOnce({
				registrationId: 'r1',
				brandStatus: 'APPROVED',
				campaignStatus: 'VERIFIED',
				registrationStatus: 'approved'
			})
			.mockResolvedValueOnce({
				registrationId: 'r2',
				brandStatus: 'FAILED',
				campaignStatus: null,
				registrationStatus: 'action_needed'
			})
			.mockResolvedValueOnce({
				registrationId: 'r3',
				brandStatus: 'PENDING',
				campaignStatus: null,
				registrationStatus: 'under_review'
			});

		const result = await runTrustHubStatusPollCron(DEPS, fakeTriggerStore(['r1', 'r2', 'r3']));

		expect(result).toEqual({
			checked: 3,
			approved: 1,
			actionNeeded: 1,
			stillPending: 1,
			failed: 0
		});
		expect(mockedSync).toHaveBeenCalledTimes(3);
		expect(mockedSync).toHaveBeenNthCalledWith(1, DEPS, { registrationId: 'r1' });
	});

	it('records one registration as failed and keeps checking the rest, rather than aborting the sweep', async () => {
		mockedSync.mockRejectedValueOnce(new Error('transport failure')).mockResolvedValueOnce({
			registrationId: 'r2',
			brandStatus: 'APPROVED',
			campaignStatus: 'VERIFIED',
			registrationStatus: 'approved'
		});

		const result = await runTrustHubStatusPollCron(DEPS, fakeTriggerStore(['r1', 'r2']));

		expect(result).toEqual({
			checked: 2,
			approved: 1,
			actionNeeded: 0,
			stillPending: 0,
			failed: 1
		});
	});
});
