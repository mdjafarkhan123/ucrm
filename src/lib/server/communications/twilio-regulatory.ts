// Twilio Regulatory Compliance adapter (Stage 10 Part 3): the only module that writes a business's number
// paperwork to Twilio. Verified against Twilio's Regulatory Compliance docs (2026-10-22):
//   - Bundles, End-Users, Supporting Documents, Item Assignments, Evaluations:
//     https://numbers.twilio.com/v2/RegulatoryCompliance/...
//   - a Supporting Document with a file goes to https://numbers-upload.twilio.com as multipart form data
//     (JPEG, PNG or PDF, up to 5 MB);
//   - Address: https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Addresses.json.
//
// Everything is made inside the business's own subaccount, with its own Auth Token, because a number can only be
// bought with a bundle and address that belong to the account buying it. Nothing here reads Uplift's own
// business details: Twilio requires each bundle to describe the business that uses the number.
//
// Twilio has no sandbox for these resources, so every call is real when it runs. Tests drive this module's
// callers against a fake of the port below.

export class TwilioRegulatoryError extends Error {
	constructor(
		message: string,
		public readonly status: number | null,
		public readonly code: string,
		public readonly retryable: boolean,
		public readonly providerCode: string | null = null,
		public readonly providerMessage: string | null = null
	) {
		super(message);
		this.name = 'TwilioRegulatoryError';
	}
}

export type SubaccountCredentials = { subaccountSid: string; authToken: string };

export type RegulatoryAddressInput = {
	customerName: string;
	street: string;
	streetSecondary?: string | null;
	city: string;
	region: string;
	postalCode: string;
	isoCountry: string;
	friendlyName: string;
};

export type RegulatoryFile = { name: string; mimeType: string; bytes: Uint8Array };

export type BundleStatus =
	| 'draft'
	| 'pending-review'
	| 'in-review'
	| 'twilio-rejected'
	| 'twilio-approved'
	| 'provisionally-approved';

export type RegulatoryBundle = {
	sid: string;
	status: BundleStatus;
	validUntil: string | null;
};

export type RegulatorySupportingDocument = {
	sid: string;
	status: string | null;
	failureReason: string | null;
};

export type ItemAssignment = { sid: string; objectSid: string };

export type BundleEvaluationProblem = {
	/** Twilio's requirement name, e.g. business_address_info, or the object type when it gives none. */
	requirementName: string;
	requirementLabel: string;
	/** The field Twilio points at, e.g. business_name; null when the whole requirement is missing. */
	field: string | null;
	reason: string;
};

export type BundleEvaluation = {
	compliant: boolean;
	problems: BundleEvaluationProblem[];
};

/** The paperwork calls the submission flow needs, kept semantic so tests can fake them. */
export type TwilioRegulatoryClient = {
	createAddress(
		account: SubaccountCredentials,
		input: RegulatoryAddressInput
	): Promise<{ sid: string }>;
	updateAddress(
		account: SubaccountCredentials,
		sid: string,
		input: RegulatoryAddressInput
	): Promise<{ sid: string }>;
	createEndUser(
		account: SubaccountCredentials,
		input: { friendlyName: string; type: string; attributes: Record<string, unknown> }
	): Promise<{ sid: string }>;
	updateEndUser(
		account: SubaccountCredentials,
		sid: string,
		attributes: Record<string, unknown>
	): Promise<{ sid: string }>;
	createSupportingDocument(
		account: SubaccountCredentials,
		input: {
			friendlyName: string;
			type: string;
			attributes: Record<string, unknown>;
			file: RegulatoryFile | null;
		}
	): Promise<RegulatorySupportingDocument>;
	fetchSupportingDocument(
		account: SubaccountCredentials,
		sid: string
	): Promise<RegulatorySupportingDocument>;
	createBundle(
		account: SubaccountCredentials,
		input: {
			friendlyName: string;
			email: string;
			statusCallback: string;
			regulationSid: string;
			isoCountry: string;
			numberType: string;
			endUserType: string;
		}
	): Promise<RegulatoryBundle>;
	fetchBundle(account: SubaccountCredentials, sid: string): Promise<RegulatoryBundle>;
	/** Move a bundle to `draft` (to edit a rejected one) or `pending-review` (to send it). */
	updateBundleStatus(
		account: SubaccountCredentials,
		sid: string,
		status: 'draft' | 'pending-review'
	): Promise<RegulatoryBundle>;
	listItemAssignments(account: SubaccountCredentials, bundleSid: string): Promise<ItemAssignment[]>;
	createItemAssignment(
		account: SubaccountCredentials,
		bundleSid: string,
		objectSid: string
	): Promise<ItemAssignment>;
	deleteItemAssignment(
		account: SubaccountCredentials,
		bundleSid: string,
		assignmentSid: string
	): Promise<void>;
	evaluateBundle(account: SubaccountCredentials, bundleSid: string): Promise<BundleEvaluation>;
};

