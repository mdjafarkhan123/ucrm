import { ALLOWED_TYPES, pickerAccept } from '$lib/files/allowlist';
import { httpError } from '$lib/http-error';
import type { NumberType } from './sms-number-shop';

// Number paperwork (Stage 10 Part 3), shared by the server and the Number paperwork pages. The questions come
// live from Twilio's Regulations for the country and number kind (the server turns them into a
// PaperworkForm); this module decides how they are labelled, which ones Uplift answers itself, what comes
// filled in from the business's texting registration, and whether a set is complete enough to send.

export type EndUserType = 'business' | 'individual';
export type PaperworkStatus = 'draft' | 'sending' | 'under_review' | 'approved' | 'needs_fix';

export type FormField = {
	name: string;
	label: string;
	hint: string;
	required: boolean;
	/** A fixed list of allowed values, as [value, label] pairs. */
	choices: [string, string][] | null;
	pattern: string | null;
	kind: 'text' | 'email' | 'phone' | 'url' | 'date';
};

export type FormDocumentKind = {
	documentType: string;
	label: string;
	/** False for a kind that is only the address (business_address): nothing to upload. */
	needsFile: boolean;
	/** Fields the business types about the document, e.g. its number. Copied fields are not listed. */
	fields: FormField[];
};

export type FormRequirement = {
	requirementName: string;
	label: string;
	hint: string;
	/** Any one of these satisfies the requirement. */
	kinds: FormDocumentKind[];
};

export type PaperworkForm = {
	countryCode: string;
	numberType: NumberType;
	endUserType: EndUserType;
	/** Null when the country only asks for an address (no Regulatory Bundle). */
	regulationSid: string | null;
	businessFields: FormField[];
	personFields: FormField[];
	needsAddress: boolean;
	/** The country's rule for the address, in Twilio's words, e.g. "Must be within Germany". */
	addressRule: string;
	requirements: FormRequirement[];
};

export type PaperworkAddress = {
	customer_name: string;
	street: string;
	street_secondary: string;
	city: string;
	region: string;
	postal_code: string;
	country_code: string;
};

/** One thing to correct, pointing at the step and field where it lives. */
export type PaperworkFix = {
	step: 'details' | 'documents';
	/** An answer name, `address`, or `document:<type>` (optionally `:<field>`). */
	target: string;
	label: string;
	reason: string;
};

// Answers Uplift gives itself, the same for every business: Twilio asks the account holder whether it resells
// numbers, and Uplift assigns each number to the business that uses it to talk to its own customers.
export const PLATFORM_ANSWERS: Record<string, string> = {
	business_identity: 'DIRECT_CUSTOMER',
	is_subassigned: 'YES'
};
// Optional notes for Twilio's reviewer; never asked.
const NEVER_ASKED = new Set(['comments']);

const PERSON_FIELDS = new Set([
	'first_name',
	'last_name',
	'email',
	'phone_number',
	'birth_date',
	'nationality',
	'birth_place'
]);

const FIELD_LABELS: Record<string, string> = {
	business_name: 'Legal business name',
	business_registration_number: 'Registration number',
	business_registration_identifier: 'Where it is registered',
	business_website: 'Website',
	first_name: 'First name',
	last_name: 'Last name',
	email: 'Email',
	phone_number: 'Phone',
	birth_date: 'Date of birth',
	document_number: 'Document number',
	issue_date: 'Issue date',
	expiry_date: 'Expiry date',
	tax_id_number: 'Tax ID number',
	registered_seat_of_business: 'Registered office'
};

// Twilio's registration authorities, said plainly.
const CHOICE_LABELS: Record<string, string> = {
	'UK:CRN': 'United Kingdom · company number',
	'US:EIN': 'United States · EIN',
	'CA:CBN': 'Canada · business number',
	'AU:ACN': 'Australia · company number',
	OTHER: 'Somewhere else',
	YES: 'Yes',
	NO: 'No'
};

