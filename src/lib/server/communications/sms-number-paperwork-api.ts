import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import {
	chosenDocumentKinds,
	prefillAddress,
	resolveDocumentChoices,
	type PaperworkDetail,
	type PaperworkForm,
	type PaperworkSummary,
	type RegistrationAnswers,
	type ReusedDetails
} from '$lib/communications/number-paperwork';
import type { NumberType } from '$lib/communications/sms-number-shop';
import {
	mapPaperwork,
	mapPaperworkDocument,
	readFixes,
	type StoredPaperwork,
	type StoredPaperworkDocument
} from './sms-number-paperwork-store';

// What the Number paperwork pages read and write (Stage 10 Part 3). Every read is scoped to one organization;
// the routes have already checked who is asking.

const COLUMNS =
	'id, country_code, number_type, end_user_type, status, submitted_at, decided_at, updated_at, failure_reason, provider_bundle_sid, provider_address_sid, regulation_sid';

type Client = SupabaseClient<Database>;

/** Numbers bought with each set: a bundle's numbers, or an address-only set's. */
async function numbersBySet(
	client: Client,
	organizationId: string,
	sets: {
		id: string;
		bundleSid: string | null;
		addressSid: string | null;
		regulationSid: string | null;
	}[]
): Promise<Map<string, string[]>> {
	const bundles = sets.flatMap((set) => (set.bundleSid ? [set.bundleSid] : []));
	const addresses = sets.flatMap((set) =>
		!set.regulationSid && set.addressSid ? [set.addressSid] : []
	);
	const result = new Map<string, string[]>(sets.map((set) => [set.id, []]));
	if (bundles.length === 0 && addresses.length === 0) return result;
	const filters = [
		...(bundles.length ? [`bundle_sid.in.(${bundles.join(',')})`] : []),
		...(addresses.length ? [`and(bundle_sid.is.null,address_sid.in.(${addresses.join(',')}))`] : [])
	];
	const { data, error } = await client
		.from('communication_sms_number_orders')
		.select('phone_number, bundle_sid, address_sid')
		.eq('organization_id', organizationId)
		.eq('state', 'completed')
		.or(filters.join(','))
		.order('completed_at', { ascending: true })
		.limit(200);
	if (error) throw error;
	for (const order of data ?? []) {
		const set = sets.find((candidate) =>
			order.bundle_sid
				? candidate.bundleSid === order.bundle_sid
				: !candidate.regulationSid && candidate.addressSid === order.address_sid
		);
		if (set) result.get(set.id)?.push(order.phone_number);
	}
	return result;
}

export async function listPaperworkSummaries(
	client: Client,
	organizationId: string
): Promise<PaperworkSummary[]> {
	const { data, error } = await client
		.from('communication_sms_number_paperwork')
		.select(`${COLUMNS}, fixes`)
		.eq('organization_id', organizationId)
		.order('created_at', { ascending: false })
		.limit(100);
	if (error) throw error;
	const rows = data ?? [];
	const numbers = await numbersBySet(
		client,
		organizationId,
		rows.map((row) => ({
			id: row.id,
			bundleSid: row.provider_bundle_sid,
			addressSid: row.provider_address_sid,
			regulationSid: row.regulation_sid
		}))
	);
	return rows.map((row) => ({
		id: row.id,
		country_code: row.country_code,
		number_type: row.number_type as NumberType,
		end_user_type: row.end_user_type as PaperworkSummary['end_user_type'],
		status: row.status as PaperworkSummary['status'],
		submitted_at: row.submitted_at,
		decided_at: row.decided_at,
		updated_at: row.updated_at,
		failure_reason: row.failure_reason,
		first_fix: row.status === 'needs_fix' ? (readFixes(row.fixes)[0] ?? null) : null,
		numbers: numbers.get(row.id) ?? []
	}));
}