const NUMBERS_BASE = 'https://numbers.twilio.com';
const NUMBERS_UPLOAD_BASE = 'https://numbers-upload.twilio.com';
const TWILIO_API_BASE = 'https://api.twilio.com';
const PROVIDER_TIMEOUT_MS = 15_000;
// A 5 MB file over a slow link takes longer than an ordinary call.
const UPLOAD_TIMEOUT_MS = 60_000;

const SUBACCOUNT_SID = /^AC[0-9A-Fa-f]{32}$/;
const ADDRESS_SID = /^AD[0-9A-Fa-f]{32}$/;
const END_USER_SID = /^IT[0-9A-Fa-f]{32}$/;
const DOCUMENT_SID = /^RD[0-9A-Fa-f]{32}$/;
const BUNDLE_SID = /^BU[0-9A-Fa-f]{32}$/;
const ASSIGNMENT_SID = /^[A-Z]{2}[0-9A-Fa-f]{32}$/;

const BUNDLE_STATUSES = new Set<BundleStatus>([
	'draft',
	'pending-review',
	'in-review',
	'twilio-rejected',
	'twilio-approved',
	'provisionally-approved'
]);

function basicAuth(account: SubaccountCredentials): string {
	requireSid(account.subaccountSid, SUBACCOUNT_SID, 'twilio_bad_subaccount_sid');
	return `Basic ${Buffer.from(`${account.subaccountSid}:${account.authToken}`, 'utf8').toString('base64')}`;
}

function readString(body: unknown, key: string): string | null {
	if (body && typeof body === 'object' && key in body) {
		const value = (body as Record<string, unknown>)[key];
		return typeof value === 'string' ? value : null;
	}
	return null;
}

function readArray(body: unknown, key: string): unknown[] {
	if (body && typeof body === 'object' && key in body) {
		const value = (body as Record<string, unknown>)[key];
		return Array.isArray(value) ? value : [];
	}
	return [];
}

function requireSid(value: string | null, pattern: RegExp, code: string): string {
	if (!value || !pattern.test(value)) {
		throw new TwilioRegulatoryError('Twilio returned an unexpected identifier.', null, code, false);
	}
	return value;
}

type RegulatoryRequest = {
	base: string;
	path: string;
	method: 'GET' | 'POST' | 'DELETE';
	auth: string;
	form?: Record<string, string>;
	multipart?: FormData;
	query?: Record<string, string>;
	timeoutMs?: number;
};

async function regulatoryRequest(request: RegulatoryRequest): Promise<unknown> {
	const url = new URL(request.path, request.base);
	for (const [key, value] of Object.entries(request.query ?? {})) url.searchParams.set(key, value);

	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), request.timeoutMs ?? PROVIDER_TIMEOUT_MS);
	let response: Response;
	try {
		response = await fetch(url, {
			method: request.method,
			headers: {
				accept: 'application/json',
				authorization: request.auth,
				...(request.form ? { 'content-type': 'application/x-www-form-urlencoded' } : {})
			},
			body: request.form ? new URLSearchParams(request.form).toString() : request.multipart,
			signal: controller.signal
		});
	} catch {
		// The outcome is unknown, so the caller may try again. Never surface the underlying error: it can echo
		// request headers, including credentials.
		throw new TwilioRegulatoryError(
			'Twilio did not return a result.',
			null,
			'twilio_regulatory_unknown',
			true
		);
	} finally {
		clearTimeout(timeout);
	}

	const text = await response.text().catch(() => '');
	let body: unknown = null;
	if (text) {
		try {
			body = JSON.parse(text);
		} catch {
			body = null;
		}
	}

	if (!response.ok) {
		const code =
			body && typeof body === 'object' && typeof (body as { code?: unknown }).code === 'number'
				? String((body as { code: number }).code)
				: null;
		throw new TwilioRegulatoryError(
			`Twilio refused a paperwork request (status ${response.status}).`,
			response.status,
			'twilio_regulatory_rejected',
			response.status === 429 || response.status >= 500,
			code,
			readString(body, 'message')
		);
	}
	return body;
}