const DOCUMENT_LABELS: Record<string, string> = {
	business_address: 'Business address',
	individual_address: 'Home address',
	commercial_registrar_excerpt: 'Company register extract',
	utility_bill: 'Utility bill',
	tax_document: 'Tax document',
	tax_notice: 'Tax notice',
	rental_receipt: 'Rent receipt',
	title_deed: 'Title deed',
	trade_license: 'Trade licence',
	passport: 'Passport',
	government_issued_document: 'Government ID',
	business_registration: 'Business registration'
};

export function fieldLabel(name: string, twilioLabel: string): string {
	return FIELD_LABELS[name] ?? twilioLabel ?? name;
}

export function documentLabel(type: string, twilioLabel: string): string {
	return DOCUMENT_LABELS[type] ?? twilioLabel ?? type;
}

export function choiceLabel(value: string): string {
	return CHOICE_LABELS[value] ?? value;
}

export function isAskedEndUserField(name: string): boolean {
	return !(name in PLATFORM_ANSWERS) && !NEVER_ASKED.has(name);
}

export function isPersonField(name: string): boolean {
	return PERSON_FIELDS.has(name);
}

/** An address-only kind (business_address, individual_address) is the address itself, with no file. */
export function documentNeedsFile(type: string): boolean {
	return !type.endsWith('_address');
}

export function fieldKind(name: string, pattern: string | null): FormField['kind'] {
	if (name === 'email' || name.endsWith('_email')) return 'email';
	if (name === 'phone_number' || name.endsWith('_phone')) return 'phone';
	if (name === 'business_website' || name.endsWith('_url')) return 'url';
	if (name.endsWith('_date')) return 'date';
	if (pattern?.includes('@')) return 'email';
	return 'text';
}

// Twilio takes a document as a JPEG, PNG or PDF of up to 5 MB.
export const PAPERWORK_FILE_TYPES = ALLOWED_TYPES.filter((type) =>
	['jpeg', 'png', 'pdf'].includes(type.signature)
);
export const PAPERWORK_FILE_ACCEPT = pickerAccept(PAPERWORK_FILE_TYPES);
export const PAPERWORK_MAX_FILE_BYTES = 5 * 1024 * 1024;

// --- Filling in ----------------------------------------------------------------------------------------------

/** The texting registration's answers, as the registration form saved them (any part may be missing). */
export type RegistrationAnswers = {
	legal_business_name?: string;
	business_registration_id?: string;
	website_url?: string;
	business_address?: Partial<{
		line1: string;
		line2: string;
		city: string;
		region: string;
		postal_code: string;
		country_code: string;
	}>;
	authorized_representative?: Partial<{
		first_name: string;
		last_name: string;
		email: string;
		phone_number: string;
	}>;
};

const REGISTRATION_IDENTIFIERS: Record<string, string> = {
	GB: 'UK:CRN',
	US: 'US:EIN',
	CA: 'CA:CBN',
	AU: 'AU:ACN'
};

/** Answers for a new set, taken from the registration the business already gave for texting. */
export function prefillAnswers(
	form: Pick<PaperworkForm, 'businessFields' | 'personFields'>,
	registration: RegistrationAnswers | null
): Record<string, string> {
	if (!registration) return {};
	const person = registration.authorized_representative ?? {};
	const known: Record<string, string | undefined> = {
		business_name: registration.legal_business_name,
		business_registration_number: registration.business_registration_id,
		business_website: registration.website_url,
		first_name: person.first_name,
		last_name: person.last_name,
		email: person.email,
		phone_number: person.phone_number
	};
	const country = registration.business_address?.country_code?.toUpperCase();
	const answers: Record<string, string> = {};
	for (const field of [...form.businessFields, ...form.personFields]) {
		let value = known[field.name];
		if (field.name === 'business_registration_identifier' && country) {
			const wanted = REGISTRATION_IDENTIFIERS[country] ?? 'OTHER';
			value = field.choices?.some(([choice]) => choice === wanted) ? wanted : undefined;
		}
		if (value) answers[field.name] = value;
	}
	return answers;
}

