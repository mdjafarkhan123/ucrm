import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { TrustHubResourceRole } from './trust-hub-submission-store';

// The durable-state boundary for Stage 9D's two triggers (Event Streams webhook + daily safety-net poll) that
// call syncTrustHubRegistrationStatus. Deliberately separate from TrustHubSubmissionStore (trust-hub-
// submission-store.ts): these two lookups exist only to find *which* registration an incoming Twilio event or
// a sweep pass is about, never to read or write submission data themselves.

export type TrustHubStatusTriggerStore = {
	/** Map an inbound Twilio Event Streams Brand/Campaign SID back to the UCRM registration it belongs to. Null
	 *  if no ledger row references that SID (an event for a resource this app never created, or one that
	 *  arrived before our own write landed). */
	findRegistrationIdByResourceSid(
		resourceRole: Extract<TrustHubResourceRole, 'brand_registration' | 'campaign'>,
		providerSid: string
	): Promise<string | null>;
	/** Registrations already submitted to Twilio (a brand_registration ledger row exists) whose contractor-
	 *  facing status is still `under_review` -- the daily safety-net poll's candidate set. */
	listRegistrationIdsPendingSync(): Promise<string[]>;
};

class TrustHubStatusTriggerStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'TrustHubStatusTriggerStoreError';
	}
}

export function createSupabaseTrustHubStatusTriggerStore(
	client: SupabaseClient<Database>
): TrustHubStatusTriggerStore {
	return {
		async findRegistrationIdByResourceSid(resourceRole, providerSid) {
			const { data, error } = await client
				.from('communication_sms_trust_hub_resources')
				.select('registration_id')
				.eq('resource_role', resourceRole)
				.eq('provider_sid', providerSid)
				.maybeSingle();
			if (error)
				throw new TrustHubStatusTriggerStoreError('Could not look up a Trust Hub resource by SID.');
			return data?.registration_id ?? null;
		},

		async listRegistrationIdsPendingSync() {
			const { data, error } = await client
				.from('communication_sms_trust_hub_resources')
				.select('registration_id, communication_sms_registrations!inner(status)')
				.eq('resource_role', 'brand_registration')
				.eq('communication_sms_registrations.status', 'under_review');
			if (error)
				throw new TrustHubStatusTriggerStoreError(
					'Could not list registrations pending a Trust Hub status sync.'
				);
			return (data ?? []).map((row) => row.registration_id);
		}
	};
}
