import type { SupabaseClient } from '@supabase/supabase-js';
import { createSupabaseTrustHubSubmissionStore } from './trust-hub-submission-store';
import { createTwilioTrustHubClient } from './twilio-trust-hub';
import { createSupabaseTrustHubStatusTriggerStore } from './trust-hub-status-trigger-store';
import { runTrustHubStatusPollCron } from './trust-hub-status-poll-cron';
import { createNumberPaperworkDeps, runPaperworkStatusCheck } from './sms-number-paperwork';
import { createTollfreeCheckDeps, runTollfreeStatusCheck } from './sms-tollfree-verification';
import { reconcileAllSenderReadiness } from './sms-number-readiness';

/**
 * Asks Twilio about everything it is still reviewing: US texting registrations, number paperwork and toll-free
 * checks, then switches on every number whose approval has now passed. The daily safety net behind Twilio's
 * webhooks runs it, and so does Check now on Texting setup's Waiting on Twilio tab. A failed paperwork or
 * toll-free sweep never hides the registration result.
 */
export async function runTwilioReviewChecks(client: SupabaseClient) {
	const result = await runTrustHubStatusPollCron(
		{
			store: createSupabaseTrustHubSubmissionStore(client),
			twilio: createTwilioTrustHubClient()
		},
		createSupabaseTrustHubStatusTriggerStore(client)
	);
	const paperwork = await runPaperworkStatusCheck(createNumberPaperworkDeps()).catch((error) => {
		console.error('The number paperwork status check failed.', error);
		return { failed: true };
	});
	const tollfree = await runTollfreeStatusCheck(createTollfreeCheckDeps()).catch((error) => {
		console.error('The toll-free status check failed.', error);
		return { failed: true };
	});
	const numbers = await reconcileAllSenderReadiness(client);
	return { ...result, paperwork, tollfree, numbers };
}
