import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';

// The durable-state boundary for the toll-free check (Stage 10 Part 4b), mirroring
// sms-number-paperwork-store.ts: the send and check flows depend on this port, never on Supabase directly, so
// tests drive them against a fake.

export type TollfreeCheckStatus = 'draft' | 'sending' | 'under_review' | 'approved' | 'needs_fix';

export type StoredTollfreeCheck = {
	id: string;
	organizationId: string;
	senderIdentityId: string;
	status: TollfreeCheckStatus;
	answers: Record<string, unknown>;
	revision: number;
	providerVerificationSid: string | null;
	submittedAt: string | null;
};

export type TollfreeCheckNumber = { phoneNumber: string; phoneNumberSid: string | null };

export type TollfreeCheckOutcome = {
	status: Exclude<TollfreeCheckStatus, 'sending'>;
	providerVerificationSid?: string | null;
	providerStatus?: string | null;
	failureReason?: string | null;
	errorCode?: number | null;
	editAllowed?: boolean | null;
	editExpiresAt?: string | null;
	/** Stamp submitted_at: the check reached carriers now. */
	submitted?: boolean;
	/** Stamp decided_at: carriers gave a new answer. */
	decided?: boolean;
};

export type TollfreeCheckEventInput = {
	organizationId: string;
	verificationId: string;
	action: string;
	actorUserId?: string | null;
	detail?: Record<string, unknown>;
};

export class TollfreeCheckStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'TollfreeCheckStoreError';
	}
}

export type TollfreeCheckStore = {
	get(
		organizationId: string,
		verificationId: string
	): Promise<{ check: StoredTollfreeCheck; number: TollfreeCheckNumber } | null>;
	/** Take the check for sending, if it is sendable and unchanged; a send left hanging 10 minutes is taken over. */
	claimSending(
		organizationId: string,
		verificationId: string,
		expectedRevision: number
	): Promise<{ token: string; previousStatus: TollfreeCheckStatus } | null>;
	/** Keep Twilio's record the moment it exists, so a crash before the end never makes a second one. */
	saveProviderSid(verificationId: string, token: string, sid: string | null): Promise<void>;
	finishSending(
		verificationId: string,
		token: string,
		outcome: TollfreeCheckOutcome
	): Promise<void>;
	recordOutcome(verificationId: string, outcome: TollfreeCheckOutcome): Promise<void>;
	recordEvent(input: TollfreeCheckEventInput): Promise<void>;
	listUnderReview(limit: number): Promise<{ id: string; organizationId: string }[]>;
	findByProviderSid(sid: string): Promise<{ id: string; organizationId: string } | null>;
};

type CheckRow = Database['public']['Tables']['communication_sms_tollfree_verifications']['Row'];

const STALE_CLAIM_MS = 10 * 60 * 1000;

function mapCheck(row: CheckRow): StoredTollfreeCheck {
	return {
		id: row.id,
		organizationId: row.organization_id,
		senderIdentityId: row.sender_identity_id,
		status: row.status as TollfreeCheckStatus,
		answers:
			row.answers && typeof row.answers === 'object' && !Array.isArray(row.answers)
				? (row.answers as Record<string, unknown>)
				: {},
		revision: row.revision,
		providerVerificationSid: row.provider_verification_sid,
		submittedAt: row.submitted_at
	};
}

function outcomeColumns(outcome: TollfreeCheckOutcome) {
	const now = new Date().toISOString();
	return {
		status: outcome.status,
		...(outcome.providerVerificationSid !== undefined
			? { provider_verification_sid: outcome.providerVerificationSid }
			: {}),
		...(outcome.providerStatus !== undefined ? { provider_status: outcome.providerStatus } : {}),
		...(outcome.failureReason !== undefined
			? { failure_reason: outcome.failureReason?.slice(0, 4000) ?? null }
			: {}),
		...(outcome.errorCode !== undefined ? { provider_error_code: outcome.errorCode } : {}),
		...(outcome.editAllowed !== undefined ? { edit_allowed: outcome.editAllowed } : {}),
		...(outcome.editExpiresAt !== undefined ? { edit_expires_at: outcome.editExpiresAt } : {}),
		...(outcome.submitted ? { submitted_at: now } : {}),
		...(outcome.decided ? { decided_at: now } : {}),
		last_checked_at: now,
		updated_at: now
	};
}