export function prefillAddress(
	registration: RegistrationAnswers | null,
	customerName: string
): PaperworkAddress | null {
	const address = registration?.business_address;
	if (!address?.line1) return null;
	return {
		customer_name: customerName,
		street: address.line1 ?? '',
		street_secondary: address.line2 ?? '',
		city: address.city ?? '',
		region: address.region ?? '',
		postal_code: address.postal_code ?? '',
		country_code: (address.country_code ?? '').toUpperCase()
	};
}

/**
 * The document kind for each requirement: the saved choice when the country still accepts it, else one
 * already chosen for another requirement (one upload proves both), else the first kind the country lists.
 */
export function resolveDocumentChoices(
	requirements: FormRequirement[],
	saved: Record<string, string>
): Record<string, string> {
	const choices: Record<string, string> = {};
	const chosen = new Set<string>();
	for (const requirement of requirements) {
		const accepted = requirement.kinds.map((kind) => kind.documentType);
		const pick =
			(saved[requirement.requirementName] && accepted.includes(saved[requirement.requirementName])
				? saved[requirement.requirementName]
				: accepted.find((type) => chosen.has(type))) ?? accepted[0];
		if (!pick) continue;
		choices[requirement.requirementName] = pick;
		chosen.add(pick);
	}
	return choices;
}

/** Each chosen document kind once, with every field asked about it across the requirements it covers. */
export function chosenDocumentKinds(
	requirements: FormRequirement[],
	choices: Record<string, string>
): (FormDocumentKind & { requirementNames: string[] })[] {
	const byType = new Map<string, FormDocumentKind & { requirementNames: string[] }>();
	for (const requirement of requirements) {
		const type = choices[requirement.requirementName];
		const kind = requirement.kinds.find((candidate) => candidate.documentType === type);
		if (!kind) continue;
		const existing = byType.get(type);
		if (!existing) {
			byType.set(type, {
				...kind,
				fields: [...kind.fields],
				requirementNames: [requirement.requirementName]
			});
			continue;
		}
		existing.requirementNames.push(requirement.requirementName);
		for (const field of kind.fields) {
			if (!existing.fields.some((known) => known.name === field.name)) existing.fields.push(field);
		}
	}
	return [...byType.values()];
}

// --- Checking before sending ---------------------------------------------------------------------------------

export type PaperworkDocumentState = {
	documentType: string;
	fields: Record<string, string>;
	/** 'ready' once the file passed its checks; null when no file was added. */
	fileState: 'uploading' | 'checking' | 'ready' | 'refused' | 'deleted' | null;
};

function fieldProblem(field: FormField, raw: string | undefined): string | null {
	const value = (raw ?? '').trim();
	if (!value) return field.required ? `Enter ${field.label.toLowerCase()}.` : null;
	if (value.length > 500) return 'Keep this under 500 characters.';
	if (field.choices && !field.choices.some(([choice]) => choice === value))
		return 'Choose one of the options.';
	if (field.pattern) {
		try {
			if (!new RegExp(field.pattern).test(value)) return problemForKind(field.kind);
		} catch {
			// A pattern this browser cannot read is left to Twilio's own check.
		}
	}
	if (field.kind === 'email' && !/^\S+@\S+\.\S+$/.test(value)) return problemForKind('email');
	if (field.kind === 'phone' && !/^\+[1-9]\d{6,14}$/.test(value)) return problemForKind('phone');
	if (field.kind === 'date' && !/^\d{4}-\d{2}-\d{2}$/.test(value)) return problemForKind('date');
	return null;
}

