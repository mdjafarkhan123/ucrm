import {
	syncTrustHubRegistrationStatus,
	type TrustHubSubmissionDeps
} from './trust-hub-submission';
import type { TrustHubStatusTriggerStore } from './trust-hub-status-trigger-store';

export type TrustHubStatusPollResult = {
	checked: number;
	approved: number;
	actionNeeded: number;
	stillPending: number;
	failed: number;
};

/**
 * Stage 9D's safety net behind the Trust Hub Event Streams webhook: re-checks every registration Twilio
 * hasn't yet resolved, in case a push notification was ever missed, delayed past Event Streams' four-hour
 * queue window, or the webhook subscription simply isn't set up yet. One syncTrustHubRegistrationStatus call
 * per registration; a single registration's failure is logged and skipped rather than aborting the rest of
 * the sweep, mirroring runOrganizationClosureCron's per-item isolation.
 */
export async function runTrustHubStatusPollCron(
	deps: TrustHubSubmissionDeps,
	triggerStore: TrustHubStatusTriggerStore
): Promise<TrustHubStatusPollResult> {
	const registrationIds = await triggerStore.listRegistrationIdsPendingSync();
	const result: TrustHubStatusPollResult = {
		checked: 0,
		approved: 0,
		actionNeeded: 0,
		stillPending: 0,
		failed: 0
	};

	for (const registrationId of registrationIds) {
		result.checked += 1;
		try {
			const outcome = await syncTrustHubRegistrationStatus(deps, { registrationId });
			if (outcome.registrationStatus === 'approved') result.approved += 1;
			else if (outcome.registrationStatus === 'action_needed') result.actionNeeded += 1;
			else result.stillPending += 1;
		} catch (error) {
			result.failed += 1;
			console.error('Trust Hub status poll failed for one registration.', {
				registrationId,
				error: error instanceof Error ? error.message : error
			});
		}
	}

	return result;
}
