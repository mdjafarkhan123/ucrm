import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import type {
	EndUserType,
	PaperworkAddress,
	PaperworkFix,
	PaperworkStatus
} from '$lib/communications/number-paperwork';
import type { NumberType } from './twilio-country-catalog';

// The durable-state boundary for number paperwork (Stage 10 Part 3), mirroring trust-hub-submission-store.ts:
// the send and check flows depend on this port, never on Supabase directly, so tests drive them against a fake.

export type StoredPaperwork = {
	id: string;
	organizationId: string;
	countryCode: string;
	numberType: NumberType;
	endUserType: EndUserType;
	status: PaperworkStatus;
	answers: Record<string, string>;
	address: PaperworkAddress | null;
	documentChoices: Record<string, string>;
	revision: number;
	regulationSid: string | null;
	providerAddressSid: string | null;
	providerEndUserSid: string | null;
	providerBundleSid: string | null;
	providerStatus: string | null;
	failureReason: string | null;
	fixes: PaperworkFix[];
	validUntil: string | null;
	submittedAt: string | null;
	decidedAt: string | null;
	updatedAt: string;
	createdAt: string;
};

export type StoredPaperworkDocument = {
	id: string;
	documentType: string;
	protectedDocumentId: string | null;
	fields: Record<string, string>;
	providerDocumentSid: string | null;
	providerProtectedDocumentId: string | null;
	providerFields: Record<string, unknown> | null;
	providerStatus: string | null;
	failureReason: string | null;
};

export type StoredPaperworkFile = {
	id: string;
	objectKey: string | null;
	displayName: string;
	mimeType: string;
	sizeBytes: number;
	state: 'uploading' | 'checking' | 'ready' | 'refused' | 'deleted';
	problem: string | null;
};

export type SendingClaim = {
	paperwork: StoredPaperwork;
	token: string;
	previousStatus: PaperworkStatus;
};

export type ProviderPatch = Partial<
	Pick<
		StoredPaperwork,
		| 'regulationSid'
		| 'providerAddressSid'
		| 'providerEndUserSid'
		| 'providerBundleSid'
		| 'providerStatus'
	>
>;

export type PaperworkOutcome = {
	status: Exclude<PaperworkStatus, 'sending'>;
	providerStatus?: string | null;
	failureReason?: string | null;
	fixes?: PaperworkFix[];
	validUntil?: string | null;
	submitted?: boolean;
	decided?: boolean;
};

export type PaperworkEventInput = {
	organizationId: string;
	paperworkId: string;
	action: string;
	actorUserId?: string | null;
	detail?: Record<string, unknown>;
};

export class PaperworkStoreError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'PaperworkStoreError';
	}
}

export type NumberPaperworkStore = {
	get(
		organizationId: string,
		paperworkId: string
	): Promise<{ paperwork: StoredPaperwork; documents: StoredPaperworkDocument[] } | null>;
	/** Move a draft or a set needing a fix to `sending`, if its revision is still the one the business saw. A
	 *  send that died part-way frees its claim after ten minutes. Null when another send holds it or it moved on. */
	claimSending(
		organizationId: string,
		paperworkId: string,
		expectedRevision: number
	): Promise<SendingClaim | null>;
	/** Record the Twilio records made so far, while the claim is held. */
	saveProvider(paperworkId: string, token: string, patch: ProviderPatch): Promise<void>;
	saveDocumentProvider(
		documentId: string,
		patch: {
			providerDocumentSid: string;
			providerProtectedDocumentId: string | null;
			providerFields: Record<string, unknown>;
			providerStatus: string | null;
		}
	): Promise<void>;
	/** End the send with its outcome and free the claim. */
	finishSending(paperworkId: string, token: string, outcome: PaperworkOutcome): Promise<void>;
	/** Record what Twilio says about a set it has. Never touches a set being sent. */
	recordOutcome(paperworkId: string, outcome: PaperworkOutcome): Promise<void>;
	recordDocumentReview(
		documentId: string,
		review: { providerStatus: string | null; failureReason: string | null }
	): Promise<void>;
	recordEvent(input: PaperworkEventInput): Promise<void>;
	findByBundleSid(bundleSid: string): Promise<{ id: string; organizationId: string } | null>;
	/** Sets Twilio is reviewing, least recently checked first. */
	listUnderReview(limit: number): Promise<{ id: string; organizationId: string }[]>;
	findApproved(input: {
		organizationId: string;
		countryCode: string;
		numberType: NumberType;
	}): Promise<{ bundleSid: string | null; addressSid: string | null } | null>;
	readFile(
		organizationId: string,
		protectedDocumentId: string
	): Promise<StoredPaperworkFile | null>;
	scheduleFileDeletion(paperworkId: string): Promise<void>;
};