function addressForm(input: RegulatoryAddressInput): Record<string, string> {
	return {
		CustomerName: input.customerName,
		Street: input.street,
		...(input.streetSecondary ? { StreetSecondary: input.streetSecondary } : {}),
		City: input.city,
		Region: input.region,
		PostalCode: input.postalCode,
		FriendlyName: input.friendlyName
	};
}

function readBundle(body: unknown): RegulatoryBundle {
	const status = readString(body, 'status');
	if (!status || !BUNDLE_STATUSES.has(status as BundleStatus)) {
		throw new TwilioRegulatoryError(
			'Twilio returned an unexpected paperwork status.',
			null,
			'twilio_regulatory_bad_status',
			false
		);
	}
	return {
		sid: requireSid(readString(body, 'sid'), BUNDLE_SID, 'twilio_regulatory_missing_bundle_sid'),
		status: status as BundleStatus,
		validUntil: readString(body, 'valid_until')
	};
}

function readDocument(body: unknown): RegulatorySupportingDocument {
	return {
		sid: requireSid(
			readString(body, 'sid'),
			DOCUMENT_SID,
			'twilio_regulatory_missing_document_sid'
		),
		status: readString(body, 'status'),
		failureReason: readString(body, 'failure_reason') || null
	};
}

function readAssignment(body: unknown): ItemAssignment {
	return {
		sid: requireSid(
			readString(body, 'sid'),
			ASSIGNMENT_SID,
			'twilio_regulatory_missing_assignment_sid'
		),
		objectSid: readString(body, 'object_sid') ?? ''
	};
}

/**
 * An evaluation lists each requirement with `passed` and, when it failed, the fields at fault. Twilio's own
 * examples nest the field rows under `fields`; a requirement with no field rows still says why it failed.
 */
export function readEvaluation(body: unknown): BundleEvaluation {
	const status = readString(body, 'status');
	const problems: BundleEvaluationProblem[] = [];
	for (const row of readArray(body, 'results')) {
		if (row && typeof row === 'object' && (row as { passed?: unknown }).passed === true) continue;
		const requirementName =
			readString(row, 'requirement_name') ?? readString(row, 'object_type') ?? 'unknown';
		const requirementLabel =
			readString(row, 'requirement_friendly_name') ??
			readString(row, 'friendly_name') ??
			requirementName;
		const failedFields = readArray(row, 'fields').filter(
			(field) =>
				!(field && typeof field === 'object' && (field as { passed?: unknown }).passed === true)
		);
		if (failedFields.length === 0) {
			problems.push({
				requirementName,
				requirementLabel,
				field: null,
				reason: readString(row, 'failure_reason') || 'This is missing.'
			});
			continue;
		}
		for (const field of failedFields) {
			problems.push({
				requirementName,
				requirementLabel,
				field: readString(field, 'object_field') ?? readString(field, 'field'),
				reason:
					readString(field, 'failure_reason') ||
					readString(row, 'failure_reason') ||
					'This does not meet the country’s rules.'
			});
		}
	}
	return { compliant: status === 'compliant' && problems.length === 0, problems };
}

