import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import {
	smsRegistrationAnswersSchema,
	type SmsRegistrationAnswers
} from '$lib/server/validation/communications-sms-registration.schema';

// The durable-state boundary for the Trust Hub submission saga (A2 Stage 9B), mirroring
// twilio-provisioning-store.ts: the saga depends on this port, never on Supabase directly, so it is driven in
// tests against an in-memory fake. Wraps the Stage 9A ledger tables (communication_sms_trust_hub_resources /
// _events) plus a read of the contractor's latest attested submission, which is the saga's only source of the
// business data it forwards to Twilio.

export type TrustHubResourceRole =
	| 'customer_profile'
	| 'end_user_business_information'
	| 'end_user_authorized_representative'
	| 'supporting_document_address'
	| 'end_user_a2p_messaging_profile'
	| 'a2p_trust_product'
	| 'brand_registration'
	| 'campaign';

export type TrustHubResourceStatus =
	'pending' | 'created' | 'submitted' | 'approved' | 'rejected' | 'failed';

export type StoredTrustHubResource = {
	id: string;
	registrationId: string;
	resourceRole: TrustHubResourceRole;
	providerSid: string | null;
	providerStatus: string | null;
	status: TrustHubResourceStatus;
	failureReason: string | null;
};

export type RegistrationSubmissionForSaga = {
	registrationId: string;
	organizationId: string;
	countryCode: string;
	senderType: string;
	answers: SmsRegistrationAnswers;
};

export type TrustHubEventInput = {
	organizationId: string;
	registrationId: string;
	resourceRole?: TrustHubResourceRole | null;
	operation: 'submit_registration' | 'sync_status';
	step: string;
	result: 'succeeded' | 'skipped' | 'rolled_back' | 'needs_review' | 'failed';
	detail?: Record<string, unknown>;
};

export type UpsertResourceInput = {
	organizationId: string;
	registrationId: string;
	resourceRole: TrustHubResourceRole;
	providerSid?: string | null;
	providerStatus?: string | null;
	status: TrustHubResourceStatus;
	failureReason?: string | null;
};

export type TrustHubSubmissionStore = {
	/** The registration's most recently attested submission -- the only business data the saga is allowed to
	 *  forward to Twilio. Null if the registration has never been submitted by the contractor yet. */
	getLatestSubmission(registrationId: string): Promise<RegistrationSubmissionForSaga | null>;
	getResource(
		registrationId: string,
		resourceRole: TrustHubResourceRole
	): Promise<StoredTrustHubResource | null>;
	/** Create-or-update the single row for (registrationId, resourceRole); never a second row for the same role. */
	upsertResource(input: UpsertResourceInput): Promise<StoredTrustHubResource>;
	recordEvent(input: TrustHubEventInput): Promise<void>;
};

class TrustHubSubmissionStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'TrustHubSubmissionStoreError';
	}
}

type ResourceRow = Database['public']['Tables']['communication_sms_trust_hub_resources']['Row'];

function mapResource(row: ResourceRow): StoredTrustHubResource {
	return {
		id: row.id,
		registrationId: row.registration_id,
		resourceRole: row.resource_role as TrustHubResourceRole,
		providerSid: row.provider_sid,
		providerStatus: row.provider_status,
		status: row.status as TrustHubResourceStatus,
		failureReason: row.failure_reason
	};
}

export function createSupabaseTrustHubSubmissionStore(
	client: SupabaseClient<Database>
): TrustHubSubmissionStore {
	return {
		async getLatestSubmission(registrationId) {
			const { data: registration, error: registrationError } = await client
				.from('communication_sms_registrations')
				.select('organization_id, country_code, sender_type')
				.eq('id', registrationId)
				.maybeSingle();
			if (registrationError) {
				throw new TrustHubSubmissionStoreError('Could not read the registration.');
			}
			if (!registration) return null;

			const { data: submission, error: submissionError } = await client
				.from('communication_sms_registration_submissions')
				.select('answers')
				.eq('registration_id', registrationId)
				.order('submission_number', { ascending: false })
				.limit(1)
				.maybeSingle();
			if (submissionError) {
				throw new TrustHubSubmissionStoreError(
					'Could not read the latest registration submission.'
				);
			}
			if (!submission) return null;

			const parsed = smsRegistrationAnswersSchema.safeParse(submission.answers);
			if (!parsed.success) {
				throw new TrustHubSubmissionStoreError(
					'The stored registration submission no longer matches the expected answer shape.'
				);
			}

			return {
				registrationId,
				organizationId: registration.organization_id,
				countryCode: registration.country_code,
				senderType: registration.sender_type,
				answers: parsed.data
			};
		},

		async getResource(registrationId, resourceRole) {
			const { data, error } = await client
				.from('communication_sms_trust_hub_resources')
				.select('*')
				.eq('registration_id', registrationId)
				.eq('resource_role', resourceRole)
				.maybeSingle();
			if (error) throw new TrustHubSubmissionStoreError('Could not read a Trust Hub resource.');
			return data ? mapResource(data) : null;
		},

		async upsertResource(input) {
			const { data, error } = await client
				.from('communication_sms_trust_hub_resources')
				.upsert(
					{
						organization_id: input.organizationId,
						registration_id: input.registrationId,
						resource_role: input.resourceRole,
						provider_sid: input.providerSid ?? null,
						provider_status: input.providerStatus ?? null,
						status: input.status,
						failure_reason: input.failureReason ?? null,
						updated_at: new Date().toISOString()
					},
					{ onConflict: 'registration_id,resource_role' }
				)
				.select('*')
				.single();
			if (error) throw new TrustHubSubmissionStoreError('Could not store a Trust Hub resource.');
			return mapResource(data as ResourceRow);
		},

		async recordEvent(input) {
			const { error } = await client.from('communication_sms_trust_hub_events').insert({
				organization_id: input.organizationId,
				registration_id: input.registrationId,
				resource_role: input.resourceRole ?? null,
				operation: input.operation,
				step: input.step,
				result: input.result,
				detail: (input.detail ?? {}) as Json
			});
			// History is best-effort observability: a failed audit insert must never mask the submission outcome.
			if (error) console.error('Failed to record Trust Hub submission event', { step: input.step });
		}
	};
}