type PaperworkRow = Database['public']['Tables']['communication_sms_number_paperwork']['Row'];
type DocumentRow =
	Database['public']['Tables']['communication_sms_number_paperwork_documents']['Row'];

const STALE_CLAIM_MS = 10 * 60 * 1000;

function stringRecord(value: Json | null): Record<string, string> {
	const out: Record<string, string> = {};
	if (value && typeof value === 'object' && !Array.isArray(value)) {
		for (const [key, item] of Object.entries(value)) if (typeof item === 'string') out[key] = item;
	}
	return out;
}

function readAddress(value: Json | null): PaperworkAddress | null {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
	const raw = stringRecord(value);
	return {
		customer_name: raw.customer_name ?? '',
		street: raw.street ?? '',
		street_secondary: raw.street_secondary ?? '',
		city: raw.city ?? '',
		region: raw.region ?? '',
		postal_code: raw.postal_code ?? '',
		country_code: raw.country_code ?? ''
	};
}

function readFixes(value: Json | null): PaperworkFix[] {
	if (!Array.isArray(value)) return [];
	return value.flatMap((row) => {
		if (!row || typeof row !== 'object' || Array.isArray(row)) return [];
		const raw = stringRecord(row);
		const step = raw.step === 'documents' ? 'documents' : 'details';
		return raw.reason
			? [{ step, target: raw.target ?? '', label: raw.label ?? '', reason: raw.reason }]
			: [];
	});
}

export function mapPaperwork(row: PaperworkRow): StoredPaperwork {
	return {
		id: row.id,
		organizationId: row.organization_id,
		countryCode: row.country_code,
		numberType: row.number_type as NumberType,
		endUserType: row.end_user_type as EndUserType,
		status: row.status as PaperworkStatus,
		answers: stringRecord(row.answers),
		address: readAddress(row.address),
		documentChoices: stringRecord(row.document_choices),
		revision: row.revision,
		regulationSid: row.regulation_sid,
		providerAddressSid: row.provider_address_sid,
		providerEndUserSid: row.provider_end_user_sid,
		providerBundleSid: row.provider_bundle_sid,
		providerStatus: row.provider_status,
		failureReason: row.failure_reason,
		fixes: readFixes(row.fixes),
		validUntil: row.valid_until,
		submittedAt: row.submitted_at,
		decidedAt: row.decided_at,
		updatedAt: row.updated_at,
		createdAt: row.created_at
	};
}

export function mapPaperworkDocument(row: DocumentRow): StoredPaperworkDocument {
	return {
		id: row.id,
		documentType: row.document_type,
		protectedDocumentId: row.protected_document_id,
		fields: stringRecord(row.fields),
		providerDocumentSid: row.provider_document_sid,
		providerProtectedDocumentId: row.provider_protected_document_id,
		providerFields:
			row.provider_fields &&
			typeof row.provider_fields === 'object' &&
			!Array.isArray(row.provider_fields)
				? (row.provider_fields as Record<string, unknown>)
				: null,
		providerStatus: row.provider_status,
		failureReason: row.failure_reason
	};
}

function outcomeColumns(outcome: PaperworkOutcome) {
	const now = new Date().toISOString();
	return {
		status: outcome.status,
		...(outcome.providerStatus !== undefined ? { provider_status: outcome.providerStatus } : {}),
		...(outcome.failureReason !== undefined ? { failure_reason: outcome.failureReason } : {}),
		...(outcome.fixes !== undefined ? { fixes: outcome.fixes as unknown as Json } : {}),
		...(outcome.validUntil !== undefined ? { valid_until: outcome.validUntil } : {}),
		...(outcome.submitted ? { submitted_at: now, decided_at: null } : {}),
		...(outcome.decided ? { decided_at: now } : {}),
		last_checked_at: now,
		updated_at: now
	};
}