export function createTwilioRegulatoryClient(): TwilioRegulatoryClient {
	return {
		async createAddress(account, input) {
			const body = await regulatoryRequest({
				base: TWILIO_API_BASE,
				path: `/2010-04-01/Accounts/${account.subaccountSid}/Addresses.json`,
				method: 'POST',
				auth: basicAuth(account),
				form: { ...addressForm(input), IsoCountry: input.isoCountry }
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					ADDRESS_SID,
					'twilio_regulatory_missing_address_sid'
				)
			};
		},

		async updateAddress(account, sid, input) {
			// Twilio never lets an address change country; the caller makes a new one instead.
			const body = await regulatoryRequest({
				base: TWILIO_API_BASE,
				path: `/2010-04-01/Accounts/${account.subaccountSid}/Addresses/${requireSid(sid, ADDRESS_SID, 'twilio_bad_address_sid')}.json`,
				method: 'POST',
				auth: basicAuth(account),
				form: addressForm(input)
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					ADDRESS_SID,
					'twilio_regulatory_missing_address_sid'
				)
			};
		},

		async createEndUser(account, input) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: '/v2/RegulatoryCompliance/EndUsers',
				method: 'POST',
				auth: basicAuth(account),
				form: {
					FriendlyName: input.friendlyName,
					Type: input.type,
					Attributes: JSON.stringify(input.attributes)
				}
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					END_USER_SID,
					'twilio_regulatory_missing_end_user_sid'
				)
			};
		},

		async updateEndUser(account, sid, attributes) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/EndUsers/${requireSid(sid, END_USER_SID, 'twilio_bad_end_user_sid')}`,
				method: 'POST',
				auth: basicAuth(account),
				form: { Attributes: JSON.stringify(attributes) }
			});
			return {
				sid: requireSid(
					readString(body, 'sid'),
					END_USER_SID,
					'twilio_regulatory_missing_end_user_sid'
				)
			};
		},

		async createSupportingDocument(account, input) {
			if (!input.file) {
				const body = await regulatoryRequest({
					base: NUMBERS_BASE,
					path: '/v2/RegulatoryCompliance/SupportingDocuments',
					method: 'POST',
					auth: basicAuth(account),
					form: {
						FriendlyName: input.friendlyName,
						Type: input.type,
						Attributes: JSON.stringify(input.attributes)
					}
				});
				return readDocument(body);
			}
			const form = new FormData();
			form.set('FriendlyName', input.friendlyName);
			form.set('Type', input.type);
			form.set('Attributes', JSON.stringify(input.attributes));
			form.set(
				'File',
				new Blob([input.file.bytes as Uint8Array<ArrayBuffer>], { type: input.file.mimeType }),
				input.file.name
			);
			const body = await regulatoryRequest({
				base: NUMBERS_UPLOAD_BASE,
				path: '/v2/RegulatoryCompliance/SupportingDocuments',
				method: 'POST',
				auth: basicAuth(account),
				multipart: form,
				timeoutMs: UPLOAD_TIMEOUT_MS
			});
			return readDocument(body);
		},

		async fetchSupportingDocument(account, sid) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/SupportingDocuments/${requireSid(sid, DOCUMENT_SID, 'twilio_bad_document_sid')}`,
				method: 'GET',
				auth: basicAuth(account)
			});
			return readDocument(body);
		},

		async createBundle(account, input) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: '/v2/RegulatoryCompliance/Bundles',
				method: 'POST',
				auth: basicAuth(account),
				form: {
					FriendlyName: input.friendlyName,
					Email: input.email,
					StatusCallback: input.statusCallback,
					RegulationSid: input.regulationSid,
					IsoCountry: input.isoCountry,
					NumberType: input.numberType,
					EndUserType: input.endUserType
				}
			});
			return readBundle(body);
		},

		async fetchBundle(account, sid) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/Bundles/${requireSid(sid, BUNDLE_SID, 'twilio_bad_bundle_sid')}`,
				method: 'GET',
				auth: basicAuth(account)
			});
			return readBundle(body);
		},

		async updateBundleStatus(account, sid, status) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/Bundles/${requireSid(sid, BUNDLE_SID, 'twilio_bad_bundle_sid')}`,
				method: 'POST',
				auth: basicAuth(account),
				form: { Status: status }
			});
			return readBundle(body);
		},

		async listItemAssignments(account, bundleSid) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/Bundles/${requireSid(bundleSid, BUNDLE_SID, 'twilio_bad_bundle_sid')}/ItemAssignments`,
				method: 'GET',
				auth: basicAuth(account),
				query: { PageSize: '50' }
			});
			return readArray(body, 'results').map(readAssignment);
		},

		async createItemAssignment(account, bundleSid, objectSid) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/Bundles/${requireSid(bundleSid, BUNDLE_SID, 'twilio_bad_bundle_sid')}/ItemAssignments`,
				method: 'POST',
				auth: basicAuth(account),
				form: { ObjectSid: objectSid }
			});
			return readAssignment(body);
		},

		async deleteItemAssignment(account, bundleSid, assignmentSid) {
			await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/Bundles/${requireSid(bundleSid, BUNDLE_SID, 'twilio_bad_bundle_sid')}/ItemAssignments/${requireSid(assignmentSid, ASSIGNMENT_SID, 'twilio_bad_assignment_sid')}`,
				method: 'DELETE',
				auth: basicAuth(account)
			});
		},

		async evaluateBundle(account, bundleSid) {
			const body = await regulatoryRequest({
				base: NUMBERS_BASE,
				path: `/v2/RegulatoryCompliance/Bundles/${requireSid(bundleSid, BUNDLE_SID, 'twilio_bad_bundle_sid')}/Evaluations`,
				method: 'POST',
				auth: basicAuth(account)
			});
			return readEvaluation(body);
		}
	};
}
