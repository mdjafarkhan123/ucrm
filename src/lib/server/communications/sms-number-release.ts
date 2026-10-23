import { createTwilioNumberPurchaseClient, type TwilioNumberPurchaseClient } from './twilio';
import {
	createTwilioProvisioningDeps,
	getSubaccountAccess,
	type SubaccountAccess
} from './twilio-provisioning';
import type { CommunicationWorkerClient } from './sms-worker';

// Stage 10 Part 7: a number whose 14-day grace ran out is let go. The release is recorded here first, so a top-up
// confirmed a moment later finds nothing unpaid to pay; only then is Twilio asked to let the number go. A Twilio
// failure leaves the number on the due list and the next wake tries again, until Twilio confirms.

type DueRelease = {
	sender_id: string;
	organization_id: string;
	phone_number: string;
	provider_phone_number_sid: string | null;
};

export type NumberReleaseDeps = {
	client: CommunicationWorkerClient;
	twilio?: Pick<TwilioNumberPurchaseClient, 'findOwnedPhoneNumber' | 'releasePhoneNumber'>;
	subaccount?: (organizationId: string) => Promise<SubaccountAccess | null>;
};

export type NumberReleaseResult = { released: number; kept: number; failed: number };

export async function releaseDueNumbers(deps: NumberReleaseDeps): Promise<NumberReleaseResult> {
	// Built only when a number is due, so an idle wake never touches Twilio settings.
	let twilio = deps.twilio;
	const subaccount =
		deps.subaccount ??
		((organizationId: string) =>
			getSubaccountAccess(createTwilioProvisioningDeps(), organizationId));
	const result: NumberReleaseResult = { released: 0, kept: 0, failed: 0 };

	const due = await deps.client.rpc('communication_sms_due_number_releases', { p_limit: 10 });
	if (due.error) throw new Error(`Could not read numbers to release: ${due.error.message}`);

	for (const row of (due.data as DueRelease[] | null) ?? []) {
		try {
			const recorded = await deps.client.rpc('communication_sms_record_number_released', {
				p_sender_id: row.sender_id
			});
			if (recorded.error) throw new Error(recorded.error.message);
			// A top-up paid it first: the number stays.
			if (recorded.data === 'kept') {
				result.kept += 1;
				continue;
			}

			const access = await subaccount(row.organization_id);
			if (!access) throw new Error('The business has no ready Twilio subaccount.');
			twilio ??= createTwilioNumberPurchaseClient(createTwilioProvisioningDeps().twilio);
			const auth = { subaccountSid: access.subaccountSid, subaccountAuthToken: access.authToken };
			const phoneNumberSid =
				row.provider_phone_number_sid ??
				(await twilio.findOwnedPhoneNumber({ ...auth, phoneNumber: row.phone_number }))
					?.phoneNumberSid;
			// Twilio no longer has it: nothing left to let go.
			if (phoneNumberSid) await twilio.releasePhoneNumber({ ...auth, phoneNumberSid });

			const confirmed = await deps.client.rpc('communication_sms_record_number_provider_released', {
				p_sender_id: row.sender_id
			});
			if (confirmed.error) throw new Error(confirmed.error.message);
			result.released += 1;
		} catch (error) {
			// Never log the error object itself: a provider error can carry request details.
			console.error('Could not release an SMS number; the next wake retries it.', {
				senderId: row.sender_id,
				reason: error instanceof Error ? error.message : 'unknown'
			});
			result.failed += 1;
		}
	}
	return result;
}