export function createSupabaseNumberPaperworkStore(
	client: SupabaseClient<Database>
): NumberPaperworkStore {
	return {
		async get(organizationId, paperworkId) {
			const { data, error } = await client
				.from('communication_sms_number_paperwork')
				.select('*, communication_sms_number_paperwork_documents(*)')
				.eq('organization_id', organizationId)
				.eq('id', paperworkId)
				.maybeSingle();
			if (error) throw new PaperworkStoreError('Could not read the paperwork.');
			if (!data) return null;
			const { communication_sms_number_paperwork_documents: documents, ...row } = data;
			return {
				paperwork: mapPaperwork(row as PaperworkRow),
				documents: (documents ?? []).map(mapPaperworkDocument)
			};
		},

		async claimSending(organizationId, paperworkId, expectedRevision) {
			const { data: current, error: readError } = await client
				.from('communication_sms_number_paperwork')
				.select('status, submitted_at, sending_claimed_at')
				.eq('organization_id', organizationId)
				.eq('id', paperworkId)
				.maybeSingle();
			if (readError) throw new PaperworkStoreError('Could not read the paperwork.');
			if (!current) return null;

			const stale =
				current.status === 'sending' &&
				current.sending_claimed_at !== null &&
				Date.parse(current.sending_claimed_at) <= Date.now() - STALE_CLAIM_MS;
			if (current.status !== 'draft' && current.status !== 'needs_fix' && !stale) return null;
			const previousStatus: PaperworkStatus = stale
				? current.submitted_at
					? 'needs_fix'
					: 'draft'
				: (current.status as PaperworkStatus);

			const token = crypto.randomUUID();
			let query = client
				.from('communication_sms_number_paperwork')
				.update({
					status: 'sending',
					sending_claim_token: token,
					sending_claimed_at: new Date().toISOString(),
					updated_at: new Date().toISOString()
				})
				.eq('organization_id', organizationId)
				.eq('id', paperworkId)
				.eq('revision', expectedRevision)
				.eq('status', current.status);
			// Only the claim that was read may be taken over, so two rescuers of one stale send cannot both win.
			query = current.sending_claimed_at
				? query.eq('sending_claimed_at', current.sending_claimed_at)
				: query.is('sending_claimed_at', null);
			const { data, error } = await query.select('*').maybeSingle();
			if (error) throw new PaperworkStoreError('Could not start sending the paperwork.');
			return data ? { paperwork: mapPaperwork(data), token, previousStatus } : null;
		},

		async saveProvider(paperworkId, token, patch) {
			const { data, error } = await client
				.from('communication_sms_number_paperwork')
				.update({
					...(patch.regulationSid !== undefined ? { regulation_sid: patch.regulationSid } : {}),
					...(patch.providerAddressSid !== undefined
						? { provider_address_sid: patch.providerAddressSid }
						: {}),
					...(patch.providerEndUserSid !== undefined
						? { provider_end_user_sid: patch.providerEndUserSid }
						: {}),
					...(patch.providerBundleSid !== undefined
						? { provider_bundle_sid: patch.providerBundleSid }
						: {}),
					...(patch.providerStatus !== undefined ? { provider_status: patch.providerStatus } : {}),
					updated_at: new Date().toISOString()
				})
				.eq('id', paperworkId)
				.eq('sending_claim_token', token)
				.select('id');
			if (error || !data?.length)
				throw new PaperworkStoreError('Could not record the Twilio paperwork.');
		},

		async saveDocumentProvider(documentId, patch) {
			const { error } = await client
				.from('communication_sms_number_paperwork_documents')
				.update({
					provider_document_sid: patch.providerDocumentSid,
					provider_protected_document_id: patch.providerProtectedDocumentId,
					provider_fields: patch.providerFields as Json,
					provider_status: patch.providerStatus,
					failure_reason: null,
					updated_at: new Date().toISOString()
				})
				.eq('id', documentId);
			if (error) throw new PaperworkStoreError('Could not record the Twilio document.');
		},

		async finishSending(paperworkId, token, outcome) {
			const { data, error } = await client
				.from('communication_sms_number_paperwork')
				.update({ ...outcomeColumns(outcome), sending_claim_token: null, sending_claimed_at: null })
				.eq('id', paperworkId)
				.eq('sending_claim_token', token)
				.select('id');
			if (error || !data?.length)
				throw new PaperworkStoreError('Could not finish sending the paperwork.');
		},

		async recordOutcome(paperworkId, outcome) {
			const { error } = await client
				.from('communication_sms_number_paperwork')
				.update(outcomeColumns(outcome))
				.eq('id', paperworkId)
				.in('status', ['under_review', 'approved', 'needs_fix']);
			if (error) throw new PaperworkStoreError('Could not record what Twilio said.');
		},

		async recordDocumentReview(documentId, review) {
			const { error } = await client
				.from('communication_sms_number_paperwork_documents')
				.update({
					provider_status: review.providerStatus,
					failure_reason: review.failureReason,
					updated_at: new Date().toISOString()
				})
				.eq('id', documentId);
			if (error)
				throw new PaperworkStoreError('Could not record what Twilio said about a document.');
		},

		async recordEvent(input) {
			const { error } = await client.from('communication_sms_number_paperwork_events').insert({
				organization_id: input.organizationId,
				paperwork_id: input.paperworkId,
				action: input.action,
				actor_user_id: input.actorUserId ?? null,
				detail: (input.detail ?? {}) as Json
			});
			// History never blocks the outcome it describes.
			if (error) console.error('Could not record a paperwork event.', { action: input.action });
		},

		async findByBundleSid(bundleSid) {
			const { data, error } = await client
				.from('communication_sms_number_paperwork')
				.select('id, organization_id')
				.eq('provider_bundle_sid', bundleSid)
				.maybeSingle();
			if (error) throw new PaperworkStoreError('Could not look up the paperwork.');
			return data ? { id: data.id, organizationId: data.organization_id } : null;
		},

		async listUnderReview(limit) {
			const { data, error } = await client
				.from('communication_sms_number_paperwork')
				.select('id, organization_id')
				.eq('status', 'under_review')
				.order('last_checked_at', { ascending: true, nullsFirst: true })
				.limit(limit);
			if (error) throw new PaperworkStoreError('Could not list paperwork under review.');
			return (data ?? []).map((row) => ({ id: row.id, organizationId: row.organization_id }));
		},

		async findApproved({ organizationId, countryCode, numberType }) {
			const { data, error } = await client
				.from('communication_sms_number_paperwork')
				.select('provider_bundle_sid, provider_address_sid')
				.eq('organization_id', organizationId)
				.eq('country_code', countryCode)
				.eq('number_type', numberType)
				.eq('status', 'approved')
				.maybeSingle();
			if (error) throw new PaperworkStoreError('Could not read approved paperwork.');
			return data
				? { bundleSid: data.provider_bundle_sid, addressSid: data.provider_address_sid }
				: null;
		},

		async readFile(organizationId, protectedDocumentId) {
			const { data, error } = await client
				.from('setup_protected_documents')
				.select('id, object_key, display_name, mime_type, size_bytes, state, problem')
				.eq('organization_id', organizationId)
				.eq('id', protectedDocumentId)
				.maybeSingle();
			if (error) throw new PaperworkStoreError('Could not read a paperwork file.');
			return data
				? {
						id: data.id,
						objectKey: data.object_key,
						displayName: data.display_name,
						mimeType: data.mime_type,
						sizeBytes: data.size_bytes,
						state: data.state as StoredPaperworkFile['state'],
						problem: data.problem
					}
				: null;
		},

		async scheduleFileDeletion(paperworkId) {
			const { error } = await client.rpc('communication_sms_schedule_paperwork_file_deletion', {
				target_paperwork_id: paperworkId
			});
			if (error)
				throw new PaperworkStoreError('Could not schedule the paperwork files for deletion.');
		}
	};
}