export function createSupabaseTollfreeCheckStore(
	client: SupabaseClient<Database>
): TollfreeCheckStore {
	const table = () => client.from('communication_sms_tollfree_verifications');
	return {
		async get(organizationId, verificationId) {
			const { data, error } = await table()
				.select('*')
				.eq('organization_id', organizationId)
				.eq('id', verificationId)
				.maybeSingle();
			if (error) throw new TollfreeCheckStoreError('Could not read the toll-free check.');
			if (!data) return null;
			const { data: sender, error: senderError } = await client
				.from('communication_sms_sender_identities')
				.select('phone_number, provider_phone_number_sid')
				.eq('organization_id', organizationId)
				.eq('id', data.sender_identity_id)
				.maybeSingle();
			if (senderError || !sender)
				throw new TollfreeCheckStoreError('Could not read the toll-free number.');
			return {
				check: mapCheck(data),
				number: {
					phoneNumber: sender.phone_number,
					phoneNumberSid: sender.provider_phone_number_sid
				}
			};
		},

		async claimSending(organizationId, verificationId, expectedRevision) {
			const { data: current, error: readError } = await table()
				.select('status, submitted_at, sending_claimed_at')
				.eq('organization_id', organizationId)
				.eq('id', verificationId)
				.maybeSingle();
			if (readError) throw new TollfreeCheckStoreError('Could not read the toll-free check.');
			if (!current) return null;

			const stale =
				current.status === 'sending' &&
				current.sending_claimed_at !== null &&
				Date.parse(current.sending_claimed_at) <= Date.now() - STALE_CLAIM_MS;
			if (current.status !== 'draft' && current.status !== 'needs_fix' && !stale) return null;
			const previousStatus: TollfreeCheckStatus = stale
				? current.submitted_at
					? 'needs_fix'
					: 'draft'
				: (current.status as TollfreeCheckStatus);

			const token = crypto.randomUUID();
			let query = table()
				.update({
					status: 'sending',
					sending_claim_token: token,
					sending_claimed_at: new Date().toISOString(),
					updated_at: new Date().toISOString()
				})
				.eq('organization_id', organizationId)
				.eq('id', verificationId)
				.eq('revision', expectedRevision)
				.eq('status', current.status);
			// Only the claim that was read may be taken over, so two rescuers of one stale send cannot both win.
			query = current.sending_claimed_at
				? query.eq('sending_claimed_at', current.sending_claimed_at)
				: query.is('sending_claimed_at', null);
			const { data, error } = await query.select('id').maybeSingle();
			if (error) throw new TollfreeCheckStoreError('Could not start sending the toll-free check.');
			return data ? { token, previousStatus } : null;
		},

		async saveProviderSid(verificationId, token, sid) {
			const { error } = await table()
				.update({ provider_verification_sid: sid, updated_at: new Date().toISOString() })
				.eq('id', verificationId)
				.eq('sending_claim_token', token);
			if (error) throw new TollfreeCheckStoreError('Could not keep the toll-free check record.');
		},

		async finishSending(verificationId, token, outcome) {
			const { error } = await table()
				.update({
					...outcomeColumns(outcome),
					sending_claim_token: null,
					sending_claimed_at: null
				})
				.eq('id', verificationId)
				.eq('sending_claim_token', token);
			if (error) throw new TollfreeCheckStoreError('Could not finish sending the toll-free check.');
		},

		async recordOutcome(verificationId, outcome) {
			const { error } = await table()
				.update(outcomeColumns(outcome))
				.eq('id', verificationId)
				.neq('status', 'sending');
			if (error) throw new TollfreeCheckStoreError('Could not record the toll-free check outcome.');
		},

		async recordEvent(input) {
			const { error } = await client.from('communication_sms_tollfree_verification_events').insert({
				organization_id: input.organizationId,
				verification_id: input.verificationId,
				action: input.action,
				actor_user_id: input.actorUserId ?? null,
				detail: (input.detail ?? {}) as Json
			});
			// History is best-effort observability: a failed insert must never mask the outcome.
			if (error)
				console.error('Failed to record a toll-free check event', { action: input.action });
		},

		async listUnderReview(limit) {
			const { data, error } = await table()
				.select('id, organization_id')
				.eq('status', 'under_review')
				.order('last_checked_at', { ascending: true, nullsFirst: true })
				.limit(limit);
			if (error) throw new TollfreeCheckStoreError('Could not list toll-free checks under review.');
			return (data ?? []).map((row) => ({ id: row.id, organizationId: row.organization_id }));
		},

		async findByProviderSid(sid) {
			const { data, error } = await table()
				.select('id, organization_id')
				.eq('provider_verification_sid', sid)
				.maybeSingle();
			if (error) throw new TollfreeCheckStoreError('Could not find the toll-free check.');
			return data ? { id: data.id, organizationId: data.organization_id } : null;
		}
	};
}