function problemForKind(kind: FormField['kind']): string {
	switch (kind) {
		case 'email':
			return 'Enter a complete email address.';
		case 'phone':
			return 'Enter the phone in international format, starting with +.';
		case 'date':
			return 'Enter the date as YYYY-MM-DD.';
		case 'url':
			return 'Enter a complete web address.';
		default:
			return 'This does not match what the country asks for.';
	}
}

const ADDRESS_PARTS: [keyof PaperworkAddress, string][] = [
	['customer_name', 'the name at this address'],
	['street', 'the street'],
	['city', 'the city'],
	['region', 'the state or region'],
	['postal_code', 'the postal code'],
	['country_code', 'the country']
];

/** Everything still missing or wrong, in the order the steps show it. Empty means the set can be sent. */
export function paperworkProblems(
	form: PaperworkForm,
	set: {
		answers: Record<string, string>;
		address: PaperworkAddress | null;
		documentChoices: Record<string, string>;
		documents: PaperworkDocumentState[];
	}
): PaperworkFix[] {
	const problems: PaperworkFix[] = [];
	for (const field of [...form.businessFields, ...form.personFields]) {
		const reason = fieldProblem(field, set.answers[field.name]);
		if (reason) problems.push({ step: 'details', target: field.name, label: field.label, reason });
	}
	if (form.needsAddress) {
		for (const [part, words] of ADDRESS_PARTS) {
			if (!set.address?.[part]?.trim()) {
				problems.push({
					step: 'details',
					target: 'address',
					label: 'Address',
					reason: `Enter ${words}.`
				});
				break;
			}
		}
	}
	const choices = resolveDocumentChoices(form.requirements, set.documentChoices);
	for (const kind of chosenDocumentKinds(form.requirements, choices)) {
		const document = set.documents.find(
			(candidate) => candidate.documentType === kind.documentType
		);
		const target = `document:${kind.documentType}`;
		if (kind.needsFile) {
			const state = document?.fileState ?? null;
			if (state !== 'ready') {
				problems.push({
					step: 'documents',
					target,
					label: kind.label,
					reason:
						state === 'checking' || state === 'uploading'
							? 'Wait for the file to finish its checks.'
							: state === 'refused'
								? 'That file could not be used. Add it again.'
								: 'Add this document.'
				});
			}
		}
		for (const field of kind.fields) {
			const reason = fieldProblem(field, document?.fields[field.name]);
			if (reason)
				problems.push({
					step: 'documents',
					target: `${target}:${field.name}`,
					label: field.label,
					reason
				});
		}
	}
	return problems;
}

// --- Client shapes and fetchers ------------------------------------------------------------------------------

export type PaperworkDocument = {
	document_type: string;
	fields: Record<string, string>;
	file: {
		id: string;
		name: string;
		size_bytes: number;
		state: 'uploading' | 'checking' | 'ready' | 'refused' | 'deleted';
		problem: string | null;
	} | null;
	failure_reason: string | null;
};

export type PaperworkSummary = {
	id: string;
	country_code: string;
	number_type: NumberType;
	end_user_type: EndUserType;
	status: PaperworkStatus;
	submitted_at: string | null;
	decided_at: string | null;
	updated_at: string;
	failure_reason: string | null;
	/** The first thing to correct, while the set needs a fix. */
	first_fix: PaperworkFix | null;
	/** Numbers bought with this paperwork. */
	numbers: string[];
};

export type PaperworkDetail = PaperworkSummary & {
	revision: number;
	answers: Record<string, string>;
	address: PaperworkAddress | null;
	document_choices: Record<string, string>;
	documents: PaperworkDocument[];
	fixes: PaperworkFix[];
	form: PaperworkForm;
};

export type ReusedDetails = {
	business_name: string | null;
	registration_number: string | null;
	address: string | null;
	person: string | null;
	/** The registration's business address, to tell a set that it uses the same one. */
	address_parts: PaperworkAddress | null;
};

export type PaperworkList = { paperwork: PaperworkSummary[]; reused: ReusedDetails };