/** The business's texting registration answers: its latest submission, else its draft. */
export async function readRegistrationAnswers(
	client: Client,
	organizationId: string
): Promise<RegistrationAnswers | null> {
	const { data: registration, error } = await client
		.from('communication_sms_registrations')
		.select('id, draft_answers')
		.eq('organization_id', organizationId)
		.order('updated_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (error) throw error;
	if (!registration) return null;
	const { data: submission, error: submissionError } = await client
		.from('communication_sms_registration_submissions')
		.select('answers')
		.eq('registration_id', registration.id)
		.order('submission_number', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (submissionError) throw submissionError;
	const answers = submission?.answers ?? registration.draft_answers;
	return answers && typeof answers === 'object' && !Array.isArray(answers)
		? (answers as RegistrationAnswers)
		: null;
}

export function reusedDetails(registration: RegistrationAnswers | null): ReusedDetails {
	const address = registration?.business_address;
	const person = registration?.authorized_representative;
	const personName = [person?.first_name, person?.last_name].filter(Boolean).join(' ');
	return {
		business_name: registration?.legal_business_name || null,
		registration_number: registration?.business_registration_id || null,
		address: address?.line1
			? [address.line1, address.city, address.region].filter(Boolean).join(', ')
			: null,
		person: personName || null,
		address_parts: prefillAddress(registration, registration?.legal_business_name ?? '')
	};
}

export async function readPaperwork(
	client: Client,
	organizationId: string,
	paperworkId: string
): Promise<{ paperwork: StoredPaperwork; documents: StoredPaperworkDocument[] } | null> {
	const { data, error } = await client
		.from('communication_sms_number_paperwork')
		.select('*, communication_sms_number_paperwork_documents(*)')
		.eq('organization_id', organizationId)
		.eq('id', paperworkId)
		.maybeSingle();
	if (error) throw error;
	if (!data) return null;
	const { communication_sms_number_paperwork_documents: documents, ...row } = data;
	return {
		paperwork: mapPaperwork(row),
		documents: (documents ?? []).map(mapPaperworkDocument)
	};
}

/** One document row per chosen kind, so every upload and every send has a row to hold its records. */
export async function ensureDocumentRows(
	client: Client,
	paperwork: StoredPaperwork,
	form: PaperworkForm
): Promise<void> {
	const choices = resolveDocumentChoices(form.requirements, paperwork.documentChoices);
	const rows = chosenDocumentKinds(form.requirements, choices).map((kind) => ({
		organization_id: paperwork.organizationId,
		paperwork_id: paperwork.id,
		document_type: kind.documentType
	}));
	if (rows.length === 0) return;
	const { error } = await client
		.from('communication_sms_number_paperwork_documents')
		.upsert(rows, { onConflict: 'paperwork_id,document_type', ignoreDuplicates: true });
	if (error) throw error;
}

export async function presentPaperwork(
	client: Client,
	loaded: { paperwork: StoredPaperwork; documents: StoredPaperworkDocument[] },
	form: PaperworkForm
): Promise<PaperworkDetail> {
	const { paperwork, documents } = loaded;
	const fileIds = documents.flatMap((document) =>
		document.protectedDocumentId ? [document.protectedDocumentId] : []
	);
	const files = new Map<string, PaperworkDetail['documents'][number]['file']>();
	if (fileIds.length > 0) {
		const { data, error } = await client
			.from('setup_protected_documents')
			.select('id, display_name, size_bytes, state, problem')
			.eq('organization_id', paperwork.organizationId)
			.in('id', fileIds);
		if (error) throw error;
		for (const row of data ?? []) {
			files.set(row.id, {
				id: row.id,
				name: row.display_name,
				size_bytes: row.size_bytes,
				state: row.state as NonNullable<PaperworkDetail['documents'][number]['file']>['state'],
				problem: row.problem
			});
		}
	}
	const numbers = await numbersBySet(client, paperwork.organizationId, [
		{
			id: paperwork.id,
			bundleSid: paperwork.providerBundleSid,
			addressSid: paperwork.providerAddressSid,
			regulationSid: paperwork.regulationSid
		}
	]);
	return {
		id: paperwork.id,
		country_code: paperwork.countryCode,
		number_type: paperwork.numberType,
		end_user_type: paperwork.endUserType,
		status: paperwork.status,
		submitted_at: paperwork.submittedAt,
		decided_at: paperwork.decidedAt,
		updated_at: paperwork.updatedAt,
		failure_reason: paperwork.failureReason,
		first_fix: paperwork.status === 'needs_fix' ? (paperwork.fixes[0] ?? null) : null,
		numbers: numbers.get(paperwork.id) ?? [],
		revision: paperwork.revision,
		answers: paperwork.answers,
		address: paperwork.address,
		document_choices: resolveDocumentChoices(form.requirements, paperwork.documentChoices),
		documents: documents.map((document) => ({
			document_type: document.documentType,
			fields: document.fields,
			file: document.protectedDocumentId ? (files.get(document.protectedDocumentId) ?? null) : null,
			failure_reason: document.failureReason
		})),
		fixes: paperwork.fixes,
		form
	};
}

export function asJson(value: unknown): Json {
	return value as Json;
}