const BASE = '/api/settings/communications/sms/paperwork';

/** A refused paperwork call: the server's own words, its code and, for a send, what is still missing. */
export type PaperworkRequestError = Error & {
	status: number;
	code: string | null;
	problems: PaperworkFix[];
	fieldErrors: Record<string, string[]>;
};

async function refusal(response: Response, fallback: string): Promise<PaperworkRequestError> {
	const body = (await response.json().catch(() => null)) as {
		error?: string;
		code?: string;
		problems?: PaperworkFix[];
		field_errors?: Record<string, string[]>;
	} | null;
	const error = httpError(response, body?.error || fallback) as PaperworkRequestError;
	error.code = body?.code ?? null;
	error.problems = body?.problems ?? [];
	error.fieldErrors = body?.field_errors ?? {};
	return error;
}

async function readJson<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) throw await refusal(response, fallback);
	return (await response.json()) as T;
}

export async function fetchPaperworkList(fetcher: typeof fetch = fetch): Promise<PaperworkList> {
	return readJson(await fetcher(BASE), 'The paperwork could not be loaded.');
}

export async function fetchPaperwork(
	id: string,
	fetcher: typeof fetch = fetch
): Promise<PaperworkDetail> {
	const body = await readJson<{ paperwork: PaperworkDetail }>(
		await fetcher(`${BASE}/${id}`),
		'This paperwork could not be loaded.'
	);
	return body.paperwork;
}

export async function startPaperwork(input: {
	country_code: string;
	number_type: NumberType;
	end_user_type: EndUserType;
}): Promise<PaperworkDetail> {
	const body = await readJson<{ paperwork: PaperworkDetail }>(
		await fetch(BASE, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(input)
		}),
		'The paperwork could not be started.'
	);
	return body.paperwork;
}

export type PaperworkChanges = {
	expected_revision: number;
	end_user_type?: EndUserType;
	answers?: Record<string, string>;
	address?: PaperworkAddress | null;
	document_choices?: Record<string, string>;
	documents?: { document_type: string; fields: Record<string, string> }[];
};

export async function savePaperwork(
	id: string,
	changes: PaperworkChanges
): Promise<PaperworkDetail> {
	const body = await readJson<{ paperwork: PaperworkDetail }>(
		await fetch(`${BASE}/${id}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(changes)
		}),
		'Your changes could not be saved.'
	);
	return body.paperwork;
}

export async function sendPaperwork(
	id: string,
	expectedRevision: number
): Promise<PaperworkDetail> {
	const body = await readJson<{ paperwork: PaperworkDetail }>(
		await fetch(`${BASE}/${id}/send`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ expected_revision: expectedRevision })
		}),
		'The paperwork could not be sent.'
	);
	return body.paperwork;
}

export async function deletePaperwork(id: string): Promise<void> {
	const response = await fetch(`${BASE}/${id}`, { method: 'DELETE' });
	if (!response.ok) throw await refusal(response, 'The draft could not be deleted.');
}

export const paperworkKeys = {
	all: ['sms-number-paperwork'] as const,
	list: () => [...paperworkKeys.all, 'list'] as const,
	detail: (id: string) => [...paperworkKeys.all, 'detail', id] as const
};

export async function startPaperworkUpload(
	id: string,
	documentType: string,
	file: File
): Promise<{ file_id: string; mime_type: string; upload_url: string }> {
	return readJson(
		await fetch(`${BASE}/${id}/documents`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				document_type: documentType,
				file_name: file.name,
				mime_type: file.type,
				size_bytes: file.size
			})
		}),
		'That file could not be added.'
	);
}

export async function finishPaperworkUpload(id: string, fileId: string): Promise<void> {
	const response = await fetch(`${BASE}/${id}/documents/${fileId}/complete`, { method: 'POST' });
	if (!response.ok) throw await refusal(response, 'That file could not be added.');
}
